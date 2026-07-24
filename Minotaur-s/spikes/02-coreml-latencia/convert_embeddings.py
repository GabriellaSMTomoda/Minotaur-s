# -*- coding: utf-8 -*-
"""
Spike 2 — Conversão do modelo de EMBEDDINGS para Core ML.

Modelo: paraphrase-multilingual-MiniLM-L12-v2 (validado no Spike 1).
Gera:
  build/Embeddings_fp16.mlpackage   (compute_precision FLOAT16)
  build/Embeddings_int8.mlpackage   (pesos quantizados INT8)
e imprime os tamanhos antes/depois.

O grafo replica o uso da spec (RF-06.3/06.4): input_ids + attention_mask ->
embedding da sentença (mean pooling + L2 normalize), com seq length flexível
(1..512) para aceitar chunks e afirmações de tamanhos variados.
"""
import os
import traceback

import numpy as np
import torch
from transformers import AutoModel

import coremltools as ct
from coremltools.optimize.coreml import (
    OpLinearQuantizerConfig,
    OptimizationConfig,
    linear_quantize_weights,
)

import coreml_shims  # noqa: F401 — registra o op `new_ones` no conversor
from common import EMBEDDING_MODEL, MAX_SEQ, dir_size_mb

BUILD = os.path.join(os.path.dirname(__file__), "build")
os.makedirs(BUILD, exist_ok=True)


class EmbeddingWrapper(torch.nn.Module):
    """BERT backbone + mean pooling + L2 normalize -> vetor de sentença."""

    def __init__(self, backbone):
        super().__init__()
        self.backbone = backbone

    def forward(self, input_ids, attention_mask):
        out = self.backbone(input_ids=input_ids, attention_mask=attention_mask, return_dict=False)
        token_embeddings = out[0]  # (B, T, H)
        mask = attention_mask.unsqueeze(-1).to(token_embeddings.dtype)  # (B, T, 1)
        summed = (token_embeddings * mask).sum(dim=1)
        counts = mask.sum(dim=1).clamp(min=1e-9)
        mean = summed / counts
        return torch.nn.functional.normalize(mean, p=2, dim=1)


def main():
    print(f"[embeddings] carregando {EMBEDDING_MODEL} ...", flush=True)
    backbone = AutoModel.from_pretrained(EMBEDDING_MODEL)
    backbone.eval()
    model = EmbeddingWrapper(backbone).eval()

    # Entrada de exemplo (seq 32) só para o trace; a conversão usa shape flexível.
    seq = 32
    example_ids = torch.randint(0, 1000, (1, seq), dtype=torch.long)
    example_mask = torch.ones((1, seq), dtype=torch.long)

    print("[embeddings] traçando (torch.jit.trace) ...", flush=True)
    with torch.no_grad():
        traced = torch.jit.trace(model, (example_ids, example_mask))

    seq_dim = ct.RangeDim(lower_bound=1, upper_bound=MAX_SEQ, default=seq)
    inputs = [
        ct.TensorType(name="input_ids", shape=(1, seq_dim), dtype=np.int32),
        ct.TensorType(name="attention_mask", shape=(1, seq_dim), dtype=np.int32),
    ]

    print("[embeddings] convertendo para Core ML (FLOAT16, iOS16) ...", flush=True)
    mlmodel = ct.convert(
        traced,
        inputs=inputs,
        outputs=[ct.TensorType(name="embedding")],
        compute_precision=ct.precision.FLOAT16,
        minimum_deployment_target=ct.target.iOS16,
        convert_to="mlprogram",
    )
    fp16_path = os.path.join(BUILD, "Embeddings_fp16.mlpackage")
    mlmodel.save(fp16_path)
    fp16_mb = dir_size_mb(fp16_path)
    print(f"[embeddings] FLOAT16 salvo: {fp16_mb:.1f} MB -> {fp16_path}", flush=True)

    print("[embeddings] quantizando pesos para INT8 ...", flush=True)
    q_cfg = OptimizationConfig(global_config=OpLinearQuantizerConfig(mode="linear_symmetric", dtype="int8"))
    mlmodel_int8 = linear_quantize_weights(mlmodel, config=q_cfg)
    int8_path = os.path.join(BUILD, "Embeddings_int8.mlpackage")
    mlmodel_int8.save(int8_path)
    int8_mb = dir_size_mb(int8_path)
    print(f"[embeddings] INT8 salvo:    {int8_mb:.1f} MB -> {int8_path}", flush=True)

    print("\n=== RESUMO EMBEDDINGS ===")
    print(f"  FLOAT16: {fp16_mb:.1f} MB")
    print(f"  INT8   : {int8_mb:.1f} MB")
    print("  min deployment target testado: iOS16")


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print("\n!!! FALHA NA CONVERSÃO (EMBEDDINGS) !!!")
        print(f"Tipo: {type(e).__name__}")
        print(f"Mensagem: {e}")
        traceback.print_exc()
        raise
