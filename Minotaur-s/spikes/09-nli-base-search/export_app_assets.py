#!/usr/bin/env python3
"""Export the selected Spike 9 tokenizer, empirical labels, and Swift parity fixture."""

from __future__ import annotations

import hashlib
import json
import shutil
from pathlib import Path

import torch
from transformers import AutoModelForSequenceClassification, AutoTokenizer


SPIKE_DIR = Path(__file__).resolve().parent
ROOT = SPIKE_DIR.parent.parent
BUILD_DIR = SPIKE_DIR / "build"
TRAINING_DIR = BUILD_DIR / "training-full"
CHECKPOINT = TRAINING_DIR / "checkpoint-best"
ADVERSARIAL = BUILD_DIR / "adversarial_evaluation.json"
TOKENIZER_DEST = ROOT / "Minotaur-s" / "Resources" / "Tokenizers"
FIXTURE_DEST = ROOT / "Minotaur-sTests" / "Verificador" / "Fixtures" / "parity_fixture.json"
SPIKE_FIXTURE = BUILD_DIR / "app_parity_fixture.json"
MANIFEST = BUILD_DIR / "app_assets_manifest.json"
MAX_LENGTH = 512


def digest(path: Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


def require_selection() -> tuple[dict, list[str]]:
    summary_path = TRAINING_DIR / "training_summary.json"
    selection_path = CHECKPOINT / "selection.json"
    if not summary_path.is_file() or not selection_path.is_file():
        raise RuntimeError("checkpoint-best is not selected; export blocked")
    summary = json.loads(summary_path.read_text(encoding="utf-8"))
    if summary.get("status") != "COMPLETE":
        raise RuntimeError("training_summary.json is not COMPLETE; export blocked")
    if Path(summary["selected_checkpoint"]).resolve() != CHECKPOINT.resolve():
        raise RuntimeError("checkpoint-best is not the PLUE-selected checkpoint")

    evaluation = json.loads(ADVERSARIAL.read_text(encoding="utf-8"))
    probe = evaluation.get("label_probe", {})
    labels = probe.get("order_index_to_label")
    if probe.get("status") != "CONFIRMED" or labels != [
        "entailment",
        "neutral",
        "contradiction",
    ]:
        raise RuntimeError("empirical index-to-label mapping is not uniquely confirmed")
    return summary, labels


def main() -> int:
    summary, labels = require_selection()
    original_fixture = json.loads(FIXTURE_DEST.read_text(encoding="utf-8"))
    tokenizer = AutoTokenizer.from_pretrained(CHECKPOINT, local_files_only=True)
    model = AutoModelForSequenceClassification.from_pretrained(
        CHECKPOINT, local_files_only=True
    ).eval()

    pairs = []
    for original in original_fixture["pairs"]:
        encoded = tokenizer(
            original["premise"],
            original["hypothesis"],
            return_tensors="pt",
            truncation="only_first",
            max_length=MAX_LENGTH,
        )
        with torch.no_grad():
            logits = model(**encoded).logits[0]
            probabilities = torch.softmax(logits, dim=-1)
        best = int(torch.argmax(probabilities).item())
        pairs.append(
            {
                "premise": original["premise"],
                "hypothesis": original["hypothesis"],
                "input_ids": encoded["input_ids"][0].tolist(),
                "attention_mask": encoded["attention_mask"][0].tolist(),
                "token_type_ids": encoded["token_type_ids"][0].tolist(),
                "expected_label": labels[best],
                "expected_confidence": float(probabilities[best].item()),
                "expected_logits": [float(value) for value in logits.tolist()],
            }
        )

    fixture = {
        "note": (
            "Embeddings preservados do Spike 7; pares NLI regenerados pelo Spike 9 a partir "
            "do checkpoint selecionado exclusivamente em PLUE dev_matched."
        ),
        "embedding_model": original_fixture["embedding_model"],
        "nli_model": "Spike 9 checkpoint-best / BERTimbau-base PLUE",
        "single": original_fixture["single"],
        "pairs": pairs,
    }
    serialized_fixture = json.dumps(fixture, ensure_ascii=False, indent=2) + "\n"
    SPIKE_FIXTURE.write_text(serialized_fixture, encoding="utf-8")
    FIXTURE_DEST.write_text(serialized_fixture, encoding="utf-8")

    TOKENIZER_DEST.mkdir(parents=True, exist_ok=True)
    tokenizer_source = CHECKPOINT / "tokenizer.json"
    tokenizer_config_source = CHECKPOINT / "tokenizer_config.json"
    tokenizer_dest = TOKENIZER_DEST / "NLITokenizer.json"
    tokenizer_config_dest = TOKENIZER_DEST / "NLITokenizerConfig.json"
    shutil.copyfile(tokenizer_source, tokenizer_dest)

    config = json.loads(tokenizer_config_source.read_text(encoding="utf-8"))
    config["model_max_length"] = MAX_LENGTH
    tokenizer_config_dest.write_text(
        json.dumps(config, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )

    label_dest = TOKENIZER_DEST / "NLILabels.json"
    label_dest.write_text(
        json.dumps(
            {
                "evidence": "Spike 9 empirical probes; config id2label not used",
                "id2label": {str(index): label for index, label in enumerate(labels)},
            },
            ensure_ascii=False,
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )

    files = [tokenizer_dest, tokenizer_config_dest, label_dest, FIXTURE_DEST]
    manifest = {
        "training_status": summary["status"],
        "selected_checkpoint": str(CHECKPOINT.resolve()),
        "selection_file": str((CHECKPOINT / "selection.json").resolve()),
        "label_order_source": str(ADVERSARIAL.resolve()),
        "label_order": labels,
        "max_length": MAX_LENGTH,
        "files": {
            str(path.relative_to(ROOT)): {
                "bytes": path.stat().st_size,
                "sha256": digest(path),
            }
            for path in files
        },
    }
    MANIFEST.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(json.dumps(manifest, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
