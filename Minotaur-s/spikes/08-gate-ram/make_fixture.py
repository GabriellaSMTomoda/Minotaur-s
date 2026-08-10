# -*- coding: utf-8 -*-
"""
SPIKE 8 — gerador da carga de trabalho do gate de RAM (item aberto 27).

O que este script produz: `build/fixture.json`, com as SEQUÊNCIAS DE TOKENS que
o harness iOS vai alimentar aos dois modelos. Não produz texto para o harness
tokenizar — o tokenizador WordPiece em Swift é trabalho da Etapa 2, e arrastá-lo
para cá misturaria o gate com a integração.

Por que isso é honesto para medir RAM: o custo de memória de uma predição Core ML
é função do modelo e do COMPRIMENTO da sequência, não de quais ids ela carrega.
O que precisa ser real, e é, são os comprimentos — eles vêm de texto de artigo
real, chunkado pelas mesmas regras do `TextChunker` do app, e tokenizado pelos
tokenizadores reais dos dois modelos.

Fontes do texto (nada sintético):
  - artigos: HTML real baixado no Spike 3 (`spikes/03-extracao-texto/html/`),
    extraído com trafilatura, dos domínios da allowlist;
  - claims e pares de NLI: `spikes/07-nli-ptbr-negacao/dataset.py` — os mesmos
    3 claims que falharam em produção.

Carga alvo (a que o usuário pediu para o gate): 180 embeddings + 15 pares de
NLI, distribuídos como 5 artigos × 36 chunks, com 3 pares por artigo — que é o
formato do `VerificationPipeline.analyze` (RF-04.3, RF-06.6).

Duas etapas porque os venvs dos spikes anteriores são separados (trafilatura
vive no do Spike 3, transformers no do Spike 2):

  ../03-extracao-texto/.venv/bin/python make_fixture.py --extract
  ../02-coreml-latencia/.venv/bin/python make_fixture.py
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SPIKES = os.path.dirname(HERE)
BUILD = os.path.join(HERE, "build")

EMBEDDINGS_ID = "sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2"
NLI_ID = "giotvr/bertimbau_large_plue_mnli_fine_tuned"
# Modelo NLI que está em produção hoje (DT-18 revisada 1ª vez). Entra aqui só como
# linha de comparação: sem saber o pico de RAM de HOJE não dá para dizer quanto da
# conta é da troca e quanto já era do pipeline.
NLI_ATUAL_ID = "MoritzLaurer/multilingual-MiniLMv2-L6-mnli-xnli"

MAX_SEQ = 512          # XLMRTokenizer.maxSequenceLength / limite do NLI (RF-06.2)
ARTICLES = 5           # RF-04.3 — até 5 fontes por verificação
CHUNKS_PER_ARTICLE = 36  # 5 × 36 = 180
PAIRS_PER_ARTICLE = 3    # RF-06.6 / DT-08 — top-3 chunks por artigo

# Os 3 claims que falharam em produção (risco materializado, 7.1).
CLAIMS = [
    "A Terra é plana.",
    "Vacina da gripe causa infarto.",
    "Brasileiro encontrou cura do câncer.",
]


# ---------------------------------------------------------------------------
# Porte das regras de chunking do app (TextChunker.swift + ChunkQualityFilter)
# ---------------------------------------------------------------------------
# É um PORTE APROXIMADO, e a aproximação é declarada: o objetivo aqui é a
# distribuição de comprimentos dos chunks, não reproduzir chunk a chunk o que o
# Swift produziria. O que é fiel: divisão por parágrafo, sobreposição de 1 frase,
# subdivisão pelo mesmo orçamento de tokens e a mesma estimativa conservadora.

def conservative_token_estimate(text):
    """`TextChunker.conservativeTokenEstimate` — max(chars/3, palavras)."""
    by_chars = -(-len(text) // 3)
    by_words = len(text.split())
    return max(by_chars, by_words)


def sentences(text):
    """Aproximação do `NLTokenizer(unit: .sentence)` em PT."""
    parts = re.split(r"(?<=[.!?])\s+", text.strip())
    return [p.strip() for p in parts if p.strip()]


def is_boilerplate(line):
    """Recorte mínimo da DT-33: linha curta demais ou sem verbo aparente."""
    if len(line) < 40:
        return True
    if re.match(r"^(Por|Foto|Leia também|Compartilhe|Publicado em)\b", line, re.I):
        return True
    return False


def chunk_text(text, max_tokens):
    """`TextChunker.chunks(from:)`: parágrafo + sobreposição de 1 frase."""
    chunks = []
    overlap = None
    for para in [p.strip() for p in text.split("\n")]:
        if not para or is_boilerplate(para):
            continue
        body = (overlap + " " + para) if overlap else para
        produced = subdivide(body, max_tokens)
        if not produced:
            continue
        chunks.extend(produced)
        last = sentences(produced[-1])
        overlap = last[-1] if last else None
    return chunks


def subdivide(text, max_tokens):
    if not text:
        return []
    if conservative_token_estimate(text) <= max_tokens:
        return [text]
    sents = sentences(text)
    if len(sents) <= 1:
        return split_by_words(text, max_tokens)
    pieces, current = [], []
    for s in sents:
        units = [s] if conservative_token_estimate(s) <= max_tokens else split_by_words(s, max_tokens)
        for unit in units:
            if not current:
                current = [unit]
                continue
            if conservative_token_estimate(" ".join(current + [unit])) <= max_tokens:
                current.append(unit)
                continue
            pieces.append(" ".join(current))
            previous = current[-1]
            with_overlap = previous + " " + unit
            current = [previous, unit] if conservative_token_estimate(with_overlap) <= max_tokens else [unit]
    if current:
        pieces.append(" ".join(current))
    return pieces


def split_by_words(text, max_tokens):
    words = text.split()
    if not words:
        return []
    pieces, current = [], []
    for w in words:
        if not current:
            current = [w]
            continue
        if conservative_token_estimate(" ".join(current + [w])) <= max_tokens:
            current.append(w)
        else:
            pieces.append(" ".join(current))
            current = [w]
    if current:
        pieces.append(" ".join(current))
    return pieces


# ---------------------------------------------------------------------------
# Texto real dos artigos (Spike 3)
# ---------------------------------------------------------------------------

ARTICLES_JSON = os.path.join(BUILD, "articles.json")


def load_real_articles():
    """Lê o texto extraído por `--extract` (etapa 1)."""
    if not os.path.exists(ARTICLES_JSON):
        print(f"ERRO: {ARTICLES_JSON} não existe. Rode antes:\n"
              f"  ../03-extracao-texto/.venv/bin/python make_fixture.py --extract",
              file=sys.stderr)
        sys.exit(1)
    with open(ARTICLES_JSON, "r", encoding="utf-8") as fh:
        return [(a["domain"], a["name"], a["text"]) for a in json.load(fh)]


def extract_real_articles():
    """Etapa 1: extrai texto dos HTMLs reais do Spike 3, dos maiores para os menores."""
    import trafilatura

    os.makedirs(BUILD, exist_ok=True)
    html_root = os.path.join(SPIKES, "03-extracao-texto", "html")
    texts = []
    for domain in sorted(os.listdir(html_root)):
        ddir = os.path.join(html_root, domain)
        if not os.path.isdir(ddir):
            continue
        for name in sorted(os.listdir(ddir)):
            path = os.path.join(ddir, name)
            try:
                with open(path, "r", encoding="utf-8", errors="ignore") as fh:
                    raw = fh.read()
            except OSError:
                continue
            extracted = trafilatura.extract(raw, include_comments=False, include_tables=False)
            if extracted and len(extracted) >= 1000:
                texts.append({"domain": domain, "name": name, "text": extracted})
    texts.sort(key=lambda t: len(t["text"]), reverse=True)
    with open(ARTICLES_JSON, "w", encoding="utf-8") as fh:
        json.dump(texts, fh)
    print(f"OK -> {ARTICLES_JSON}: {len(texts)} artigos "
          f"(maior {len(texts[0]['text'])} chars, menor {len(texts[-1]['text'])} chars)")
    return 0


def main():
    os.makedirs(BUILD, exist_ok=True)
    from transformers import AutoTokenizer

    print("carregando tokenizadores reais…")
    emb_tok = AutoTokenizer.from_pretrained(EMBEDDINGS_ID)
    nli_tok = AutoTokenizer.from_pretrained(NLI_ID)
    atual_tok = AutoTokenizer.from_pretrained(NLI_ATUAL_ID)
    print("  embeddings:", type(emb_tok).__name__, "vocab", emb_tok.vocab_size)
    print("  nli       :", type(nli_tok).__name__, "vocab", nli_tok.vocab_size)
    print("  nli atual :", type(atual_tok).__name__, "vocab", atual_tok.vocab_size)

    # Orçamento de chunk do app: 512 - 4 especiais - tokens da afirmação
    # (`VerificationPipeline.chunker(for:)`). Usa o maior dos 3 claims, que é o
    # que aperta menos o chunk — pior caso de comprimento de premissa.
    claim_budget = max(conservative_token_estimate(c) for c in CLAIMS)
    max_chunk_tokens = MAX_SEQ - 4 - claim_budget
    print(f"orçamento de chunk: {max_chunk_tokens} tokens (claim mais longo = {claim_budget})")

    print("extraindo artigos reais do Spike 3…")
    articles = load_real_articles()
    print(f"  {len(articles)} artigos com texto aproveitável")

    # Monta 5 grupos de 36 chunks. Artigo real raramente dá 36 chunks sozinho —
    # quando faltar, o grupo é completado com chunks do próximo artigo real. A
    # carga total (180) é a que o gate pede; a origem continua sendo texto real.
    groups, pool, sources = [], [], []
    for domain, name, text in articles:
        cs = chunk_text(text, max_chunk_tokens)
        if not cs:
            continue
        pool.extend(cs)
        sources.append(f"{domain}/{name} ({len(cs)} chunks)")
        if len(pool) >= ARTICLES * CHUNKS_PER_ARTICLE:
            break

    if len(pool) < ARTICLES * CHUNKS_PER_ARTICLE:
        print(f"ERRO: só {len(pool)} chunks reais disponíveis", file=sys.stderr)
        return 1

    for i in range(ARTICLES):
        groups.append(pool[i * CHUNKS_PER_ARTICLE:(i + 1) * CHUNKS_PER_ARTICLE])

    # ---- embeddings: ids no formato do XLMRTokenizer.encode ----
    bos, eos = emb_tok.bos_token_id, emb_tok.eos_token_id
    fixture_articles = []
    for gi, group in enumerate(groups):
        emb_inputs = []
        for chunk in group:
            body = emb_tok(chunk, add_special_tokens=False)["input_ids"]
            ids = [bos] + body[:MAX_SEQ - 2] + [eos]
            emb_inputs.append(ids)

        # ---- NLI: top-3 do artigo. Sem rodar similaridade aqui — os 3 chunks
        # mais LONGOS são o pior caso de comprimento de sequência, que é o que
        # move a RAM. O claim rotaciona entre os 3 que falharam em produção.
        longest = sorted(group, key=len, reverse=True)[:PAIRS_PER_ARTICLE]
        nli_inputs = []
        nli_atual_inputs = []
        for pi, premise in enumerate(longest):
            claim = CLAIMS[(gi + pi) % len(CLAIMS)]
            # Modelo atual: par no formato XLM-R montado à mão, exatamente como
            # `XLMRTokenizer.encodePair` faz no app — `<s> premissa </s></s> hipótese </s>`.
            hyp_ids = atual_tok(claim, add_special_tokens=False)["input_ids"]
            prem_ids = atual_tok(premise, add_special_tokens=False)["input_ids"]
            budget = max(0, MAX_SEQ - 4 - len(hyp_ids))
            atual_ids = ([atual_tok.bos_token_id] + prem_ids[:budget]
                         + [atual_tok.eos_token_id, atual_tok.eos_token_id]
                         + hyp_ids + [atual_tok.eos_token_id])
            nli_atual_inputs.append({
                "input_ids": atual_ids,
                "attention_mask": [1] * len(atual_ids),
                "claim": claim,
            })
            enc = nli_tok(
                premise, claim,
                truncation="only_first", max_length=MAX_SEQ,
                add_special_tokens=True,
            )
            nli_inputs.append({
                "input_ids": enc["input_ids"],
                "attention_mask": enc["attention_mask"],
                "token_type_ids": enc["token_type_ids"],
                "claim": claim,
            })

        fixture_articles.append({
            "index": gi,
            "embedding_inputs": emb_inputs,
            "nli_inputs": nli_inputs,
            "nli_atual_inputs": nli_atual_inputs,
        })

    emb_lens = [len(i) for a in fixture_articles for i in a["embedding_inputs"]]
    nli_lens = [len(p["input_ids"]) for a in fixture_articles for p in a["nli_inputs"]]

    # ---- PIOR CASO ----------------------------------------------------------
    # Os chunks reais destes artigos têm parágrafos curtos e param em ~216
    # tokens, bem abaixo do teto. Mas a RAM de uma predição Core ML cresce com o
    # comprimento da sequência, e o `TextChunker` PODE produzir chunk de até 496
    # tokens (orçamento acima) num artigo de parágrafos longos. Medir só o caso
    # médio deixaria o gate frouxo justamente onde ele importa.
    #
    # Continua sendo texto real: os chunks reais são concatenados até encher a
    # sequência, e o tokenizador corta no limite. O que muda é o comprimento.
    joined = " ".join(pool)
    long_body = emb_tok(joined, add_special_tokens=False)["input_ids"]
    worst_emb = [bos] + long_body[:MAX_SEQ - 2] + [eos]

    long_premise = " ".join(pool[:40])
    worst_nli = []
    for ci, claim in enumerate(CLAIMS):
        enc = nli_tok(long_premise, claim, truncation="only_first",
                      max_length=MAX_SEQ, add_special_tokens=True)
        worst_nli.append({
            "input_ids": enc["input_ids"],
            "attention_mask": enc["attention_mask"],
            "token_type_ids": enc["token_type_ids"],
            "claim": claim,
        })

    fixture_worst = {
        "embedding_input": worst_emb,
        "nli_inputs": worst_nli,
        "embedding_len": len(worst_emb),
        "nli_len": [len(p["input_ids"]) for p in worst_nli],
    }

    fixture = {
        "generated_by": "spikes/08-gate-ram/make_fixture.py",
        "embeddings_model": EMBEDDINGS_ID,
        "nli_model": NLI_ID,
        "max_chunk_tokens_estimate": max_chunk_tokens,
        "articles": fixture_articles,
        "worst_case": fixture_worst,
        "stats": {
            "embedding_count": len(emb_lens),
            "embedding_len_min": min(emb_lens),
            "embedding_len_max": max(emb_lens),
            "embedding_len_mean": sum(emb_lens) / len(emb_lens),
            "nli_count": len(nli_lens),
            "nli_len_min": min(nli_lens),
            "nli_len_max": max(nli_lens),
            "nli_len_mean": sum(nli_lens) / len(nli_lens),
            "worst_embedding_len": fixture_worst["embedding_len"],
            "worst_nli_len": fixture_worst["nli_len"],
        },
        "text_sources": sources,
    }

    out = os.path.join(BUILD, "fixture.json")
    with open(out, "w", encoding="utf-8") as fh:
        json.dump(fixture, fh)

    print(json.dumps(fixture["stats"], indent=2))
    print("fontes de texto:")
    for s in sources:
        print("  -", s)
    print(f"OK -> {out} ({os.path.getsize(out) / 1024:.0f} KB)")
    return 0


if __name__ == "__main__":
    if "--extract" in sys.argv:
        sys.exit(extract_real_articles())
    sys.exit(main())
