#!/usr/bin/env python3
"""Fail closed unless frozen evaluation and device evidence support promotion."""
import argparse
import json
import re
from pathlib import Path

def check(report):
    errors = []
    current, baseline = report["candidate"], report["baseline"]
    if report.get("blind_test_claims", 0) < 300 or not report.get("blind_test_sha256"):
        errors.append("Complete frozen 300-claim blind test required")
    for metric, target in [("directional_precision", .90), ("resolvable_coverage", .70)]:
        if (current[metric]["value"] or 0) < target: errors.append(metric + " below target")
    if current["end_to_end_accuracy"]["value"] <= baseline["end_to_end_accuracy"]["value"]:
        errors.append("No end-to-end evidence + verdict improvement")
    if current["total_coverage"]["value"] < baseline["total_coverage"]["value"] - .03:
        errors.append("Coverage regression exceeds 3 percentage points")
    if not report.get("tokenizer_parity_passed") or not report.get("coreml_parity_passed"):
        errors.append("Tokenizer and Core ML parity required")
    if not report.get("critical_regressions_passed"):
        errors.append("Known critical adversarial regression gate failed")
    devices = report.get("physical_devices", [])
    newer = any((match := re.search(r"iPhone\s+(\d+)", d.get("name", ""))) and int(match[1]) > 13 for d in devices)
    if not any(d.get("name") == "iPhone 13" for d in devices) or not newer:
        errors.append("Physical iPhone 13 and a newer device required")
    for d in devices:
        if d.get("peak_ram_mb", float("inf")) >= 1000 or d.get("verification_p95_seconds", float("inf")) > 15:
            errors.append("Physical memory/latency budget failed: " + d.get("name", "unknown"))
        if not d.get("free_storage_mb") or not d.get("cold_and_repeated_runs"):
            errors.append("Storage preflight and cold/repeated measurements required")
    if not report.get("model_sha256") or not report.get("policy_version"):
        errors.append("Versioned model/tokenizer/calibration manifest required")
    return errors

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__); parser.add_argument("report")
    args = parser.parse_args()
    errors = check(json.loads(Path(args.report).read_text()))
    print(json.dumps({"promotable": not errors, "errors": errors}, indent=2))
    raise SystemExit(bool(errors))
