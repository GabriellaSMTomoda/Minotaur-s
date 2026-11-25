"""Runs the harness over the dev set and writes a report with per-case traces.

Usage:
  uv run python run_dev.py collect            # network (cached), 1 Tavily credit per uncached claim
  uv run python run_dev.py analyze --mode baseline --run baseline
  uv run python run_dev.py report --run baseline [--aggregator baseline]
"""
from __future__ import annotations

import argparse
import json
import math
import pickle
import sys
from collections import Counter
from pathlib import Path

import pipeline as p
import textutil as tu

HERE = Path(__file__).resolve().parent
DATA = HERE.parent / "data" / "dev_claims.jsonl"
ARTIFACTS = HERE.parent / "artifacts" / "harness"
COLLECTED = HERE.parent / "snapshots" / "collected"
VERDICTS = ["CONFIRMADO", "CONTRADITO", "DIVERGENTE", "SEM_INFORMACAO", "NAO_ENCONTRADO", "ERRO_LEITURA"]


def records(only=None):
    rows = [json.loads(l) for l in DATA.read_text().splitlines() if l.strip()]
    return [r for r in rows if not only or r["id"] in only or r["group"] in only]


def cmd_collect(args):
    COLLECTED.mkdir(parents=True, exist_ok=True)
    for r in records(args.only):
        path = COLLECTED / f"{r['id']}{args.suffix}.pkl"
        if path.exists() and not args.force:
            continue
        ctx = tu.claim_context(r["claim"], p.reference_for(r))
        try:
            col = p.collect(ctx, max_queries=args.max_queries, force_expand=args.force_expand)
        except Exception as e:  # noqa: BLE001
            print("ERR", r["id"], e, file=sys.stderr)
            continue
        path.write_bytes(pickle.dumps({"ctx": ctx, **col}))
        print(r["id"], len(col["items"]), "items", len(col["articles"]), "articles", col["errors"] or "")


def cmd_collect_wiki(args):
    import wiki
    for r in records(args.only):
        path = COLLECTED / f"{r['id']}.pkl"
        if not path.exists():
            continue
        col = pickle.loads(path.read_bytes())
        if "wiki_articles" in col and not args.force:
            continue
        col["wiki_articles"] = wiki.collect_wiki(col["ctx"])
        path.write_bytes(pickle.dumps(col))
        print(r["id"], [a["title"] for a in col["wiki_articles"]])


def analyzer(mode):
    import analysis
    if mode == "baseline":
        return analysis.analyze_baseline
    import evidence
    return evidence.ANALYZERS[mode]


def cmd_analyze(args):
    out = ARTIFACTS / args.run
    out.mkdir(parents=True, exist_ok=True)
    fn = analyzer(args.mode)
    for r in records(args.only):
        path = COLLECTED / f"{r['id']}.pkl"
        if not path.exists():
            continue
        col = pickle.loads(path.read_bytes())
        wiki_articles = col.get("wiki_articles", [])
        variant = COLLECTED / f"{r['id']}{args.suffix}.pkl"
        if args.suffix and variant.exists():
            col = pickle.loads(variant.read_bytes())
        if args.wiki_lead:  # only the article's lead section (first characters of the plain extract)
            wiki_articles = [{**a, "text": a["text"][:args.wiki_lead].rsplit(".", 1)[0] + "."} for a in wiki_articles]
        arts = col["articles"] + (wiki_articles if args.with_wiki else [])
        res = fn(col["ctx"], arts)
        res.update({"id": r["id"], "items": len(col["items"]) + (len(col.get("wiki_articles", [])) if args.with_wiki else 0),
                    "articles": len(arts),
                    "queries": col["queries"], "claim": col["ctx"]["text"], "ctx_kind": col["ctx"]["kind"]})
        (out / f"{r['id']}.json").write_text(json.dumps(res, ensure_ascii=False, indent=1, default=str))
        print(r["id"], res["pairs"], "pairs", file=sys.stderr)


def wilson(k, n, z=1.96):
    if n == 0:
        return (None, None)
    ph = k / n
    d = 1 + z * z / n
    c = (ph + z * z / (2 * n)) / d
    h = z * math.sqrt(ph * (1 - ph) / n + z * z / (4 * n * n)) / d
    return (round(c - h, 3), round(c + h, 3))


def decide(res, aggregator, policy):
    import analysis
    if res["items"] == 0:
        return "NAO_ENCONTRADO", []
    if res["articles"] == 0:
        return "ERRO_LEITURA", []
    if not res["sources"]:
        return "SEM_INFORMACAO", []
    if aggregator == "baseline":
        return analysis.verdict_baseline(res["sources"])
    import evidence
    return evidence.aggregate(res["sources"], res.get("ctx_kind", "timeless"), policy, res["claim"])


def evaluate(run, aggregator="baseline", policy=None, only=None):
    rows = []
    for r in records(only):
        path = ARTIFACTS / run / f"{r['id']}.json"
        if not path.exists():
            continue
        res = json.loads(path.read_text())
        verdict, votes = decide(res, aggregator, policy)
        rows.append({"record": r, "verdict": verdict, "votes": votes, "res": res})
    return rows


def summarize(rows):
    n = len(rows)
    correct = sum(x["verdict"] == x["record"]["verdict"] for x in rows)
    opposite = sum({x["verdict"], x["record"]["verdict"]} == {"CONFIRMADO", "CONTRADITO"} for x in rows)
    div = sum(x["verdict"] == "DIVERGENTE" for x in rows)
    groups = {}
    for x in rows:
        g = groups.setdefault(x["record"]["group"], [0, 0])
        g[0] += x["verdict"] == x["record"]["verdict"]
        g[1] += 1
    return {"n": n, "correct": correct, "accuracy": round(correct / n, 3) if n else None,
            "accuracy_ci95": wilson(correct, n), "divergente": div, "wrong_direction": opposite,
            "by_group": {k: f"{a}/{b}" for k, (a, b) in sorted(groups.items())},
            "distribution": dict(Counter(x["verdict"] for x in rows))}


def cmd_report(args):
    policy = json.loads(Path(args.policy).read_text()) if args.policy else None
    rows = evaluate(args.run, args.aggregator, policy, args.only)
    s = summarize(rows)
    lines = [f"# Relatório do harness — run `{args.run}`, agregador `{args.aggregator}`", "",
             "> Conjunto **dev, não-gold** (`evaluation/data/dev_claims.jsonl`, revisão pendente). "
             "Não é teste cego; não usar como métrica de promoção.", "",
             f"- Casos: **{s['n']}** · acertos: **{s['correct']}** ({s['accuracy']}, IC95% {s['accuracy_ci95']})",
             f"- Fontes divergentes: **{s['divergente']}** · direção oposta (erro grave): **{s['wrong_direction']}**",
             f"- Por grupo: {s['by_group']}", "", "## Matriz (linhas = esperado, colunas = previsto)", "",
             "| esperado \\ previsto | " + " | ".join(VERDICTS) + " |", "|---|" + "---|" * len(VERDICTS)]
    for exp in ("CONFIRMADO", "CONTRADITO"):
        cnt = Counter(x["verdict"] for x in rows if x["record"]["verdict"] == exp)
        lines.append(f"| {exp} | " + " | ".join(str(cnt.get(v, 0)) for v in VERDICTS) + " |")
    lines += ["", "## Erros (trace)", ""]
    for x in rows:
        if x["verdict"] == x["record"]["verdict"]:
            continue
        r = x["record"]
        lines.append(f"### {r['id']} — esperado {r['verdict']}, previsto **{x['verdict']}**")
        lines.append(f"> {r['claim']}")
        lines.append(f"- itens {x['res']['items']}, artigos {x['res']['articles']}, fontes {len(x['res']['sources'])}, pares {x['res']['pairs']}")
        for v in x["votes"][:6]:
            lines.append(f"  - voto `{v['label']}` {v.get('confidence', v.get('score', 0)):.2f} [{v['origin']}] {v.get('text', '')[:160]!r}")
        lines.append("")
    out = ARTIFACTS / f"report-{args.run}-{args.aggregator}.md"
    out.write_text("\n".join(lines))
    print(json.dumps(s, ensure_ascii=False))
    print("report:", out)


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("collect"); c.add_argument("--max-queries", type=int, default=1)
    c.add_argument("--force-expand", action="store_true", help="always run the complementary queries")
    c.add_argument("--suffix", default="", help="collected file suffix, keeps the default collection intact")
    c.add_argument("--force", action="store_true"); c.add_argument("--only", nargs="*")
    a = sub.add_parser("analyze"); a.add_argument("--mode", default="baseline"); a.add_argument("--run", required=True)
    a.add_argument("--only", nargs="*"); a.add_argument("--with-wiki", action="store_true"); a.add_argument("--wiki-lead", type=int, default=0)
    a.add_argument("--suffix", default="", help="read collected files with this suffix when present")
    w = sub.add_parser("collect-wiki"); w.add_argument("--only", nargs="*"); w.add_argument("--force", action="store_true")
    r = sub.add_parser("report"); r.add_argument("--run", required=True); r.add_argument("--aggregator", default="baseline")
    r.add_argument("--policy"); r.add_argument("--only", nargs="*")
    args = ap.parse_args()
    {"collect": cmd_collect, "collect-wiki": cmd_collect_wiki, "analyze": cmd_analyze, "report": cmd_report}[args.cmd](args)


if __name__ == "__main__":
    main()
