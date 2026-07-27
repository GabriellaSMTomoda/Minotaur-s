"""
Roda as duas abordagens de extração (A = trafilatura, B = heurística manual)
sobre todo HTML baixado por download.py, e monta uma tabela de resultados
por URL com as colunas pedidas no spike:

- qual abordagem funcionou melhor (ou nenhuma)
- texto extraído >= 200 caracteres?
- texto limpo (é o artigo) ou poluído com menu/ads/relacionados? (heurística
  automática + nota para revisão manual quando ambígua)
- indício de paywall (palavras-chave típicas)
- indício de dependência de JS (corpo do HTML quase vazio / div#root vazio)
- tempo de download (do manifest)

Saída: results.json (dados brutos) + results.md (tabela) para consumo do
RESULTADO.md.
"""
import json
import re
from pathlib import Path

from extract_a_trafilatura import extract as extract_a
from extract_b_heuristic import extract as extract_b

MIN_CHARS = 200

PAYWALL_HINTS = re.compile(
    r"(assine (já|agora|para continuar)|conteúdo exclusivo para assinantes|"
    r"para continuar lendo|acesso ilimitado|subscribe to continue|"
    r"subscriber(s)? only|register to continue|paywall|"
    r"you('| a)ve reached your (free )?(article )?limit|"
    r"crie sua conta gratuita|faça login para continuar)",
    re.I,
)

# indício de "poluição" — sobrou lixo de navegação/relacionadas mesmo após a
# extração (checagem automática grosseira, best-effort)
NOISE_HINTS = re.compile(
    r"(leia também|leia mais|veja também|matérias relacionadas|compartilhe|"
    r"compartilhar no|newsletter|assine a newsletter|todos os direitos "
    r"reservados|política de privacidade|termos de uso|siga (o|a) .* no "
    r"(instagram|twitter|facebook)|menu principal|pular para o conteúdo)",
    re.I,
)


def paywall_signal(html: str, text_a: str | None, text_b: str | None) -> bool:
    """Sinal de paywall real: o texto EXTRAÍDO (não a página toda) é curto e
    termina com uma chamada de assinatura, ou nenhuma das duas abordagens
    consegue passar de pouco texto mesmo a página tendo HTML robusto. CTAs de
    newsletter/assinatura em rodapé aparecem em quase toda página brasileira
    de notícia mesmo sem paywall — checar a página toda inteira gera falso
    positivo, por isso a checagem é sobre o texto já extraído."""
    for text in (text_a, text_b):
        if text and PAYWALL_HINTS.search(text):
            return True
    # nenhum texto extraído com tamanho razoável, mas a chamada de assinatura
    # aparece perto do fim do <body> visível (não em rodapé genérico) —
    # aproximação grosseira, best-effort
    if (not text_a or len(text_a) < MIN_CHARS) and (not text_b or len(text_b) < MIN_CHARS):
        if PAYWALL_HINTS.search(html):
            return True
    return False


def js_dependency_signal(html: str) -> bool:
    """Heurística grosseira: HTML muito curto para ter um artigo, ou marcas
    típicas de SPA com corpo vazio (div#root/#app/#__next vazio)."""
    if len(html) < 3000:
        return True
    empty_root = re.search(
        r'<div id="(root|app|__next)"\s*>\s*</div>', html, re.I
    )
    if empty_root:
        return True
    # muito poucas tags <p> com texto substancial é outro indício
    p_text_total = sum(len(t) for t in re.findall(r"<p[^>]*>(.*?)</p>", html, re.S))
    if p_text_total < 150 and len(html) > 20000:
        return True
    return False


def noise_score(text: str) -> int:
    return len(NOISE_HINTS.findall(text or ""))


def evaluate(text: str | None) -> dict:
    if not text:
        return {"chars": 0, "ok_length": False, "noise_hits": None, "sample": None}
    chars = len(text)
    return {
        "chars": chars,
        "ok_length": chars >= MIN_CHARS,
        "noise_hits": noise_score(text),
        "sample": text[:220].replace("\n", " "),
    }


def main():
    manifest = json.loads(Path("download_manifest.json").read_text())
    results = []

    for entry in manifest:
        row = {
            "domain": entry["domain"],
            "url": entry["url"],
            "download_ok": entry["error"] is None,
            "download_error": entry["error"],
            "elapsed_s": entry["elapsed_s"],
        }

        if entry["error"] is not None or not entry.get("html_file"):
            row["approach_a"] = None
            row["approach_b"] = None
            row["js_dependent"] = None
            row["paywall"] = None
            row["winner"] = "N/A (download falhou)"
            results.append(row)
            continue

        html = Path(entry["html_file"]).read_text(encoding="utf-8", errors="replace")

        try:
            text_a = extract_a(html, url=entry["url"])
        except Exception as exc:
            text_a = None
            row["error_a"] = str(exc)
        try:
            text_b = extract_b(html, url=entry["url"])
        except Exception as exc:
            text_b = None
            row["error_b"] = str(exc)

        eval_a = evaluate(text_a)
        eval_b = evaluate(text_b)

        row["approach_a"] = eval_a
        row["approach_b"] = eval_b
        row["js_dependent"] = js_dependency_signal(html)
        row["paywall"] = paywall_signal(html, text_a, text_b)

        # decide vencedor: prioriza ok_length, depois menor ruído, depois
        # mais texto (chunk maior tende a ser o artigo completo, não um
        # trecho perdido)
        def score(e):
            if not e["ok_length"]:
                return (-1, 0, 0)
            noise = e["noise_hits"] if e["noise_hits"] is not None else 99
            return (1, -noise, e["chars"])

        sa, sb = score(eval_a), score(eval_b)
        if sa[0] == -1 and sb[0] == -1:
            row["winner"] = "nenhuma"
        elif sa > sb:
            row["winner"] = "A (trafilatura)"
        elif sb > sa:
            row["winner"] = "B (heurística)"
        else:
            row["winner"] = "empate"

        results.append(row)

    Path("results.json").write_text(json.dumps(results, ensure_ascii=False, indent=2))

    # markdown table
    lines = [
        "| Domínio | Download | JS-dep? | Paywall? | A: chars | A ok? | B: chars | B ok? | Vencedor |",
        "|---|---|:---:|:---:|---:|:---:|---:|:---:|---|",
    ]
    for r in results:
        if not r["download_ok"]:
            lines.append(
                f"| {r['domain']} | FALHOU ({r['download_error']}) | - | - | - | - | - | - | N/A |"
            )
            continue
        a, b = r["approach_a"], r["approach_b"]
        lines.append(
            f"| {r['domain']} | OK ({r['elapsed_s']}s) | "
            f"{'sim' if r['js_dependent'] else 'não'} | "
            f"{'sim' if r['paywall'] else 'não'} | "
            f"{a['chars']} | {'sim' if a['ok_length'] else 'não'} | "
            f"{b['chars']} | {'sim' if b['ok_length'] else 'não'} | "
            f"{r['winner']} |"
        )
    Path("results.md").write_text("\n".join(lines), encoding="utf-8")

    # resumo agregado
    by_domain = {}
    for r in results:
        by_domain.setdefault(r["domain"], []).append(r)

    usable_domains = []
    for domain, rows in by_domain.items():
        domain_usable = False
        for r in rows:
            if not r["download_ok"]:
                continue
            if r["js_dependent"] or r["paywall"]:
                continue
            a, b = r["approach_a"], r["approach_b"]
            if a["ok_length"] or b["ok_length"]:
                domain_usable = True
        if domain_usable:
            usable_domains.append(domain)

    total_domains = len(by_domain)
    print(f"Domínios utilizáveis (>=1 URL ok, sem paywall/JS, >=200 chars): "
          f"{len(usable_domains)}/{total_domains}")
    print("Utilizáveis:", sorted(usable_domains))
    print("NÃO utilizáveis:", sorted(set(by_domain) - set(usable_domains)))

    wins_a = sum(1 for r in results if r.get("winner") == "A (trafilatura)")
    wins_b = sum(1 for r in results if r.get("winner") == "B (heurística)")
    ties = sum(1 for r in results if r.get("winner") == "empate")
    neither = sum(1 for r in results if r.get("winner") == "nenhuma")
    na = sum(1 for r in results if r.get("winner", "").startswith("N/A"))
    print(f"A venceu: {wins_a} | B venceu: {wins_b} | empate: {ties} | nenhuma: {neither} | N/A: {na}")


if __name__ == "__main__":
    main()
