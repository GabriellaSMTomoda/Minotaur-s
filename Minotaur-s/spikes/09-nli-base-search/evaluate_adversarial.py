#!/usr/bin/env python3
"""Post-selection label probe and Spike 7 adversarial evaluation.

Do not run this program until ``checkpoint-best`` has been selected using only
PLUE validation data. The label mapping is inferred from unequivocal probes;
the model config is recorded but is not used as evidence.
"""

from __future__ import annotations

import argparse
import importlib.util
import itertools
import json
import sys
from pathlib import Path
from typing import Any

import torch
from transformers import AutoModelForSequenceClassification, AutoTokenizer


SCRIPT_DIR = Path(__file__).resolve().parent
SPIKE7_DATASET = SCRIPT_DIR.parent / "07-nli-ptbr-negacao" / "dataset.py"
LABELS = ("entailment", "neutral", "contradiction")
PROBES = [
    ("A Terra é plana.", "A Terra é plana.", "entailment"),
    ("A Terra é plana.", "A Terra não é plana.", "contradiction"),
    (
        "A Terra não é plana, e sim aproximadamente esférica.",
        "A Terra é plana.",
        "contradiction",
    ),
    ("O gato dormiu no sofá.", "A inflação subiu no trimestre.", "neutral"),
]


def load_spike7_dataset():
    spec = importlib.util.spec_from_file_location("spike7_dataset", SPIKE7_DATASET)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Could not load {SPIKE7_DATASET}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


@torch.inference_mode()
def raw_probabilities(tokenizer: Any, model: Any, premise: str, hypothesis: str) -> list[float]:
    encoded = tokenizer(
        premise,
        hypothesis,
        return_tensors="pt",
        truncation=True,
        max_length=512,
    )
    return torch.softmax(model(**encoded).logits[0], dim=-1).tolist()


def infer_label_order(tokenizer: Any, model: Any) -> tuple[list[str], dict[str, Any]]:
    raw = []
    for premise, hypothesis, expected in PROBES:
        probabilities = raw_probabilities(tokenizer, model, premise, hypothesis)
        raw.append(
            {
                "premise": premise,
                "hypothesis": hypothesis,
                "expected": expected,
                "argmax_index": max(range(3), key=probabilities.__getitem__),
                "probabilities_by_index": probabilities,
            }
        )

    passing_orders: list[list[str]] = []
    for order_tuple in itertools.permutations(LABELS):
        if all(order_tuple[item["argmax_index"]] == item["expected"] for item in raw):
            passing_orders.append(list(order_tuple))
    if len(passing_orders) != 1:
        raise RuntimeError(
            "Empirical label order is not uniquely identifiable: "
            f"passing_orders={passing_orders}, probes={raw}"
        )

    order = passing_orders[0]
    details = {
        "status": "CONFIRMED",
        "method": "unique permutation that makes all unequivocal probes correct",
        "order_index_to_label": order,
        "config_id2label_not_used_as_evidence": dict(model.config.id2label),
        "probes": [
            {
                **item,
                "predicted": order[item["argmax_index"]],
                "probabilities_named": {
                    order[index]: round(probability, 6)
                    for index, probability in enumerate(item["probabilities_by_index"])
                },
            }
            for item in raw
        ],
    }
    return order, details


def predict(tokenizer: Any, model: Any, order: list[str], premise: str, hypothesis: str):
    probabilities = raw_probabilities(tokenizer, model, premise, hypothesis)
    index = max(range(3), key=probabilities.__getitem__)
    return order[index], {order[i]: round(probabilities[i], 6) for i in range(3)}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--checkpoint",
        type=Path,
        default=SCRIPT_DIR / "build" / "training-full" / "checkpoint-best",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=SCRIPT_DIR / "build" / "adversarial_evaluation.json",
    )
    args = parser.parse_args()
    selection_path = args.checkpoint / "selection.json"
    summary_path = args.checkpoint.parent / "training_summary.json"
    if not selection_path.exists() or not summary_path.exists():
        raise FileNotFoundError(
            "Training is not complete; adversarial evaluation remains sealed"
        )
    training_summary = json.loads(summary_path.read_text(encoding="utf-8"))
    if training_summary.get("status") != "COMPLETE":
        raise RuntimeError("Training summary is not COMPLETE; adversarial evaluation remains sealed")
    selected_checkpoint = Path(training_summary["selected_checkpoint"]).resolve()
    if selected_checkpoint != args.checkpoint.resolve():
        raise RuntimeError(
            f"Training selected {selected_checkpoint}, not requested {args.checkpoint.resolve()}"
        )

    tokenizer = AutoTokenizer.from_pretrained(args.checkpoint)
    model = AutoModelForSequenceClassification.from_pretrained(args.checkpoint).eval()
    order, label_probe = infer_label_order(tokenizer, model)
    spike7 = load_spike7_dataset()

    real_rows = []
    group_correct = {"A": 0, "B": 0}
    group_total = {"A": 0, "B": 0}
    critical_correct = 0
    for pair_index, (premise, hypothesis, expected, source, group) in enumerate(spike7.todos_os_pares()):
        predicted, probabilities = predict(tokenizer, model, order, premise, hypothesis)
        correct = bool(spike7.acertou(predicted, expected))
        group_correct[group] += int(correct)
        group_total[group] += 1
        if pair_index < 6:
            critical_correct += int(correct)
        real_rows.append(
            {
                "group": group,
                "source": source,
                "premise": premise,
                "hypothesis": hypothesis,
                "expected": expected,
                "predicted": predicted,
                "correct": correct,
                "probabilities": probabilities,
            }
        )

    short_groups = []
    stable_groups = 0
    stable_and_correct_groups = 0
    for case in spike7.CLAIMS_CURTOS:
        variants = []
        for claim in case["variantes"]:
            predicted, probabilities = predict(tokenizer, model, order, case["premissa"], claim)
            variants.append(
                {
                    "claim": claim,
                    "predicted": predicted,
                    "correct": bool(spike7.acertou(predicted, case["esperado"])),
                    "probabilities": probabilities,
                }
            )
        stable = len({variant["predicted"] for variant in variants}) == 1
        all_correct = all(variant["correct"] for variant in variants)
        stable_groups += int(stable)
        stable_and_correct_groups += int(stable and all_correct)
        short_groups.append(
            {
                "group": case["grupo"],
                "expected": case["esperado"],
                "stable": stable,
                "all_correct": all_correct,
                "correct_variants": sum(int(variant["correct"]) for variant in variants),
                "total_variants": len(variants),
                "variants": variants,
            }
        )

    result = {
        "checkpoint": str(args.checkpoint.resolve()),
        "training_summary": training_summary,
        "selection": json.loads(selection_path.read_text(encoding="utf-8")),
        "label_probe": label_probe,
        "summary": {
            "group_a": f"{group_correct['A']}/{group_total['A']}",
            "group_b": f"{group_correct['B']}/{group_total['B']}",
            "real_pairs": f"{sum(group_correct.values())}/{sum(group_total.values())}",
            "earth_and_vaccine_materialized_cases": f"{critical_correct}/6",
            "short_claim_stable_groups": f"{stable_groups}/{len(short_groups)}",
            "short_claim_stable_and_correct_groups": f"{stable_and_correct_groups}/{len(short_groups)}",
        },
        "real_pairs": real_rows,
        "short_claims": short_groups,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result["label_probe"], ensure_ascii=False, indent=2))
    print(json.dumps(result["summary"], ensure_ascii=False, indent=2))
    print(f"Wrote {args.output}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
