"""Prints every scored passage of one case: `uv run python debug_case.py RUN ID [ID...]`."""
import json
import sys

import analysis
import evidence
from run_dev import ARTIFACTS

run = sys.argv[1]
for cid in sys.argv[2:]:
    res = json.loads((ARTIFACTS / run / f"{cid}.json").read_text())
    feats = evidence.claim_features(res["claim"])
    print(f"== {cid}: {res['claim']}  feats={ {k: feats[k] for k in ('names', 'anchors', 'nonname', 'numbers')} }")
    print("   verdict:", evidence.aggregate(res["sources"], res.get("ctx_kind"), None, res["claim"])[0])
    for s in res["sources"]:
        tag = "ok" if analysis.eligible(s) else f"inelig(partial={s['partial']},{s['provenance']},{s['alignment']},dup={bool(s['duplicate_of'])})"
        print(f" [{s['origin']}|{s['kind']}|{tag}] {s['title'][:70]}")
        for p in s["passages"]:
            sc = evidence.score_passage(res["claim"], p, evidence.DEFAULT_POLICY, feats)
            pr = p["probs"]
            print(f"   E{pr['entailment']:.2f} N{pr['neutral']:.2f} C{pr['contradiction']:.2f} sim{p['similarity']:.2f} "
                  f"S{sc['support']:.2f} R{sc['refute']:.2f} nm{sc['names']} an{sc['anchors']} {sc['why']} | {p['text'][:110]}")
