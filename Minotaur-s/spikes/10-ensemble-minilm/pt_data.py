# -*- coding: utf-8 -*-
"""Pares e frases PT reaproveitados (nada novo é rotulado aqui).

- 15 regressões conhecidas: `evaluation/data/known_regressions.jsonl`.
- 20 pares do Spike 1: `spikes/01-modelos-ptbr/dataset.py` (PAIRS).
- Frases para comparar tokenizers: premissas/hipóteses acima + afirmações de
  `evaluation/data/dev_claims.jsonl`, deduplicadas, primeiras N.
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SPIKES = os.path.dirname(HERE)
ROOT = os.path.dirname(SPIKES)


def regression_pairs():
    path = os.path.join(ROOT, "evaluation", "data", "known_regressions.jsonl")
    with open(path, encoding="utf-8") as f:
        rows = [json.loads(line) for line in f if line.strip()]
    return [{"id": r["id"], "premise": r["premise"], "hypothesis": r["hypothesis"],
             "allowed": r["allowed_labels"], "source": "known_regressions"} for r in rows]


def spike1_pairs():
    sys.path.insert(0, os.path.join(SPIKES, "01-modelos-ptbr"))
    from dataset import PAIRS  # noqa: E402
    return [{"id": f"spike1-{i + 1}", "premise": p["chunk"], "hypothesis": p["afirmacao"],
             "allowed": [p["esperado"]], "source": "spike1"} for i, p in enumerate(PAIRS)]


def all_pairs():
    return regression_pairs() + spike1_pairs()


def sentences(n=60):
    out, seen = [], set()

    def add(s):
        if s not in seen:
            seen.add(s)
            out.append(s)

    with open(os.path.join(ROOT, "evaluation", "data", "dev_claims.jsonl"), encoding="utf-8") as f:
        claims = [json.loads(line)["claim"] for line in f if line.strip()]
    pairs = all_pairs()
    # intercala para cobrir textos longos (premissas) e curtos (afirmações)
    for i in range(max(len(claims), len(pairs))):
        if i < len(pairs):
            add(pairs[i]["premise"])
            add(pairs[i]["hypothesis"])
        if i < len(claims):
            add(claims[i])
    return out[:n]
