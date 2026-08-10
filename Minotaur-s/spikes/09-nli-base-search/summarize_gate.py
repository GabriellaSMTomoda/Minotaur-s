# -*- coding: utf-8 -*-
"""Consolida as linhas estruturadas do harness físico do Spike 9."""
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

HERE = Path(__file__).resolve().parent
LOG = HERE / "device_results_iphone.log"
OUT = HERE / "build" / "gate_summary.json"


def structured(prefix: str, log_path: Path):
    pattern = re.compile(rf"{prefix} (\{{.*\}})")
    for raw in log_path.read_text(encoding="utf-8", errors="replace").splitlines():
        match = pattern.search(raw)
        if match:
            yield json.loads(match.group(1))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--log", type=Path, default=LOG)
    parser.add_argument("--output", type=Path, default=OUT)
    args = parser.parse_args()
    gates = list(structured("GATELINE", args.log))
    parity = list(structured("PARITYLINE", args.log))
    variants = sorted({line["variant"] for line in gates})
    summary = {
        "device": "iPhone 16 (iPhone17,3), iOS 26.3.1 (a)",
        "compute_units": "cpuOnly",
        "variant_count": len(variants),
        "gate_lines": len(gates),
        "parity_lines": len(parity),
        "minimum_free_disk_mb": min(line["free_disk_mb"] for line in gates),
        "maximum_observed_resident_mb": max(line["peak_resident_mb"] for line in gates),
        "maximum_observed_footprint_mb": max(line["peak_footprint_mb"] for line in gates),
        "parity_all_cosine_one": all(line["cosine"] == 1.0 for line in parity),
        "parity_all_argmax_match": all(
            line["expected_argmax"] == line["actual_argmax"] for line in parity
        ),
        "variants": {},
    }

    for variant in variants:
        own = [line for line in gates if line["variant"] == variant]
        real = [line for line in own if line["scenario"] == "real"]
        nli = next(line for line in real if line["stage"] == "nli_15")
        second = next(line for line in real if line["stage"] == "second_verification")
        load_nli = max(
            (line for line in own if line["stage"] == "load_nli"),
            key=lambda line: line["peak_resident_mb"],
        )
        latency = {
            int(line["scenario"].removeprefix("len-")): {
                "median_ms": line["median_ms"],
                "mean_ms": line["mean_ms"],
                "min_ms": line["min_ms"],
                "max_ms": line["max_ms"],
                "peak_resident_mb": line["peak_resident_mb"],
                "peak_footprint_mb": line["peak_footprint_mb"],
            }
            for line in own
            if line["stage"] == "latency_warm"
        }
        summary["variants"][variant] = {
            "preflight_free_disk_mb": next(
                line["free_disk_mb"] for line in own if line["scenario"] == "preflight"
            ),
            "minimum_free_disk_mb": min(line["free_disk_mb"] for line in own),
            "two_model_load_peak_resident_mb": load_nli["peak_resident_mb"],
            "two_model_load_peak_footprint_mb": load_nli["peak_footprint_mb"],
            "real_nli_peak_resident_mb": nli["peak_resident_mb"],
            "real_nli_peak_footprint_mb": nli["peak_footprint_mb"],
            "real_nli_median_ms": nli["median_ms"],
            "real_nli_elapsed_ms": nli["elapsed_ms"],
            "second_verification_peak_resident_mb": second["peak_resident_mb"],
            "second_verification_peak_footprint_mb": second["peak_footprint_mb"],
            "latency_by_tokens": latency,
        }

    args.output.write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
