#!/usr/bin/env python3
"""Evaluate verdict AND annotated sufficient evidence, with Wilson confidence intervals."""
from __future__ import annotations
import argparse
import json
import math
from dataset import VERDICTS, canonical, read, validate

DIRECTIONAL = {"CONFIRMADO", "CONTRADITO"}

def wilson(successes, total):
    if not total:
        return None
    z = 1.959963984540054
    p, d = successes / total, 1 + z * z / total
    center = (p + z * z / (2 * total)) / d
    radius = z * math.sqrt(p * (1 - p) / total + z * z / (4 * total * total)) / d
    return [max(0, center - radius), min(1, center + radius)]

def ratio(n, d):
    return {"value": n / d if d else None, "numerator": n, "denominator": d, "ci95": wilson(n, d)}

def verified_evidence(gold, predicted):
    annotated = {e["id"]: e for e in gold.get("evidence", [])}
    ids = set()
    for passage in predicted.get("evidence", []):
        expected = annotated.get(passage.get("id"))
        if not expected or not passage.get("text"):
            continue
        # An ID alone is insufficient: require the annotated span and matching URL.
        text = " ".join(passage["text"].casefold().split())
        span = " ".join(expected["text"].casefold().split())
        if span in text and canonical(passage.get("url", "")) == canonical(expected["url"]):
            ids.add(expected["id"])
    return ids

def evaluate(gold, predictions):
    validate(gold, require_reviewed=True)
    by_id = {p["id"]: p for p in predictions}
    if len(by_id) != len(predictions) or set(by_id) != {g["id"] for g in gold}:
        raise ValueError("Predictions must cover every gold id exactly once; missing cases cannot disappear")
    confusion = {v: {w: 0 for w in (*VERDICTS, "ERROR")} for v in VERDICTS}
    directional, correct_directional, resolved, covered_resolved, complete = 0, 0, 0, 0, 0
    labels = {v: [0, 0] for v in DIRECTIONAL}
    evidence_hits, evidence_total, high_confidence_errors, confidence_observations = 0, 0, 0, 0
    latencies, credits = [], []
    errors = 0
    for row in gold:
        p = by_id[row["id"]]
        actual = "ERROR" if p.get("error") else p.get("verdict")
        if actual != "ERROR" and actual not in VERDICTS:
            raise ValueError("Unknown verdict")
        expected = row["verdict"]
        errors += actual == "ERROR"
        confusion[expected][actual] += 1
        ids = verified_evidence(row, p)
        sufficient = any(set(s) <= ids for s in row.get("sufficient_evidence_sets", []))
        correct = actual == expected and (sufficient if actual in DIRECTIONAL | {"DIVERGENTE"} else True)
        complete += correct
        if actual in DIRECTIONAL:
            directional += 1; correct_directional += correct
            labels[actual][1] += 1; labels[actual][0] += correct
            confidence = p.get("confidence")
            if isinstance(confidence, (float, int)) and math.isfinite(confidence):
                confidence_observations += 1
                if confidence >= 0.85 and not correct: high_confidence_errors += 1
        if expected in DIRECTIONAL:
            resolved += 1; covered_resolved += actual in DIRECTIONAL
        evidence_total += bool(row.get("sufficient_evidence_sets"))
        evidence_hits += sufficient
        if "elapsed_seconds" in p: latencies.append(p["elapsed_seconds"])
        if "search_calls" in p: credits.append(p["search_calls"])
    f1s = []
    for v in VERDICTS:
        tp = confusion[v][v]
        fp = sum(confusion[w][v] for w in VERDICTS if w != v)
        fn = sum(confusion[v][w] for w in (*VERDICTS, "ERROR") if w != v)
        f1s.append(2 * tp / (2 * tp + fp + fn) if 2 * tp + fp + fn else 0)
    return {"count": len(gold), "macro_f1_verdict": sum(f1s) / len(VERDICTS), "confusion": confusion,
            "end_to_end_accuracy": ratio(complete, len(gold)), "directional_precision": ratio(correct_directional, directional),
            "precision_by_direction": {v: ratio(*counts) for v, counts in labels.items()},
            "total_coverage": ratio(directional, len(gold)), "resolvable_coverage": ratio(covered_resolved, resolved),
            "sufficient_evidence_recall": ratio(evidence_hits, evidence_total),
            "high_confidence_errors": high_confidence_errors if confidence_observations else None,
            "confidence_observations": confidence_observations,
            "latency_p95_seconds": sorted(latencies)[max(0, math.ceil(len(latencies) * .95) - 1)] if latencies else None,
            "mean_search_calls": sum(credits) / len(credits) if credits else None,
            "execution_failures": errors}

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("gold"); parser.add_argument("predictions"); parser.add_argument("--output")
    args = parser.parse_args()
    report = json.dumps(evaluate(read(args.gold), read(args.predictions)), ensure_ascii=False, indent=2)
    if args.output:
        from pathlib import Path
        Path(args.output).write_text(report + "\n")
    else:
        print(report)
