#!/usr/bin/env python3
"""Choose class/single-source thresholds on reviewed calibration claims, never blind test."""
import argparse
import json
from pathlib import Path
from calibrate import softmax
from dataset import fingerprint, read, validate
from metrics import evaluate

def predict(record, temperature, minimum, single):
    if record.get("error"):
        return {"id": record["id"], "verdict": None, "error": record["error"], "evidence": []}
    eligible = []
    evidence = []
    for source in record.get("sources", []):
        if source.get("is_partial") or source.get("provenance") == "searchSnippet" or source.get("temporal_alignment") != "compatible" or source.get("duplicate_of"):
            continue
        votes = []
        for passage in source.get("passages", []):
            p = softmax(passage["logits"], temperature)
            winner = max(range(3), key=p.__getitem__)
            if winner != 1 and p[winner] >= minimum:
                votes.append((winner, p[winner]))
                evidence.append({k: passage[k] for k in ("id", "text", "url")})
        if votes:
            eligible.append((source["origin_group"], votes))
    threshold = single if len({origin for origin, _ in eligible}) == 1 else minimum
    votes = {label for _, votes in eligible for label, score in votes if score >= threshold}
    verdict = "DIVERGENTE" if votes == {0, 2} else "CONFIRMADO" if 0 in votes else "CONTRADITO" if 2 in votes else "SEM_INFORMACAO"
    if not record.get("found_articles", 0) and not record.get("sources"):
        verdict = "NAO_ENCONTRADO"
    return {"id": record["id"], "verdict": verdict, "evidence": evidence,
            "confidence": max((score for _, votes in eligible for _, score in votes if score >= threshold), default=None)}

def select(gold, observations, calibration, model_version, minimum_claims=300):
    validate(gold, require_reviewed=True)
    if len(gold) < minimum_claims or any(r.get("split") != "calibration" for r in gold):
        raise ValueError("Only the complete reviewed calibration partition may select policy")
    if set(calibration.get("claim_ids", [])) != {r["id"] for r in gold}:
        raise ValueError("Temperature and policy must use the same calibration claims")
    best = None
    for i in range(19):
        floor = .5 + i * .025
        for j in range(i, 19):
            single = .5 + j * .025
            report = evaluate(gold, [predict(row, calibration["temperature"], floor, single) for row in observations])
            precision = report["directional_precision"]["value"] or 0
            coverage = report["resolvable_coverage"]["value"] or 0
            if precision < .9 or coverage < .7:
                continue
            score = (report["macro_f1_verdict"], report["end_to_end_accuracy"]["value"], coverage, precision)
            if best is None or score > best[0]: best = (score, floor, single, report)
    if best is None:
        raise ValueError("No policy meets both precision and coverage targets; retain baseline and improve data/retrieval/model")
    return {"version": "evidence-v2-" + fingerprint(gold)[:12], "modelVersion": model_version,
            "temperature": calibration["temperature"], "minimumConfidence": best[1],
            "singleSourceMinimumConfidence": best[2], "calibrated": True,
            "calibrationDigest": fingerprint(gold), "selection_report": best[3],
            "promotion_status": "requires_frozen_test_and_physical_gates"}

if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("gold"); p.add_argument("observations"); p.add_argument("temperature"); p.add_argument("output")
    p.add_argument("--model-version", required=True)
    a = p.parse_args()
    result = select(read(a.gold), read(a.observations), json.loads(Path(a.temperature).read_text()), a.model_version)
    Path(a.output).write_text(json.dumps(result, indent=2) + "\n")
