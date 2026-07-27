"""Gera a tabela markdown por domínio/URL para colar no RESULTADO.md, com
avaliação qualitativa (limpo/poluído/insuficiente) combinando as duas
abordagens: usa o texto da abordagem que venceu (compare.py já decide o
vencedor) e aplica a nota qualitativa sobre esse texto."""
import json
from pathlib import Path

results = json.loads(Path("results.json").read_text())

lines = [
    "| Domínio | URL (resumida) | Tempo download | JS-dep? | Paywall? | Vencedor | Chars (vencedor) | >=200 chars? | Qualidade |",
    "|---|---|---:|:---:|:---:|---|---:|:---:|---|",
]

for r in results:
    url_short = r["url"].replace("https://", "").replace("http://", "")
    if len(url_short) > 55:
        url_short = url_short[:52] + "..."
    if not r["download_ok"]:
        lines.append(
            f"| {r['domain']} | {url_short} | - | - | - | - | - | - | **bloqueado**: {r['download_error']} |"
        )
        continue

    a, b = r["approach_a"], r["approach_b"]
    winner = r["winner"]
    if winner.startswith("A"):
        chosen = a
    elif winner.startswith("B"):
        chosen = b
    else:
        chosen = a if a["chars"] >= b["chars"] else b

    ok = chosen["ok_length"]
    noise = chosen["noise_hits"] or 0
    if not ok:
        quality = "insuficiente (< 200 chars)"
    elif noise == 0:
        quality = "limpo"
    else:
        quality = f"limpo, ruído leve ({noise} ocorrência{'s' if noise > 1 else ''})"

    lines.append(
        f"| {r['domain']} | {url_short} | {r['elapsed_s']}s | "
        f"{'sim' if r['js_dependent'] else 'não'} | "
        f"{'sim' if r['paywall'] else 'não'} | "
        f"{winner} | {chosen['chars']} | {'sim' if ok else 'não'} | {quality} |"
    )

Path("table_full.md").write_text("\n".join(lines), encoding="utf-8")
print(f"{len(results)} linhas escritas em table_full.md")
