# -*- coding: utf-8 -*-
"""
SPIKE 2b — Conversão de teste MÍNIMA de um candidato de NLI para Core ML.

Uso:
    python convert_candidate.py <model_id> [--keep]

O que faz (e o que NÃO faz):
  - Carrega o modelo, imprime id2label (nº de classes).
  - Traça (jit.trace) backbone -> logits (sem softmax; feito no app).
  - Converte para Core ML FLOAT16 (mlprogram, iOS16), depois quantiza pesos INT8.
  - Mede tamanho de cada variante.
  - SANITY CHECK: roda o .mlpackage INT8 via coremltools no desktop e compara os
    logits com o PyTorch original sobre UM par PT-BR real (cos dos logits + argmax).
    Isso confirma que a CONVERSÃO preserva a saída — NÃO é validação de acurácia
    em PT-BR (isso é o Spike 1, fora do escopo desta tarefa).

Se a conversão falhar por op não suportada, imprime a op/mensagem EXATA e encerra
com erro — NÃO reescreve a arquitetura do modelo (trava do pedido).

Latência de device NÃO é medida aqui (ambiente sem Xcode completo; é o Spike 3).
"""
import argparse
import json
import os
import shutil
import sys
import traceback

import numpy as np
import torch
from transformers import AutoModelForSequenceClassification, AutoTokenizer

import coremltools as ct
from coremltools.optimize.coreml import (
    OpLinearQuantizerConfig,
    OptimizationConfig,
    linear_quantize_weights,
)

from common import MAX_SEQ, NLI_HYPOTHESIS, NLI_PREMISE, dir_size_mb

BUILD = os.path.join(os.path.dirname(__file__), "build")
RESULTS = os.path.join(os.path.dirname(__file__), "results")
os.makedirs(BUILD, exist_ok=True)
os.makedirs(RESULTS, exist_ok=True)


class NLIWrapper(torch.nn.Module):
    """SequenceClassification -> logits (sem softmax; feito no app)."""

    def __init__(self, backbone):
        super().__init__()
        self.backbone = backbone

    def forward(self, input_ids, attention_mask):
        out = self.backbone(input_ids=input_ids, attention_mask=attention_mask,
                            return_dict=False)
        return out[0]  # logits (B, num_labels)


def safe_name(model_id: str) -> str:
    return model_id.replace("/", "__")


def torch_logits(backbone, tok):
    enc = tok(NLI_PREMISE, NLI_HYPOTHESIS, return_tensors="pt",
              truncation=True, max_length=MAX_SEQ)
    with torch.no_grad():
        out = backbone(input_ids=enc["input_ids"],
                       attention_mask=enc["attention_mask"], return_dict=False)[0]
    ids = enc["input_ids"].to(torch.int32).numpy()
    mask = enc["attention_mask"].to(torch.int32).numpy()
    return out.numpy()[0], ids, mask


def convert(model_id: str, keep: bool) -> dict:
    rec = {"id": model_id, "converts": False, "num_labels": None,
           "id2label": None, "fp16_mb": None, "int8_mb": None,
           "logits_cos": None, "argmax_match": None, "error": None}

    print(f"[2b] carregando {model_id} ...", flush=True)
    backbone = AutoModelForSequenceClassification.from_pretrained(model_id).float().eval()
    tok = AutoTokenizer.from_pretrained(model_id)
    rec["id2label"] = {int(k): v for k, v in backbone.config.id2label.items()}
    rec["num_labels"] = int(backbone.config.num_labels)
    print(f"[2b] num_labels={rec['num_labels']} id2label={rec['id2label']}", flush=True)

    ref_logits, ids, mask = torch_logits(backbone, tok)
    print(f"[2b] logits PyTorch (ref) = {ref_logits}", flush=True)

    model = NLIWrapper(backbone).eval()
    seq = 32
    ex_ids = torch.randint(0, 1000, (1, seq), dtype=torch.long)
    ex_mask = torch.ones((1, seq), dtype=torch.long)
    print("[2b] traçando (torch.jit.trace) ...", flush=True)
    with torch.no_grad():
        traced = torch.jit.trace(model, (ex_ids, ex_mask), strict=False)

    seq_dim = ct.RangeDim(lower_bound=1, upper_bound=MAX_SEQ, default=seq)
    inputs = [
        ct.TensorType(name="input_ids", shape=(1, seq_dim), dtype=np.int32),
        ct.TensorType(name="attention_mask", shape=(1, seq_dim), dtype=np.int32),
    ]

    print("[2b] convertendo para Core ML (FLOAT16, iOS16, mlprogram) ...", flush=True)
    mlmodel = ct.convert(
        traced,
        inputs=inputs,
        outputs=[ct.TensorType(name="logits")],
        compute_precision=ct.precision.FLOAT16,
        minimum_deployment_target=ct.target.iOS16,
        convert_to="mlprogram",
    )
    rec["converts"] = True
    fp16_path = os.path.join(BUILD, f"{safe_name(model_id)}_fp16.mlpackage")
    mlmodel.save(fp16_path)
    rec["fp16_mb"] = round(dir_size_mb(fp16_path), 1)
    print(f"[2b] FLOAT16 salvo: {rec['fp16_mb']} MB", flush=True)

    print("[2b] quantizando pesos para INT8 ...", flush=True)
    q_cfg = OptimizationConfig(
        global_config=OpLinearQuantizerConfig(mode="linear_symmetric", dtype="int8"))
    mlmodel_int8 = linear_quantize_weights(mlmodel, config=q_cfg)
    int8_path = os.path.join(BUILD, f"{safe_name(model_id)}_int8.mlpackage")
    mlmodel_int8.save(int8_path)
    rec["int8_mb"] = round(dir_size_mb(int8_path), 1)
    print(f"[2b] INT8 salvo: {rec['int8_mb']} MB", flush=True)

    # Sanity-check: o .mlpackage INT8 preserva a saída do PyTorch?
    try:
        cm = ct.models.MLModel(int8_path)
        out = cm.predict({"input_ids": ids, "attention_mask": mask})
        cm_logits = np.asarray(out[list(out.keys())[0]]).reshape(-1)
        cos = float(np.dot(cm_logits, ref_logits) /
                    (np.linalg.norm(cm_logits) * np.linalg.norm(ref_logits) + 1e-9))
        rec["logits_cos"] = round(cos, 4)
        rec["argmax_match"] = bool(int(np.argmax(cm_logits)) == int(np.argmax(ref_logits)))
        print(f"[2b] INT8 vs PyTorch: cos(logits)={rec['logits_cos']} "
              f"argmax_match={rec['argmax_match']} | CoreML logits={cm_logits}", flush=True)
    except Exception as e:  # noqa: BLE001
        rec["error"] = f"predict_int8: {type(e).__name__}: {e}"
        print(f"[2b] AVISO: falha ao rodar INT8 no desktop: {rec['error']}", flush=True)

    if not keep:
        shutil.rmtree(fp16_path, ignore_errors=True)
        shutil.rmtree(int8_path, ignore_errors=True)
        print("[2b] .mlpackages removidos (use --keep para manter)", flush=True)

    return rec


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("model_id")
    ap.add_argument("--keep", action="store_true", help="não apagar os .mlpackage gerados")
    args = ap.parse_args()

    try:
        rec = convert(args.model_id, args.keep)
    except Exception as e:  # noqa: BLE001
        rec = {"id": args.model_id, "converts": False, "error": f"{type(e).__name__}: {e}"}
        print("\n!!! FALHA NA CONVERSÃO !!!")
        print(f"Tipo: {type(e).__name__}\nMensagem: {e}")
        traceback.print_exc()

    out_path = os.path.join(RESULTS, f"{safe_name(args.model_id)}.json")
    with open(out_path, "w") as f:
        json.dump(rec, f, ensure_ascii=False, indent=2)
    print(f"\n[2b] resultado -> {out_path}")
    print(json.dumps(rec, ensure_ascii=False, indent=2))
    sys.exit(0 if rec.get("converts") else 1)


if __name__ == "__main__":
    main()
