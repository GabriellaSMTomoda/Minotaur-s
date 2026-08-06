#!/usr/bin/env python3
"""Convert the selected PLUE checkpoint to the production-shaped Core ML model."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import shutil
import sys
from pathlib import Path

import numpy as np
import torch


SCRIPT_DIR = Path(__file__).resolve().parent
BUILD_DIR = SCRIPT_DIR / "build"
SPIKES_DIR = SCRIPT_DIR.parent
sys.path.append(str(SPIKES_DIR / "02-coreml-latencia"))
import coreml_shims  # noqa: E402,F401

import coremltools as ct  # noqa: E402
from coremltools.optimize.coreml import (  # noqa: E402
    OpLinearQuantizerConfig,
    OptimizationConfig,
    linear_quantize_weights,
)
from transformers import AutoModelForSequenceClassification, AutoTokenizer  # noqa: E402


MAX_LENGTH = 512
VARIANT = "bertimbau_base_plue_dynamic512"
PROBES = [
    {"kind": "entailment", "premise": "A Terra é plana.", "hypothesis": "A Terra é plana."},
    {
        "kind": "contradiction",
        "premise": "A Terra não é plana, e sim aproximadamente esférica.",
        "hypothesis": "A Terra é plana.",
    },
    {
        "kind": "neutral",
        "premise": "O gato dormiu no sofá.",
        "hypothesis": "A inflação subiu no trimestre.",
    },
]


class NLIWrapper(torch.nn.Module):
    def __init__(self, backbone: torch.nn.Module):
        super().__init__()
        self.backbone = backbone

    def forward(self, input_ids, attention_mask, token_type_ids):
        return self.backbone(
            input_ids=input_ids,
            attention_mask=attention_mask,
            token_type_ids=token_type_ids,
            return_dict=False,
        )[0]


def digest_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def directory_mb(path: Path) -> float:
    return sum(item.stat().st_size for item in path.rglob("*") if item.is_file()) / 1024 / 1024


def cosine(left, right) -> float:
    a = np.asarray(left, dtype=np.float64).reshape(-1)
    b = np.asarray(right, dtype=np.float64).reshape(-1)
    return float(np.dot(a, b) / (np.linalg.norm(a) * np.linalg.norm(b) + 1e-12))


def clean_json(value):
    if isinstance(value, float):
        return value if math.isfinite(value) else None
    if isinstance(value, list):
        return [clean_json(item) for item in value]
    if isinstance(value, dict):
        return {key: clean_json(item) for key, item in value.items()}
    return value


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--checkpoint",
        type=Path,
        default=BUILD_DIR / "training-full" / "checkpoint-best",
    )
    args = parser.parse_args()
    checkpoint = args.checkpoint.resolve()
    selection_path = checkpoint / "selection.json"
    summary_path = checkpoint.parent / "training_summary.json"
    if not selection_path.exists() or not summary_path.exists():
        raise FileNotFoundError("Training is not complete; conversion is blocked")
    training_summary = json.loads(summary_path.read_text(encoding="utf-8"))
    if training_summary.get("status") != "COMPLETE":
        raise RuntimeError("Training summary is not COMPLETE; conversion is blocked")
    selected_checkpoint = Path(training_summary["selected_checkpoint"]).resolve()
    if selected_checkpoint != checkpoint:
        raise RuntimeError(f"Training selected {selected_checkpoint}, not requested {checkpoint}")

    print(f"Loading selected checkpoint {checkpoint}", flush=True)
    tokenizer = AutoTokenizer.from_pretrained(checkpoint)
    model = AutoModelForSequenceClassification.from_pretrained(checkpoint).float().eval()
    example = (
        torch.randint(0, 1000, (1, 32), dtype=torch.long),
        torch.ones((1, 32), dtype=torch.long),
        torch.zeros((1, 32), dtype=torch.long),
    )
    with torch.no_grad():
        traced = torch.jit.trace(NLIWrapper(model).eval(), example, strict=False)

    dimension = ct.RangeDim(lower_bound=1, upper_bound=MAX_LENGTH, default=32)
    converted = ct.convert(
        traced,
        inputs=[
            ct.TensorType(name="input_ids", shape=(1, dimension), dtype=np.int32),
            ct.TensorType(name="attention_mask", shape=(1, dimension), dtype=np.int32),
            ct.TensorType(name="token_type_ids", shape=(1, dimension), dtype=np.int32),
        ],
        outputs=[ct.TensorType(name="logits")],
        compute_precision=ct.precision.FLOAT16,
        minimum_deployment_target=ct.target.iOS16,
        convert_to="mlprogram",
    )
    quantized = linear_quantize_weights(
        converted,
        config=OptimizationConfig(
            global_config=OpLinearQuantizerConfig(mode="linear_symmetric", dtype="int8")
        ),
    )
    trained_dir = BUILD_DIR / "trained"
    trained_dir.mkdir(parents=True, exist_ok=True)
    output = trained_dir / f"{VARIANT}_int8.mlpackage"
    if output.exists():
        shutil.rmtree(output)
    quantized.save(str(output))

    coreml = ct.models.MLModel(str(output), compute_units=ct.ComputeUnit.CPU_ONLY)
    probe_results = []
    for probe in PROBES:
        encoded = tokenizer(
            probe["premise"],
            probe["hypothesis"],
            return_tensors="pt",
            truncation=True,
            max_length=MAX_LENGTH,
        )
        with torch.no_grad():
            pytorch_logits = model(**encoded).logits.cpu().numpy()[0]
        feed = {
            "input_ids": encoded["input_ids"].to(torch.int32).numpy(),
            "attention_mask": encoded["attention_mask"].to(torch.int32).numpy(),
            "token_type_ids": encoded["token_type_ids"].to(torch.int32).numpy(),
        }
        coreml_logits = np.asarray(coreml.predict(feed)["logits"]).reshape(-1)
        probe_results.append(
            {
                **probe,
                "input_ids": encoded["input_ids"][0].tolist(),
                "attention_mask": encoded["attention_mask"][0].tolist(),
                "token_type_ids": encoded["token_type_ids"][0].tolist(),
                "expected_coreml_logits": [float(value) for value in coreml_logits],
                "pytorch_logits": [float(value) for value in pytorch_logits],
                "cosine": cosine(pytorch_logits, coreml_logits),
                "argmax_match": int(np.argmax(pytorch_logits)) == int(np.argmax(coreml_logits)),
            }
        )

    weight_files = sorted(
        path for path in checkpoint.iterdir() if path.name in {"model.safetensors", "pytorch_model.bin"}
    )
    manifest = {
        "checkpoint": str(checkpoint),
        "checkpoint_weight_sha256": {path.name: digest_file(path) for path in weight_files},
        "training_summary": training_summary,
        "selection": json.loads(selection_path.read_text(encoding="utf-8")),
        "variant": VARIANT,
        "shape": {"lower": 1, "upper": MAX_LENGTH, "default": 32},
        "quantization": "linear_symmetric int8 weights; fp16 compute",
        "int8_mb": directory_mb(output),
        "parameters": sum(parameter.numel() for parameter in model.parameters()),
        "probes": probe_results,
        "parity": {
            "minimum_cosine": min(item["cosine"] for item in probe_results),
            "all_argmax_match": all(item["argmax_match"] for item in probe_results),
        },
    }
    (trained_dir / "conversion_manifest.json").write_text(
        json.dumps(clean_json(manifest), ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    fixture = {
        "model_id": str(checkpoint),
        "variants": {
            VARIANT: [
                {
                    key: item[key]
                    for key in (
                        "kind",
                        "input_ids",
                        "attention_mask",
                        "token_type_ids",
                        "expected_coreml_logits",
                    )
                }
                for item in probe_results
            ]
        },
    }
    (BUILD_DIR / "trained_device_fixture.json").write_text(
        json.dumps(fixture, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    print(json.dumps(manifest["parity"], indent=2), flush=True)
    print(f"Model: {output} ({manifest['int8_mb']:.1f} MB)", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
