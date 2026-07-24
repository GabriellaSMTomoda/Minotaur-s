# -*- coding: utf-8 -*-
"""
Spike 2 — Conversão do modelo de NLI para Core ML.

Modelo: mDeBERTa-v3-base-xnli-multilingual-nli-2mil7 (validado no Spike 1).

*** ESTE É O PONTO DE MAIOR RISCO DA SPEC (§7.1). ***
DeBERTa-v3 usa "disentangled attention" com operações (gather de posição
relativa etc.) que historicamente falham na conversão para Core ML.

Se a conversão falhar por operação não suportada, o script imprime a
operação/mensagem exata e encerra com erro — NÃO tenta reescrever a
arquitetura do modelo (instrução explícita do usuário / passo 3 da tarefa).

Grafo: input_ids + attention_mask -> logits (entailment/neutral/contradiction).
Seq length flexível (1..512).
"""
import os
import traceback

import numpy as np
import torch
from transformers import AutoModelForSequenceClassification

import coremltools as ct
from coremltools.optimize.coreml import (
    OpLinearQuantizerConfig,
    OptimizationConfig,
    linear_quantize_weights,
)

import coreml_shims  # noqa: F401 — registra o op `new_ones` no conversor
from common import MAX_SEQ, NLI_MODEL, dir_size_mb

BUILD = os.path.join(os.path.dirname(__file__), "build")
os.makedirs(BUILD, exist_ok=True)


class NLIWrapper(torch.nn.Module):
    """DeBERTa sequence-classification -> logits (sem softmax; feito no app)."""

    def __init__(self, backbone):
        super().__init__()
        self.backbone = backbone

    def forward(self, input_ids, attention_mask):
        out = self.backbone(input_ids=input_ids, attention_mask=attention_mask, return_dict=False)
        return out[0]  # logits (B, 3)


def main():
    print(f"[nli] carregando {NLI_MODEL} ...", flush=True)
    # O checkpoint do mDeBERTa é salvo em fp16; carregamos em fp32 para o
    # conversor lidar com a precisão de forma uniforme (senão o layer_norm
    # recebe x=fp16 e epsilon=fp32 e a validação do coremltools falha).
    backbone = AutoModelForSequenceClassification.from_pretrained(NLI_MODEL).float()
    backbone.eval()
    print(f"[nli] id2label = {backbone.config.id2label}", flush=True)
    model = NLIWrapper(backbone).eval()

    seq = 32
    example_ids = torch.randint(0, 1000, (1, seq), dtype=torch.long)
    example_mask = torch.ones((1, seq), dtype=torch.long)

    print("[nli] traçando (torch.jit.trace) ...", flush=True)
    with torch.no_grad():
        traced = torch.jit.trace(model, (example_ids, example_mask), strict=False)

    seq_dim = ct.RangeDim(lower_bound=1, upper_bound=MAX_SEQ, default=seq)
    inputs = [
        ct.TensorType(name="input_ids", shape=(1, seq_dim), dtype=np.int32),
        ct.TensorType(name="attention_mask", shape=(1, seq_dim), dtype=np.int32),
    ]

    print("[nli] convertendo para Core ML (FLOAT16, iOS16) ...", flush=True)
    mlmodel = ct.convert(
        traced,
        inputs=inputs,
        outputs=[ct.TensorType(name="logits")],
        compute_precision=ct.precision.FLOAT16,
        minimum_deployment_target=ct.target.iOS16,
        convert_to="mlprogram",
    )
    fp16_path = os.path.join(BUILD, "NLI_fp16.mlpackage")
    mlmodel.save(fp16_path)
    fp16_mb = dir_size_mb(fp16_path)
    print(f"[nli] FLOAT16 salvo: {fp16_mb:.1f} MB -> {fp16_path}", flush=True)

    print("[nli] quantizando pesos para INT8 ...", flush=True)
    q_cfg = OptimizationConfig(global_config=OpLinearQuantizerConfig(mode="linear_symmetric", dtype="int8"))
    mlmodel_int8 = linear_quantize_weights(mlmodel, config=q_cfg)
    int8_path = os.path.join(BUILD, "NLI_int8.mlpackage")
    mlmodel_int8.save(int8_path)
    int8_mb = dir_size_mb(int8_path)
    print(f"[nli] INT8 salvo:    {int8_mb:.1f} MB -> {int8_path}", flush=True)

    print("\n=== RESUMO NLI ===")
    print(f"  FLOAT16: {fp16_mb:.1f} MB")
    print(f"  INT8   : {int8_mb:.1f} MB")
    print("  min deployment target testado: iOS16")


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print("\n!!! FALHA NA CONVERSÃO (NLI / mDeBERTa-v3) !!!")
        print(f"Tipo: {type(e).__name__}")
        print(f"Mensagem: {e}")
        traceback.print_exc()
        raise
