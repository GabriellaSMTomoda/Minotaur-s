# -*- coding: utf-8 -*-
"""
SPIKE 7 — FILTRO 1 (conversão) + referência para o FILTRO 2 (execução em device).

Mesma mecânica do Spike 2c, com UMA diferença que não é detalhe: BERTimbau é
BERT, e BERT usa `token_type_ids` para separar premissa de hipótese (segmento 0
vs. segmento 1). O XLM-R/MiniLMv2 em produção hoje não usa — o `XLMRTokenizer`
do app produz só `input_ids`, e o `NLIService` alimenta o modelo com
`input_ids` + `attention_mask`.

Consequência: os candidatos BERT são convertidos com TRÊS entradas. Isso é custo
de integração real, não um ajuste de script — está contabilizado no RESULTADO.md.
Converter um BERT com token_type_ids zerado "para caber na interface atual"
degradaria o modelo silenciosamente, que é justamente a classe de erro que este
spike existe para não repetir.

Saída: build/<short>_int8.mlpackage + build/manifest.json (consumido pelo
harness de device).

Uso:
  ../02-coreml-latencia/.venv/bin/python convert_and_reference.py [short ...]
"""
import json
import math
import os
import shutil
import sys
import traceback

import numpy as np
import torch

# shims de versão do Spike 2 (new_ones / bitwise_and). NÃO alteram arquitetura.
sys.path.append(os.path.join(os.path.dirname(__file__), "..", "02-coreml-latencia"))
import coreml_shims  # noqa: E402,F401

import coremltools as ct  # noqa: E402
from coremltools.optimize.coreml import (  # noqa: E402
    OpLinearQuantizerConfig,
    OptimizationConfig,
    linear_quantize_weights,
)
from transformers import AutoModelForSequenceClassification, AutoTokenizer  # noqa: E402

from candidates import CANDIDATES, MAX_SEQ, NLI_HYPOTHESIS, NLI_PREMISE  # noqa: E402

BUILD = os.path.join(os.path.dirname(__file__), "build")
os.makedirs(BUILD, exist_ok=True)


def dir_size_mb(path: str) -> float:
    total = 0
    for root, _dirs, files in os.walk(path):
        for f in files:
            fp = os.path.join(root, f)
            if os.path.exists(fp):
                total += os.path.getsize(fp)
    return total / (1024 * 1024)


def cos(a, b):
    a = np.asarray(a, dtype=np.float64).reshape(-1)
    b = np.asarray(b, dtype=np.float64).reshape(-1)
    return float(np.dot(a, b) / (np.linalg.norm(a) * np.linalg.norm(b) + 1e-9))


class NLIWrapperWithSegments(torch.nn.Module):
    """SequenceClassification -> logits, com token_type_ids (BERT)."""

    def __init__(self, backbone):
        super().__init__()
        self.backbone = backbone

    def forward(self, input_ids, attention_mask, token_type_ids):
        return self.backbone(input_ids=input_ids, attention_mask=attention_mask,
                             token_type_ids=token_type_ids, return_dict=False)[0]


class NLIWrapper(torch.nn.Module):
    """SequenceClassification -> logits, sem segmentos (XLM-R/RoBERTa)."""

    def __init__(self, backbone):
        super().__init__()
        self.backbone = backbone

    def forward(self, input_ids, attention_mask):
        return self.backbone(input_ids=input_ids, attention_mask=attention_mask,
                             return_dict=False)[0]


def convert_one(c: dict) -> dict:
    short, model_id = c["short"], c["id"]
    rec = {
        "short": short, "id": model_id, "base": c["base"], "data": c["data"],
        "converts": False, "num_labels": None, "label_order": c["label_order"],
        "uses_token_type_ids": None, "tokenizer_kind": None,
        "int8_mb": None, "seq_len": None,
        "input_ids": None, "attention_mask": None, "token_type_ids": None,
        "pytorch_logits": None, "desktop_coreml_logits": None,
        "desktop_cos": None, "desktop_argmax_match": None, "error": None,
    }

    print(f"\n===== [{short}] {model_id} =====", flush=True)
    backbone = AutoModelForSequenceClassification.from_pretrained(model_id).float().eval()
    tok = AutoTokenizer.from_pretrained(model_id)

    rec["num_labels"] = int(backbone.config.num_labels)
    rec["tokenizer_kind"] = type(tok).__name__
    if rec["num_labels"] != 3:
        rec["error"] = f"FILTRO 0: num_labels={rec['num_labels']} (RF-07.2 exige 3)"
        print(f"[{short}] {rec['error']}", flush=True)
        return rec

    # Par PT-BR fixo -> tokenização + logits PyTorch de referência.
    enc = tok(NLI_PREMISE, NLI_HYPOTHESIS, return_tensors="pt",
              truncation=True, max_length=MAX_SEQ, return_attention_mask=True)
    ids_t = enc["input_ids"]
    mask_t = enc.get("attention_mask")
    if mask_t is None:
        mask_t = torch.ones_like(ids_t)

    # A presença de token_type_ids na saída do tokenizer é o que decide a
    # interface do modelo convertido. Não é escolha nossa: é da arquitetura.
    types_t = enc.get("token_type_ids")
    usa_segmentos = types_t is not None
    rec["uses_token_type_ids"] = bool(usa_segmentos)
    print(f"[{short}] tokenizer={rec['tokenizer_kind']} "
          f"token_type_ids={'SIM' if usa_segmentos else 'nao'} "
          f"seq_len={int(ids_t.shape[1])}", flush=True)

    with torch.no_grad():
        if usa_segmentos:
            pt_logits = backbone(input_ids=ids_t, attention_mask=mask_t,
                                 token_type_ids=types_t, return_dict=False)[0].numpy()[0]
        else:
            pt_logits = backbone(input_ids=ids_t, attention_mask=mask_t,
                                 return_dict=False)[0].numpy()[0]

    rec["input_ids"] = ids_t[0].to(torch.int64).tolist()
    rec["attention_mask"] = mask_t[0].to(torch.int64).tolist()
    rec["token_type_ids"] = types_t[0].to(torch.int64).tolist() if usa_segmentos else None
    rec["seq_len"] = int(ids_t.shape[1])
    rec["pytorch_logits"] = [float(x) for x in pt_logits]
    print(f"[{short}] logits PyTorch={pt_logits}", flush=True)

    # Trace + convert FLOAT16, shape dinâmico como o modelo em produção (RangeDim).
    seq = 32
    ex_ids = torch.randint(0, 1000, (1, seq), dtype=torch.long)
    ex_mask = torch.ones((1, seq), dtype=torch.long)
    ex_types = torch.zeros((1, seq), dtype=torch.long)

    seq_dim = ct.RangeDim(lower_bound=1, upper_bound=MAX_SEQ, default=seq)
    inputs = [
        ct.TensorType(name="input_ids", shape=(1, seq_dim), dtype=np.int32),
        ct.TensorType(name="attention_mask", shape=(1, seq_dim), dtype=np.int32),
    ]
    if usa_segmentos:
        model = NLIWrapperWithSegments(backbone).eval()
        example = (ex_ids, ex_mask, ex_types)
        inputs.append(ct.TensorType(name="token_type_ids", shape=(1, seq_dim), dtype=np.int32))
    else:
        model = NLIWrapper(backbone).eval()
        example = (ex_ids, ex_mask)

    with torch.no_grad():
        traced = torch.jit.trace(model, example, strict=False)

    print(f"[{short}] convertendo FLOAT16 (iOS16, mlprogram) ...", flush=True)
    mlmodel = ct.convert(
        traced, inputs=inputs, outputs=[ct.TensorType(name="logits")],
        compute_precision=ct.precision.FLOAT16,
        minimum_deployment_target=ct.target.iOS16, convert_to="mlprogram",
    )
    rec["converts"] = True
    fp16_path = os.path.join(BUILD, f"{short}_fp16.mlpackage")
    mlmodel.save(fp16_path)
    print(f"[{short}] FLOAT16 = {round(dir_size_mb(fp16_path), 1)} MB", flush=True)

    print(f"[{short}] quantizando INT8 ...", flush=True)
    q_cfg = OptimizationConfig(
        global_config=OpLinearQuantizerConfig(mode="linear_symmetric", dtype="int8"))
    mlmodel_int8 = linear_quantize_weights(mlmodel, config=q_cfg)
    int8_path = os.path.join(BUILD, f"{short}_int8.mlpackage")
    mlmodel_int8.save(int8_path)
    rec["int8_mb"] = round(dir_size_mb(int8_path), 1)
    print(f"[{short}] INT8 = {rec['int8_mb']} MB", flush=True)

    # Sanity no desktop: o .mlpackage INT8 preserva a saída do PyTorch?
    # CPU_ONLY evita o backend MPSGraph do Mac, que já abortou processo por shape
    # dinâmico (ERNIE-M, Spike 2c). O backend do device é problema do FILTRO 2.
    feed = {
        "input_ids": ids_t.to(torch.int32).numpy(),
        "attention_mask": mask_t.to(torch.int32).numpy(),
    }
    if usa_segmentos:
        feed["token_type_ids"] = types_t.to(torch.int32).numpy()
    try:
        cm = ct.models.MLModel(int8_path, compute_units=ct.ComputeUnit.CPU_ONLY)
        out = cm.predict(feed)
        cm_logits = np.asarray(out[list(out.keys())[0]]).reshape(-1)
        rec["desktop_coreml_logits"] = [float(x) for x in cm_logits]
        rec["desktop_cos"] = round(cos(cm_logits, pt_logits), 4)
        rec["desktop_argmax_match"] = bool(
            int(np.argmax(cm_logits)) == int(np.argmax(pt_logits)))
        print(f"[{short}] DESKTOP INT8 vs PyTorch: cos={rec['desktop_cos']} "
              f"argmax_match={rec['desktop_argmax_match']}", flush=True)
    except Exception as e:  # noqa: BLE001
        rec["error"] = f"predict_int8_desktop: {type(e).__name__}: {e}"
        print(f"[{short}] AVISO desktop predict: {rec['error']}", flush=True)

    shutil.rmtree(fp16_path, ignore_errors=True)
    return rec


def main():
    mpath = os.path.join(BUILD, "manifest.json")
    only = set(sys.argv[1:])
    manifest = {"pair": {"premise": NLI_PREMISE, "hypothesis": NLI_HYPOTHESIS}, "models": []}
    if os.path.exists(mpath):
        with open(mpath) as f:
            manifest = json.load(f)
    by_short = {m["short"]: i for i, m in enumerate(manifest["models"])}

    for c in CANDIDATES:
        if only and c["short"] not in only:
            continue
        try:
            rec = convert_one(c)
        except Exception as e:  # noqa: BLE001
            rec = {"short": c["short"], "id": c["id"], "converts": False,
                   "error": f"{type(e).__name__}: {e}"}
            print(f"\n!!! [{c['short']}] FALHA NA CONVERSÃO: {type(e).__name__}: {e}", flush=True)
            traceback.print_exc()
        if c["short"] in by_short:
            manifest["models"][by_short[c["short"]]] = rec
        else:
            manifest["models"].append(rec)
            by_short[c["short"]] = len(manifest["models"]) - 1

    def _clean(o):
        # json.dump escreve `NaN` literal, que é JSON inválido e quebra o
        # JSONDecoder do Swift — o manifest inteiro morre por um float ruim.
        if isinstance(o, float):
            return o if math.isfinite(o) else None
        if isinstance(o, list):
            return [_clean(x) for x in o]
        if isinstance(o, dict):
            return {k: _clean(v) for k, v in o.items()}
        return o

    with open(mpath, "w") as f:
        json.dump(_clean(manifest), f, ensure_ascii=False, indent=2, allow_nan=False)

    print("\n\n================ RESUMO FILTRO 1 ================")
    for m in manifest["models"]:
        print(f"  {m['short']:16s} converts={m.get('converts')} "
              f"int8={m.get('int8_mb')}MB seg={m.get('uses_token_type_ids')} "
              f"cos_desktop={m.get('desktop_cos')} err={m.get('error')}")
    print(f"\nmanifest -> {mpath}")


if __name__ == "__main__":
    main()
