# -*- coding: utf-8 -*-
"""Spike 9 / Etapa 2 — converte a arquitetura do BERTimbau-base sem fine-tune.

O encoder vem do checkpoint público do BERTimbau-base. A cabeça de três logits é
inicializada aleatoriamente, com seed fixa. Isso basta para medir RAM e latência:
essas propriedades dependem da arquitetura e dos shapes, não da qualidade dos pesos.

Saídas:
  build/bertimbau_base_dynamic512_int8.mlpackage  RangeDim 1...512
  build/bertimbau_base_fixed{256,384,512}_int8.mlpackage
  build/conversion_manifest.json

Uso:
  ../02-coreml-latencia/.venv/bin/python convert_architecture_gate.py
"""
from __future__ import annotations

import hashlib
import json
import math
import os
import shutil
import sys
from pathlib import Path

import numpy as np
import torch

HERE = Path(__file__).resolve().parent
SPIKES = HERE.parent
BUILD = HERE / "build"
BUILD.mkdir(exist_ok=True)

# Shims já validados nos Spikes 2/7 para transformers + coremltools.
sys.path.append(str(SPIKES / "02-coreml-latencia"))
import coreml_shims  # noqa: E402,F401

import coremltools as ct  # noqa: E402
from coremltools.optimize.coreml import (  # noqa: E402
    OpLinearQuantizerConfig,
    OptimizationConfig,
    linear_quantize_weights,
)
from transformers import AutoModelForSequenceClassification, AutoTokenizer  # noqa: E402

MODEL_ID = "neuralmind/bert-base-portuguese-cased"
SEED = 903_2026
MAX_SEQ = 512
FIXED_SHAPES = (256, 384, 512)

# Estes nomes documentam o contrato desejado para o fine-tune futuro, mas NÃO
# atribuem semântica à cabeça aleatória. A ordem terá de ser confirmada com sondas
# depois do treino, na Etapa 3.
ID2LABEL = {0: "ENTAILMENT", 1: "NEUTRAL", 2: "CONTRADICTION"}

PROBES = [
    {
        "kind": "entailment",
        "premise": "Brasília é a capital do Brasil.",
        "hypothesis": "A capital do Brasil é Brasília.",
    },
    {
        "kind": "contradiction",
        "premise": "A Terra é aproximadamente esférica.",
        "hypothesis": "A Terra é plana.",
    },
    {
        "kind": "neutral",
        "premise": "A vacinação contra a gripe começou nesta semana.",
        "hypothesis": "O preço do café caiu ontem.",
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


def directory_mb(path: Path) -> float:
    return sum(p.stat().st_size for p in path.rglob("*") if p.is_file()) / 1024 / 1024


def cosine(a, b) -> float:
    aa = np.asarray(a, dtype=np.float64).reshape(-1)
    bb = np.asarray(b, dtype=np.float64).reshape(-1)
    return float(np.dot(aa, bb) / (np.linalg.norm(aa) * np.linalg.norm(bb) + 1e-12))


def classifier_sha256(model: torch.nn.Module) -> str:
    digest = hashlib.sha256()
    for tensor in model.classifier.state_dict().values():
        digest.update(tensor.detach().cpu().contiguous().numpy().tobytes())
    return digest.hexdigest()


def padded_encoding(tokenizer, premise: str, hypothesis: str, length: int | None):
    kwargs = {
        "return_tensors": "pt",
        "truncation": "only_first",
        "max_length": length or MAX_SEQ,
    }
    if length is not None:
        kwargs.update({"padding": "max_length"})
    enc = tokenizer(premise, hypothesis, **kwargs)
    return enc["input_ids"], enc["attention_mask"], enc["token_type_ids"]


def convert_variant(traced, model, tokenizer, name: str, fixed: int | None) -> dict:
    default = fixed or 32
    dimension = fixed if fixed is not None else ct.RangeDim(
        lower_bound=1, upper_bound=MAX_SEQ, default=default
    )
    inputs = [
        ct.TensorType(name="input_ids", shape=(1, dimension), dtype=np.int32),
        ct.TensorType(name="attention_mask", shape=(1, dimension), dtype=np.int32),
        ct.TensorType(name="token_type_ids", shape=(1, dimension), dtype=np.int32),
    ]

    print(f"\n[{name}] convertendo fp16; shape={fixed or 'RangeDim(1...512)'}", flush=True)
    mlmodel = ct.convert(
        traced,
        inputs=inputs,
        outputs=[ct.TensorType(name="logits")],
        compute_precision=ct.precision.FLOAT16,
        minimum_deployment_target=ct.target.iOS16,
        convert_to="mlprogram",
    )

    print(f"[{name}] quantizando pesos para int8", flush=True)
    config = OptimizationConfig(
        global_config=OpLinearQuantizerConfig(mode="linear_symmetric", dtype="int8")
    )
    quantized = linear_quantize_weights(mlmodel, config=config)
    output = BUILD / f"{name}_int8.mlpackage"
    if output.exists():
        shutil.rmtree(output)
    quantized.save(str(output))

    probe_results = []
    coreml = ct.models.MLModel(str(output), compute_units=ct.ComputeUnit.CPU_ONLY)
    for probe in PROBES:
        ids, mask, types = padded_encoding(
            tokenizer, probe["premise"], probe["hypothesis"], fixed
        )
        with torch.no_grad():
            pt = model(
                input_ids=ids,
                attention_mask=mask,
                token_type_ids=types,
                return_dict=False,
            )[0].cpu().numpy()[0]
        feed = {
            "input_ids": ids.to(torch.int32).numpy(),
            "attention_mask": mask.to(torch.int32).numpy(),
            "token_type_ids": types.to(torch.int32).numpy(),
        }
        cm = np.asarray(coreml.predict(feed)["logits"]).reshape(-1)
        probe_results.append(
            {
                **probe,
                "sequence_length": int(ids.shape[1]),
                "pytorch_logits": [float(x) for x in pt],
                "coreml_logits": [float(x) for x in cm],
                "cosine": cosine(pt, cm),
                "argmax_match": int(np.argmax(pt)) == int(np.argmax(cm)),
            }
        )

    record = {
        "name": name,
        "shape": fixed if fixed is not None else {"lower": 1, "upper": MAX_SEQ, "default": 32},
        "int8_mb": directory_mb(output),
        "probes": probe_results,
    }
    print(
        f"[{name}] {record['int8_mb']:.1f} MB; "
        f"probes cos(min)={min(p['cosine'] for p in probe_results):.6f}; "
        f"argmax={all(p['argmax_match'] for p in probe_results)}",
        flush=True,
    )
    return record


def clean_json(value):
    if isinstance(value, float):
        return value if math.isfinite(value) else None
    if isinstance(value, list):
        return [clean_json(v) for v in value]
    if isinstance(value, dict):
        return {k: clean_json(v) for k, v in value.items()}
    return value


def main() -> int:
    torch.manual_seed(SEED)
    np.random.seed(SEED)

    print(f"carregando encoder {MODEL_ID} + cabeça aleatória de 3 logits", flush=True)
    model = AutoModelForSequenceClassification.from_pretrained(
        MODEL_ID,
        num_labels=3,
        id2label=ID2LABEL,
        label2id={v: k for k, v in ID2LABEL.items()},
    ).float().eval()
    tokenizer = AutoTokenizer.from_pretrained(MODEL_ID)

    params = sum(p.numel() for p in model.parameters())
    classifier_params = sum(p.numel() for p in model.classifier.parameters())
    classifier_values = torch.cat([p.detach().flatten() for p in model.classifier.parameters()])
    print(
        f"arquitetura: hidden={model.config.hidden_size}, layers={model.config.num_hidden_layers}, "
        f"heads={model.config.num_attention_heads}, params={params:,}",
        flush=True,
    )

    # O trace é feito uma vez. Os shapes declarados ao conversor geram quatro modelos
    # Core ML distintos; os três fixos não contêm RangeDim.
    example = (
        torch.randint(0, 1000, (1, 32), dtype=torch.long),
        torch.ones((1, 32), dtype=torch.long),
        torch.zeros((1, 32), dtype=torch.long),
    )
    with torch.no_grad():
        traced = torch.jit.trace(NLIWrapper(model).eval(), example, strict=False)

    variants = [convert_variant(traced, model, tokenizer, "bertimbau_base_dynamic512", None)]
    for length in FIXED_SHAPES:
        variants.append(
            convert_variant(traced, model, tokenizer, f"bertimbau_base_fixed{length}", length)
        )

    manifest = {
        "model_id": MODEL_ID,
        "seed": SEED,
        "encoder_pretrained": True,
        "classifier_trained": False,
        "classifier_sha256": classifier_sha256(model),
        "classifier_mean": float(classifier_values.mean()),
        "classifier_std": float(classifier_values.std()),
        "id2label_declared_not_empirical": ID2LABEL,
        "semantic_probe_warning": (
            "A cabeça é aleatória: sondas semânticas não podem determinar a ordem dos rótulos. "
            "Elas verificam somente a preservação dos três índices PyTorch -> Core ML."
        ),
        "architecture": {
            "model_type": model.config.model_type,
            "hidden_size": model.config.hidden_size,
            "layers": model.config.num_hidden_layers,
            "attention_heads": model.config.num_attention_heads,
            "vocab_size": model.config.vocab_size,
            "total_parameters": params,
            "classifier_parameters": classifier_params,
        },
        "variants": variants,
    }
    destination = BUILD / "conversion_manifest.json"
    destination.write_text(
        json.dumps(clean_json(manifest), ensure_ascii=False, indent=2), encoding="utf-8"
    )
    print(f"\nmanifest -> {destination}", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
