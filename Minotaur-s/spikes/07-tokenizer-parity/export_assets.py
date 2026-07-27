# -*- coding: utf-8 -*-
"""
Spike 7 — assets de tokenização + fixture de paridade Python↔Swift.

Motivação: até aqui NENHUMA tokenização em Swift foi validada. O Spike 2c rodou os modelos
com `input_ids` hardcoded num manifest gerado em Python — "os logits batem" foi medido sobre
ids que o Python produziu, não sobre ids que o app vai produzir. Se o tokenizador Swift
divergir do HF, os dois modelos recebem entrada errada e devolvem lixo com aparência de
resultado válido, silenciosamente.

Este script faz duas coisas:

  1. Exporta tokenizer.json / tokenizer_config.json / config.json dos dois modelos para
     Minotaur-s/Resources/Tokenizers/{embeddings,nli}/ — são os arquivos que o
     swift-transformers lê para montar o tokenizador on-device. (config.json do NLI também
     carrega o id2label, que o NLIService usa para saber a ORDEM das classes.)

  2. Gera parity_fixture.json: textos PT-BR reais -> input_ids esperados, incluindo o
     par (premissa, hipótese) do NLI. O TokenizerParityTests em Swift compara contra isso.
     É o gate: se ele falhar, os Services de ML não podem ser considerados corretos.

Código descartável, fora do target iOS.

Reproduzir (venv pinada do Spike 2):
    ../02-coreml-latencia/.venv/bin/python export_assets.py
"""
import json
import os
import shutil

from transformers import AutoTokenizer, AutoConfig

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
DEST = os.path.join(REPO, "Minotaur-s", "Resources", "Tokenizers")

EMBEDDING_MODEL = "sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2"
NLI_MODEL = "MoritzLaurer/multilingual-MiniLMv2-L6-mnli-xnli"

MAX_SEQ = 512

# Afirmações do dataset dos Spikes 3/4/5 + trechos com as características que quebram
# tokenizador: acento, cedilha, número, sigla, aspas tipográficas, hífen, emoji.
TEXTS = [
    "O governo federal anunciou um novo programa de habitação popular.",
    "A inflação medida pelo IPCA ficou em 0,45% no mês de junho.",
    "O STF decidiu por 9 votos a 2 manter a decisão anterior.",
    "Cientistas da USP descobriram uma nova espécie na Amazônia.",
    "A seleção brasileira venceu por 3 a 0 no último amistoso.",
    "O ministro afirmou que “não há qualquer risco de desabastecimento”.",
    "Chuvas fortes atingiram o Rio Grande do Sul nesta terça-feira.",
    "A vacina tem eficácia de 87,5% contra casos graves, segundo a OMS.",
    "O dólar fechou cotado a R$ 5,12 na sexta-feira.",
    "Pesquisa aponta que 62% dos entrevistados apoiam a medida.",
    "A Câmara aprovou o texto-base da proposta em segundo turno.",
    "Terremoto de magnitude 6,1 atingiu a região central do país.",
    "O IBGE divulgou os dados do censo demográfico de 2022.",
    "A empresa anunciou demissão de 1.200 funcionários. 😔",
    "Não há comprovação científica de que o tratamento funcione.",
]

# Pares (premissa=chunk do artigo, hipótese=afirmação do usuário) — a ordem da RF-07.1.
PAIRS = [
    # Entailment próximo (hipótese reafirma a premissa). O modelo é confiável nesta forma.
    (
        "O Instituto Brasileiro de Geografia e Estatística divulgou nesta quinta-feira que a "
        "taxa de desemprego caiu para 6,2% no trimestre encerrado em maio.",
        "A taxa de desemprego caiu para 6,2%.",
    ),
    (
        "A Câmara dos Deputados aprovou nesta terça-feira o texto-base da proposta que altera "
        "as regras de licenciamento ambiental.",
        "A Câmara aprovou o texto-base da proposta sobre licenciamento ambiental.",
    ),
    # Entailment "abstrativo" (a hipótese generaliza o número da premissa). O MiniLMv2-L6
    # classifica isto como NEUTRAL com alta confiança — não é bug do app, é o limite de
    # acurácia aceito na DT-18. Fica na fixture justamente para registrar o comportamento.
    (
        "O Instituto Brasileiro de Geografia e Estatística divulgou nesta quinta-feira que a "
        "taxa de desemprego caiu para 6,2% no trimestre encerrado em maio, o menor patamar "
        "da série histórica iniciada em 2012.",
        "O desemprego no Brasil caiu para o menor nível já registrado.",
    ),
    # Contradiction.
    (
        "A prefeitura informou que o novo hospital municipal será inaugurado apenas em 2027, "
        "após o adiamento das obras por falta de repasse federal.",
        "O hospital municipal foi inaugurado neste ano.",
    ),
    # Sem relação.
    (
        "O time treinou normalmente no centro de treinamento durante a manhã desta segunda-feira.",
        "A inflação subiu no último trimestre.",
    ),
]


def force_unigram_tokenizer_class(prefix: str) -> None:
    """Corrige `tokenizer_class` para XLMRobertaTokenizer quando o modelo é Unigram.

    O swift-transformers escolhe a implementação pelo campo `tokenizer_class` do
    tokenizer_config.json, NÃO pelo `model.type` do tokenizer.json (ver TokenizerModel.from,
    swift-transformers 1.3.3). O mapa dele leva "PreTrainedTokenizer" — a classe genérica
    que o `paraphrase-multilingual-MiniLM-L12-v2` declara — para BPETokenizer, e o
    BPETokenizer aborta com `fatalError("BPETokenizer requires merges")` sobre um vocabulário
    Unigram, que não tem merges.

    É `fatalError`, não exceção: derruba o processo inteiro, e nenhum `try` captura.

    Os dois modelos são XLM-R (`model.type == "Unigram"` em ambos, confirmado no assert
    abaixo), e o de NLI já declara `XLMRobertaTokenizer`. Uniformizar o campo é dizer a
    verdade sobre o tokenizador, não contorná-lo — e quem prova que a correção está certa é
    o TokenizerParityTests, que compara os ids resultantes com os do Hugging Face.
    """
    data_path = os.path.join(DEST, f"{prefix}Tokenizer.json")
    config_path = os.path.join(DEST, f"{prefix}TokenizerConfig.json")

    with open(data_path, encoding="utf-8") as f:
        model_type = json.load(f).get("model", {}).get("type")
    assert model_type == "Unigram", f"[{prefix}] esperava Unigram, veio {model_type!r}"

    with open(config_path, encoding="utf-8") as f:
        config = json.load(f)

    current = config.get("tokenizer_class")
    if current == "XLMRobertaTokenizer":
        print(f"[{prefix}] tokenizer_class já é XLMRobertaTokenizer")
        return

    config["tokenizer_class"] = "XLMRobertaTokenizer"
    with open(config_path, "w", encoding="utf-8") as f:
        json.dump(config, f, ensure_ascii=False, indent=2)
    print(f"[{prefix}] tokenizer_class {current!r} -> 'XLMRobertaTokenizer' "
          f"(senão o swift-transformers cai no BPETokenizer e aborta)")


def export_model(model_id: str, prefix: str, with_labels: bool) -> None:
    """Exporta os assets com nomes PLANOS e distintos por modelo.

    Não usa subpasta por modelo de propósito: o grupo sincronizado do Xcode achata os
    recursos na raiz do bundle, então dois `tokenizer.json` (um por modelo) colidiriam.
    Como o Swift monta o tokenizador a partir de `Config` decodificado dos dados — e não por
    `AutoTokenizer.from(modelFolder:)` — o nome do arquivo é livre.
    """
    os.makedirs(DEST, exist_ok=True)
    staging = os.path.join(DEST, f".{prefix}-staging")

    tok = AutoTokenizer.from_pretrained(model_id)
    tok.save_pretrained(staging)

    # O swift-transformers só precisa de tokenizer.json + tokenizer_config.json. O
    # sentencepiece.bpe.model (slow tokenizer) seria ~5 MB de peso morto no bundle.
    for source, target in (
        ("tokenizer.json", f"{prefix}Tokenizer.json"),
        ("tokenizer_config.json", f"{prefix}TokenizerConfig.json"),
    ):
        shutil.move(os.path.join(staging, source), os.path.join(DEST, target))
        print(f"[{prefix}] {source} -> {target}")
    shutil.rmtree(staging)

    force_unigram_tokenizer_class(prefix)

    if with_labels:
        # id2label do NLI: a ORDEM das classes na saída do modelo. Assumir
        # entailment/neutral/contradiction sem ler isto é como o pipeline erra em silêncio.
        cfg = AutoConfig.from_pretrained(model_id)
        path = os.path.join(DEST, f"{prefix}Labels.json")
        with open(path, "w", encoding="utf-8") as f:
            json.dump({"id2label": {str(k): v for k, v in cfg.id2label.items()}}, f,
                      ensure_ascii=False, indent=2)
        print(f"[{prefix}] id2label = {cfg.id2label} -> {os.path.basename(path)}")


def build_fixture() -> None:
    """Gera a referência do HF: ids de tokenização E probabilidades do NLI.

    As probabilidades entram porque asserção sobre "o rótulo esperado" é frágil de outra
    forma: o MiniLMv2-L6 acerta ~90% em PT-BR (DT-18), então escrever no teste o rótulo que
    um humano daria mede a acurácia do modelo, não a corretude do app. Comparar com a saída
    do PyTorch para o MESMO par mede o que interessa aqui — se o caminho Swift
    (tokenização + Core ML + softmax) reproduz a referência.
    """
    import torch
    from transformers import AutoModelForSequenceClassification

    emb_tok = AutoTokenizer.from_pretrained(EMBEDDING_MODEL)
    nli_tok = AutoTokenizer.from_pretrained(NLI_MODEL)
    nli_model = AutoModelForSequenceClassification.from_pretrained(NLI_MODEL).eval()

    fixture = {
        "note": "Gerado por spikes/07-tokenizer-parity/export_assets.py. "
                "Referência do HF para o gate de paridade em Swift.",
        "embedding_model": EMBEDDING_MODEL,
        "nli_model": NLI_MODEL,
        "single": [],
        "pairs": [],
    }

    for text in TEXTS:
        enc = emb_tok(text, truncation=True, max_length=MAX_SEQ)
        fixture["single"].append({
            "text": text,
            "input_ids": enc["input_ids"],
            "attention_mask": enc["attention_mask"],
        })

    id2label = {int(k): str(v) for k, v in nli_model.config.id2label.items()}
    for premise, hypothesis in PAIRS:
        enc = nli_tok(premise, hypothesis, truncation=True, max_length=MAX_SEQ,
                      return_attention_mask=True)
        with torch.no_grad():
            logits = nli_model(
                input_ids=torch.tensor([enc["input_ids"]]),
                attention_mask=torch.tensor([enc["attention_mask"]]),
            ).logits[0]
        probs = torch.softmax(logits, dim=-1)
        top = int(probs.argmax())

        fixture["pairs"].append({
            "premise": premise,
            "hypothesis": hypothesis,
            "input_ids": enc["input_ids"],
            "attention_mask": enc["attention_mask"],
            "expected_label": id2label[top],
            "expected_confidence": float(probs[top]),
        })
        print(f"  par -> {id2label[top]} ({float(probs[top]):.4f}): {hypothesis[:50]}")

    path = os.path.join(HERE, "parity_fixture.json")
    with open(path, "w", encoding="utf-8") as f:
        json.dump(fixture, f, ensure_ascii=False, indent=2)
    print(f"\nfixture: {path} "
          f"({len(fixture['single'])} textos, {len(fixture['pairs'])} pares)")

    # Tokens especiais do XLM-R, para o Swift montar o par manualmente: o swift-transformers
    # 1.3.3 NÃO tem encode(text:textPair:), então o app precisa replicar
    # `<s> A </s></s> B </s>` na mão. Estes ids são a referência.
    print(f"bos/cls = {nli_tok.cls_token} -> {nli_tok.cls_token_id}")
    print(f"eos/sep = {nli_tok.sep_token} -> {nli_tok.sep_token_id}")
    print(f"pad     = {nli_tok.pad_token} -> {nli_tok.pad_token_id}")


if __name__ == "__main__":
    if os.path.isdir(DEST):
        shutil.rmtree(DEST)
    export_model(EMBEDDING_MODEL, "Embeddings", with_labels=False)
    export_model(NLI_MODEL, "NLI", with_labels=True)
    build_fixture()
