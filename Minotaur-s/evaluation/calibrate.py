#!/usr/bin/env python3
"""Fit temperature to independently reviewed CALIBRATION pairs only; never test/regression."""
from __future__ import annotations
import argparse
import json
import math
from pathlib import Path
from dataset import fingerprint, read

LABELS = ("entailment", "neutral", "contradiction")

def softmax(logits, temperature=1):
    if len(logits) != 3 or not all(math.isfinite(x) for x in logits) or not math.isfinite(temperature) or temperature <= 0:
        raise ValueError("Invalid three-class logits/temperature")
    values = [x / temperature for x in logits]
    peak = max(values)
    exp = [math.exp(x - peak) for x in values]
    return [x / sum(exp) for x in exp]

def loss(records, temperature):
    return sum(-math.log(max(1e-15, softmax(r["logits"], temperature)[LABELS.index(r["label"])])) for r in records) / len(records)

def fit(records):
    if not records:
        raise ValueError("No calibration observations")
    if any(r.get("split") != "calibration" or len(set(r.get("reviewers", []))) < 2 for r in records):
        raise ValueError("Only independently reviewed calibration observations are allowed")
    for row in records:
        softmax(row["logits"])
        if row["label"] not in LABELS:
            raise ValueError("Unknown label")
    candidates = [math.exp(-3 + i * .01) for i in range(601)] + [1.0]
    temperature = min(candidates, key=lambda t: loss(records, t))
    return {"temperature": temperature, "nll_before": loss(records, 1), "nll_after": loss(records, temperature),
            "observations": len(records), "claims": len({r["claim_id"] for r in records}),
            "claim_ids": sorted({r["claim_id"] for r in records}),
            "calibration_sha256": fingerprint(records), "label_order": list(LABELS),
            "status": "calibration_candidate_requires_pipeline_evaluation"}

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("observations"); parser.add_argument("output")
    args = parser.parse_args()
    records = read(args.observations)
    if len({r["claim_id"] for r in records}) < 300:
        raise ValueError("Release calibration requires at least 300 distinct reviewed calibration claims")
    Path(args.output).write_text(json.dumps(fit(records), indent=2) + "\n")
