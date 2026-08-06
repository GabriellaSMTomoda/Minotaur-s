#!/usr/bin/env python3
"""Validate the completed PLUE training and its selected checkpoint.

This program uses only PLUE training artifacts. It deliberately has no import
or path reference to the sealed Spike 7 adversarial dataset.
"""

from __future__ import annotations

import hashlib
import json
import math
import sys
from pathlib import Path
from typing import Any


SCRIPT_DIR = Path(__file__).resolve().parent
BUILD_DIR = SCRIPT_DIR / "build"
TRAINING_DIR = BUILD_DIR / "training-full"
AUDIT_PATH = BUILD_DIR / "plue" / "dataset_audit.json"
OUTPUT_PATH = BUILD_DIR / "training_validation.json"
EXPECTED_TRAIN = 392_662
EXPECTED_EVAL = 9_815
EXPECTED_EPOCHS = 3
EXPECTED_UPDATES = 36_813
EXPECTED_EXAMPLES_SEEN = EXPECTED_TRAIN * EXPECTED_EPOCHS
EXPECTED_TRAIN_MD5 = "df6dbc8cb3e3c76f6985fd0d327f01aa"


def load_json(path: Path) -> Any:
    if not path.exists():
        raise FileNotFoundError(path)
    return json.loads(path.read_text(encoding="utf-8"))


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def close(left: float, right: float) -> bool:
    return math.isclose(left, right, rel_tol=0.0, abs_tol=1e-12)


def same_selection(left: dict[str, Any], right: dict[str, Any]) -> bool:
    return (
        left.get("epoch") == right.get("epoch")
        and left.get("global_update") == right.get("global_update")
        and close(float(left.get("macro_f1", -1)), float(right.get("macro_f1", -2)))
        and close(float(left.get("loss", -1)), float(right.get("loss", -2)))
    )


def main() -> int:
    manifest = load_json(TRAINING_DIR / "training_manifest.json")
    summary = load_json(TRAINING_DIR / "training_summary.json")
    audit = load_json(AUDIT_PATH)
    if summary.get("status") != "COMPLETE":
        raise RuntimeError("Training is not COMPLETE")

    metrics = [
        load_json(TRAINING_DIR / f"epoch_{epoch}_metrics.json")
        for epoch in range(1, EXPECTED_EPOCHS + 1)
    ]
    checkpoint = Path(summary["selected_checkpoint"]).resolve()
    selection = load_json(checkpoint / "selection.json")
    failures: list[str] = []

    def require(condition: bool, message: str) -> None:
        if not condition:
            failures.append(message)

    counts = manifest["counts"]
    hparams = manifest["hparams"]
    require(audit.get("status") == "PASS", "dataset audit did not pass")
    require(manifest.get("train_md5") == EXPECTED_TRAIN_MD5, "unexpected train MD5")
    require(counts.get("train") == EXPECTED_TRAIN, "unexpected valid train count")
    require(counts.get("eval") == EXPECTED_EVAL, "unexpected validation count")
    require(counts.get("planned_optimizer_updates") == EXPECTED_UPDATES, "unexpected planned updates")
    require(summary.get("optimizer_updates") == EXPECTED_UPDATES, "training did not finish all updates")
    require(
        summary.get("training_examples_seen") == EXPECTED_EXAMPLES_SEEN,
        "training did not consume exactly three full epochs",
    )
    require(hparams.get("epochs") == EXPECTED_EPOCHS, "unexpected epoch count")
    require(hparams.get("seed") == 42, "unexpected seed")
    require(hparams.get("effective_batch_size") == 32, "unexpected effective batch")
    require(hparams.get("max_length") == 256, "unexpected training token cap")
    require(close(float(hparams.get("learning_rate", 0)), 2e-5), "unexpected learning rate")
    require(close(float(hparams.get("weight_decay", 0)), 0.01), "unexpected weight decay")
    require(close(float(hparams.get("warmup_ratio", 0)), 0.10), "unexpected warmup ratio")
    require(manifest.get("adversarial_set_used_for_selection") is False, "adversarial leakage flag")

    expected_updates_by_epoch = [12_271, 24_542, 36_813]
    for epoch, (item, expected_update) in enumerate(zip(metrics, expected_updates_by_epoch), start=1):
        require(item.get("epoch") == epoch, f"epoch_{epoch} has wrong epoch field")
        require(item.get("global_update") == expected_update, f"epoch_{epoch} has wrong update count")
        require(item.get("examples") == EXPECTED_EVAL, f"epoch_{epoch} has incomplete validation")
        matrix = item.get("confusion_rows_true_columns_predicted", [])
        require(
            len(matrix) == 3 and all(len(row) == 3 for row in matrix),
            f"epoch_{epoch} confusion matrix is not 3x3",
        )
        require(sum(sum(row) for row in matrix) == EXPECTED_EVAL, f"epoch_{epoch} confusion total mismatch")
        require(set(item.get("per_class", {})) == {"entailment", "neutral", "contradiction"},
                f"epoch_{epoch} class metrics incomplete")

    recomputed_best = sorted(metrics, key=lambda item: (-item["macro_f1"], item["loss"]))[0]
    require(same_selection(selection, recomputed_best), "selection.json is not the recomputed best epoch")
    require(
        same_selection(summary.get("best_validation", {}), recomputed_best),
        "training_summary best does not match recomputed best epoch",
    )
    require(checkpoint == (TRAINING_DIR / "checkpoint-best").resolve(), "selected checkpoint path mismatch")

    required_checkpoint_files = {
        "config.json",
        "model.safetensors",
        "special_tokens_map.json",
        "tokenizer_config.json",
        "tokenizer.json",
        "vocab.txt",
        "selection.json",
    }
    present = {path.name for path in checkpoint.iterdir() if path.is_file()}
    require(required_checkpoint_files.issubset(present), "checkpoint files are incomplete")
    config = load_json(checkpoint / "config.json")
    require(config.get("num_labels", 3) == 3, "checkpoint is not a 3-class model")
    require(config.get("model_type") == "bert", "checkpoint model type is not BERT")

    checkpoint_files = sorted(path for path in checkpoint.iterdir() if path.is_file())
    result = {
        "status": "PASS" if not failures else "FAIL",
        "failures": failures,
        "dataset": {
            "train_valid": counts.get("train"),
            "validation": counts.get("eval"),
            "train_md5": manifest.get("train_md5"),
            "excluded_empty_rows": counts.get("train_rows_excluded_for_empty_text"),
        },
        "protocol": hparams,
        "runtime": manifest["runtime"],
        "summary": summary,
        "epochs": metrics,
        "recomputed_best_epoch": recomputed_best["epoch"],
        "checkpoint": {
            "path": str(checkpoint),
            "bytes": sum(path.stat().st_size for path in checkpoint_files),
            "sha256": {path.name: sha256(path) for path in checkpoint_files},
        },
    }
    OUTPUT_PATH.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({
        "status": result["status"],
        "failures": failures,
        "recomputed_best_epoch": result["recomputed_best_epoch"],
        "checkpoint_bytes": result["checkpoint"]["bytes"],
    }, ensure_ascii=False, indent=2))
    return 0 if not failures else 1


if __name__ == "__main__":
    sys.exit(main())
