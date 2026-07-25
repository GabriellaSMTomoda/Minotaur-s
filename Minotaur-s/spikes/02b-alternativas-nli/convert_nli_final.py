# -*- coding: utf-8 -*-
"""
Finalização do artefato Core ML do NLI definitivo (DT-18): mDeBERTa-v3-base-xnli
com o XSoftmax patchado.

Este script NÃO reabre a escolha do modelo nem revalida equivalência do zero —
reaproveita a classe `XSoftmaxPatched` já escrita e verificada em
`patch_deberta.py` (Spike 2b: cos=1,0, max|Δlogit|=0 vs. original) e só completa o
passo que faltava: quantizar para INT8 e salvar no caminho que o harness
`xcode-bench` (Spike 2) espera.

Gera:
  ../02-coreml-latencia/build/NLI_int8.mlpackage

Reproduzir (venv pinado do Spike 2):
  ../02-coreml-latencia/.venv/bin/python convert_nli_final.py
"""
import os
import sys

import numpy as np
import torch

sys.path.append(os.path.join(os.path.dirname(__file__), "..", "02-coreml-latencia"))
import coreml_shims  # noqa: E402,F401 — salvaguarda de versão (ver Spike 2)

import coremltools as ct  # noqa: E402
from coremltools.optimize.coreml import (  # noqa: E402
    OpLinearQuantizerConfig,
    OptimizationConfig,
    linear_quantize_weights,
)
from transformers import AutoModelForSequenceClassification, AutoTokenizer  # noqa: E402
from transformers.models.deberta_v2 import modeling_deberta_v2 as dv2  # noqa: E402

from common import MAX_SEQ, NLI_HYPOTHESIS, NLI_PREMISE, dir_size_mb  # noqa: E402
from patch_deberta import NLIWrapper, XSoftmaxPatched, logits_for  # noqa: E402

NLI_MODEL = "MoritzLaurer/mDeBERTa-v3-base-xnli-multilingual-nli-2mil7"

BUILD_TARGET = os.path.join(
    os.path.dirname(__file__), "..", "02-coreml-latencia", "build"
)


def main():
    os.makedirs(BUILD_TARGET, exist_ok=True)

    print(f"[nli-final] carregando {NLI_MODEL} ...", flush=True)
    backbone = AutoModelForSequenceClassification.from_pretrained(NLI_MODEL).float().eval()
    tok = AutoTokenizer.from_pretrained(NLI_MODEL)
    print(f"[nli-final] id2label = {backbone.config.id2label}", flush=True)

    enc = tok(NLI_PREMISE, NLI_HYPOTHESIS, return_tensors="pt",
              truncation=True, max_length=MAX_SEQ)
    ids, mask = enc["input_ids"], enc["attention_mask"]

    print("[nli-final] verificando equivalência do patch antes de converter ...", flush=True)
    orig_logits = logits_for(backbone, ids, mask)
    original = getattr(dv2, "XSoftmax", None)
    dv2.XSoftmax = XSoftmaxPatched
    try:
        patched_logits = logits_for(backbone, ids, mask)
    finally:
        if original is not None:
            dv2.XSoftmax = original

    max_abs = float(np.max(np.abs(orig_logits - patched_logits)))
    cos = float(np.dot(orig_logits, patched_logits) /
                (np.linalg.norm(orig_logits) * np.linalg.norm(patched_logits) + 1e-9))
    print(f"[nli-final] equivalência: max|Δlogit|={max_abs:.3e} cos={cos:.6f}", flush=True)
    if max_abs > 1e-3:
        raise RuntimeError(
            f"Patch do XSoftmax divergiu do original (max|Δ|={max_abs:.3e}); "
            "abortando conversão definitiva."
        )

    print("[nli-final] convertendo com XSoftmax patchado ...", flush=True)
    dv2.XSoftmax = XSoftmaxPatched
    try:
        model = NLIWrapper(backbone).eval()
        seq = 32
        ex_ids = torch.randint(0, 1000, (1, seq), dtype=torch.long)
        ex_mask = torch.ones((1, seq), dtype=torch.long)
        with torch.no_grad():
            traced = torch.jit.trace(model, (ex_ids, ex_mask), strict=False)
        seq_dim = ct.RangeDim(lower_bound=1, upper_bound=MAX_SEQ, default=seq)
        inputs = [
            ct.TensorType(name="input_ids", shape=(1, seq_dim), dtype=np.int32),
            ct.TensorType(name="attention_mask", shape=(1, seq_dim), dtype=np.int32),
        ]
        mlmodel = ct.convert(
            traced, inputs=inputs, outputs=[ct.TensorType(name="logits")],
            compute_precision=ct.precision.FLOAT16,
            minimum_deployment_target=ct.target.iOS16, convert_to="mlprogram",
        )
    finally:
        if original is not None:
            dv2.XSoftmax = original

    fp16_path = os.path.join(BUILD_TARGET, "NLI_fp16.mlpackage")
    mlmodel.save(fp16_path)
    fp16_mb = dir_size_mb(fp16_path)
    print(f"[nli-final] FLOAT16 salvo: {fp16_mb:.1f} MB -> {fp16_path}", flush=True)

    print("[nli-final] quantizando pesos para INT8 ...", flush=True)
    q_cfg = OptimizationConfig(global_config=OpLinearQuantizerConfig(mode="linear_symmetric", dtype="int8"))
    mlmodel_int8 = linear_quantize_weights(mlmodel, config=q_cfg)
    int8_path = os.path.join(BUILD_TARGET, "NLI_int8.mlpackage")
    mlmodel_int8.save(int8_path)
    int8_mb = dir_size_mb(int8_path)
    print(f"[nli-final] INT8 salvo:    {int8_mb:.1f} MB -> {int8_path}", flush=True)

    print("\n=== RESUMO NLI (definitivo, patchado) ===")
    print(f"  equivalência do patch: max|Δlogit|={max_abs:.3e} cos={cos:.6f}")
    print(f"  FLOAT16: {fp16_mb:.1f} MB")
    print(f"  INT8   : {int8_mb:.1f} MB")
    print("  min deployment target: iOS16 (compilação; não confirma runtime abaixo de 18.6)")


if __name__ == "__main__":
    main()
