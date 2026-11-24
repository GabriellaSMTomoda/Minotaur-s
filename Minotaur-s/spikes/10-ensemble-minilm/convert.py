# -*- coding: utf-8 -*-
"""
SPIKE 10 — Conversão do segundo NLI (ensemble): MiniLMv2-L6-mnli-xnli -> Core ML.

Reaproveita o fluxo do Spike 2c (`../02c-nli-executavel/convert_and_reference.py`,
mesmo candidato `L6` de `candidates.py`, já aprovado em iPhone físico):

  trace -> ct.convert(FLOAT16, iOS16, mlprogram, RangeDim 1..512)
        -> linear_quantize_weights(INT8, linear_symmetric)
        -> metadado model_version -> save .mlpackage -> coremlcompiler -> .mlmodelc

Entradas `input_ids`/`attention_mask` (int32); sem `token_type_ids` (XLM-R,
type_vocab_size=1, o tokenizer não emite). Saída `logits` (sem softmax).
Também escreve `NLI2Labels.json` a partir de `config.id2label`.

Uso:  uv run python convert.py
"""
import json
import os
import shutil
import subprocess
import sys

import numpy as np
import torch

HERE = os.path.dirname(os.path.abspath(__file__))
SPIKES = os.path.dirname(HERE)
sys.path.append(os.path.join(SPIKES, "02-coreml-latencia"))  # coreml_shims
sys.path.append(os.path.join(SPIKES, "02c-nli-executavel"))  # candidates

import coreml_shims  # noqa: E402,F401  (new_ones / bitwise_and; não muda arquitetura)
import coremltools as ct  # noqa: E402
from coremltools.optimize.coreml import (  # noqa: E402
    OpLinearQuantizerConfig,
    OptimizationConfig,
    linear_quantize_weights,
)
from transformers import AutoModelForSequenceClassification  # noqa: E402

from candidates import CANDIDATES, MAX_SEQ  # noqa: E402

MODEL_VERSION = "minilmv2-l6-mnli-xnli-v1"
CANDIDATE = next(c for c in CANDIDATES if c["short"] == "L6")
MODEL_ID = CANDIDATE["id"]
BUILD = os.path.join(HERE, "build")
PKG = os.path.join(BUILD, "NLI2.mlpackage")
COMPILED = os.path.join(BUILD, "NLI2.mlmodelc")


class NLIWrapper(torch.nn.Module):
    def __init__(self, backbone):
        super().__init__()
        self.backbone = backbone

    def forward(self, input_ids, attention_mask):
        return self.backbone(input_ids=input_ids, attention_mask=attention_mask,
                             return_dict=False)[0]


def dir_size_mb(path):
    return sum(os.path.getsize(os.path.join(r, f))
               for r, _, fs in os.walk(path) for f in fs) / (1024 * 1024)


def main():
    os.makedirs(BUILD, exist_ok=True)
    backbone = AutoModelForSequenceClassification.from_pretrained(MODEL_ID).float().eval()
    cfg = backbone.config
    revision = getattr(cfg, "_commit_hash", None)
    id2label = {str(k): v for k, v in sorted(cfg.id2label.items())}
    print(f"id2label={id2label} type_vocab_size={cfg.type_vocab_size} rev={revision}")
    assert [id2label[k].lower() for k in ("0", "1", "2")] == ["entailment", "neutral", "contradiction"]

    with open(os.path.join(HERE, "NLI2Labels.json"), "w") as f:
        json.dump({
            "evidence": f"config.json id2label de {MODEL_ID}@{revision}",
            "model_version": MODEL_VERSION,
            "id2label": id2label,
        }, f, ensure_ascii=False, indent=2)
        f.write("\n")

    seq = 32
    ex_ids = torch.randint(5, 1000, (1, seq), dtype=torch.long)
    ex_mask = torch.ones((1, seq), dtype=torch.long)
    with torch.no_grad():
        traced = torch.jit.trace(NLIWrapper(backbone).eval(), (ex_ids, ex_mask), strict=False)
    seq_dim = ct.RangeDim(lower_bound=1, upper_bound=MAX_SEQ, default=seq)
    mlmodel = ct.convert(
        traced,
        inputs=[ct.TensorType(name="input_ids", shape=(1, seq_dim), dtype=np.int32),
                ct.TensorType(name="attention_mask", shape=(1, seq_dim), dtype=np.int32)],
        outputs=[ct.TensorType(name="logits")],
        compute_precision=ct.precision.FLOAT16,
        minimum_deployment_target=ct.target.iOS16,
        convert_to="mlprogram",
    )
    q = linear_quantize_weights(mlmodel, config=OptimizationConfig(
        global_config=OpLinearQuantizerConfig(mode="linear_symmetric", dtype="int8")))
    q.short_description = (f"{MODEL_ID} — NLI de 3 classes (segundo modelo do ensemble). "
                           "Logits sem softmax; ordem em NLI2Labels.json.")
    q.author = "MoritzLaurer (pesos); conversão Spike 10"
    q.license = "MIT (modelo original)"
    q.version = MODEL_VERSION
    q.user_defined_metadata["model_version"] = MODEL_VERSION
    q.user_defined_metadata["source_model"] = MODEL_ID
    q.user_defined_metadata["source_revision"] = str(revision)
    q.user_defined_metadata["id2label"] = json.dumps(id2label)
    q.user_defined_metadata["quantization"] = "int8 linear_symmetric (pesos); compute FP16"
    q.input_description["input_ids"] = "Ids XLM-R: <s> premissa </s></s> hipótese </s>"
    q.input_description["attention_mask"] = "1 para tokens reais"
    q.output_description["logits"] = "Logits [1,3] entailment/neutral/contradiction"

    shutil.rmtree(PKG, ignore_errors=True)
    q.save(PKG)
    shutil.rmtree(COMPILED, ignore_errors=True)
    subprocess.run(["xcrun", "coremlcompiler", "compile", PKG, BUILD], check=True,
                   stdout=subprocess.DEVNULL)
    print(f"mlpackage={dir_size_mb(PKG):.1f} MiB  mlmodelc={dir_size_mb(COMPILED):.1f} MiB")


if __name__ == "__main__":
    main()
