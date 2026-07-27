# -*- coding: utf-8 -*-
"""
SPIKE 2c — FILTRO 1 (conversão) + geração da referência para o FILTRO 2 (execução).

Para cada candidato de candidates.py:
  - carrega modelo + tokenizer, lê id2label (2 classes -> reprova por RF-07.2);
  - tokeniza o par PT-BR fixo -> input_ids/attention_mask (int32);
  - PyTorch forward -> logits de referência;
  - trace -> ct.convert(FLOAT16, iOS16, mlprogram) -> INT8 (linear_symmetric);
  - roda o .mlpackage INT8 via coremltools no DESKTOP sobre o MESMO input e
    compara com o PyTorch (cos + argmax) — sanity da conversão;
  - salva o .mlpackage INT8 em build/<short>_int8.mlpackage.

No fim escreve build/manifest.json com, por modelo:
  short, id, converts, fp16_mb, int8_mb, id2label (ordenado), input_ids,
  attention_mask, seq_len, pytorch_logits, desktop_coreml_logits, desktop_cos,
  desktop_argmax_match, error.

O manifest é embarcado no harness: o app usa input_ids/attention_mask por modelo
para rodar .predict() no device e comparar os logits com pytorch_logits. Assim o
Filtro 2 mede EXECUÇÃO CORRETA, não só "não lança exceção".

Se um candidato falhar na conversão por op não suportada, registra a op/mensagem
EXATA e segue para o próximo — NÃO reescreve arquitetura (trava do pedido).

Reproduzir (venv pinado do Spike 2):
  ../02-coreml-latencia/.venv/bin/python convert_and_reference.py
"""
import json
import math
import os
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


class NLIWrapper(torch.nn.Module):
    """SequenceClassification -> logits (sem softmax; feito no app)."""

    def __init__(self, backbone):
        super().__init__()
        self.backbone = backbone

    def forward(self, input_ids, attention_mask):
        out = self.backbone(input_ids=input_ids, attention_mask=attention_mask,
                            return_dict=False)
        return out[0]


def cos(a, b):
    a = np.asarray(a, dtype=np.float64).reshape(-1)
    b = np.asarray(b, dtype=np.float64).reshape(-1)
    return float(np.dot(a, b) / (np.linalg.norm(a) * np.linalg.norm(b) + 1e-9))


def convert_one(c: dict) -> dict:
    short, model_id = c["short"], c["id"]
    rec = {
        "short": short, "id": model_id, "kind": c["kind"],
        "converts": False, "num_labels": None, "id2label": None,
        "fp16_mb": None, "int8_mb": None,
        "input_ids": None, "attention_mask": None, "seq_len": None,
        "pytorch_logits": None, "desktop_coreml_logits": None,
        "desktop_cos": None, "desktop_argmax_match": None,
        "class_ok": None, "error": None,
    }

    print(f"\n===== [{short}] {model_id} =====", flush=True)
    backbone = AutoModelForSequenceClassification.from_pretrained(model_id).float().eval()
    tok = AutoTokenizer.from_pretrained(model_id)
    id2label = {int(k): str(v) for k, v in backbone.config.id2label.items()}
    rec["id2label"] = id2label
    rec["num_labels"] = int(backbone.config.num_labels)
    labels_lower = [v.lower() for v in id2label.values()]
    has3 = rec["num_labels"] == 3 and all(
        any(k in " ".join(labels_lower) for k in [x]) for x in
        ["entail", "contradict", "neutral"]
    )
    rec["class_ok"] = bool(has3)
    print(f"[{short}] num_labels={rec['num_labels']} id2label={id2label} "
          f"class_ok(3 NLI)={rec['class_ok']}", flush=True)
    if not has3:
        rec["error"] = "reprovado FILTRO 0: nao tem 3 classes NLI (RF-07.2)"
        print(f"[{short}] {rec['error']}", flush=True)
        return rec

    # Par PT-BR fixo -> input_ids/mask + logits PyTorch de referência.
    # return_attention_mask=True: alguns tokenizers (ex.: ErnieM) não incluem a
    # máscara por padrão. Sem par único a máscara é toda 1s, mas mantemos o campo
    # explícito porque o wrapper/CoreML exige attention_mask como entrada.
    enc = tok(NLI_PREMISE, NLI_HYPOTHESIS, return_tensors="pt",
              truncation=True, max_length=MAX_SEQ, return_attention_mask=True)
    ids_t = enc["input_ids"]
    mask_t = enc.get("attention_mask")
    if mask_t is None:
        mask_t = torch.ones_like(ids_t)
    with torch.no_grad():
        pt_logits = backbone(input_ids=ids_t, attention_mask=mask_t,
                             return_dict=False)[0].numpy()[0]
    rec["input_ids"] = ids_t[0].to(torch.int64).tolist()
    rec["attention_mask"] = mask_t[0].to(torch.int64).tolist()
    rec["seq_len"] = int(ids_t.shape[1])
    rec["pytorch_logits"] = [float(x) for x in pt_logits]
    print(f"[{short}] seq_len={rec['seq_len']} logits PyTorch={pt_logits}", flush=True)

    # Trace + convert FLOAT16.
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
    print(f"[{short}] convertendo FLOAT16 (iOS16, mlprogram) ...", flush=True)
    mlmodel = ct.convert(
        traced, inputs=inputs, outputs=[ct.TensorType(name="logits")],
        compute_precision=ct.precision.FLOAT16,
        minimum_deployment_target=ct.target.iOS16, convert_to="mlprogram",
    )
    rec["converts"] = True
    fp16_path = os.path.join(BUILD, f"{short}_fp16.mlpackage")
    mlmodel.save(fp16_path)
    rec["fp16_mb"] = round(dir_size_mb(fp16_path), 1)
    print(f"[{short}] FLOAT16 = {rec['fp16_mb']} MB", flush=True)

    # INT8.
    print(f"[{short}] quantizando INT8 ...", flush=True)
    q_cfg = OptimizationConfig(
        global_config=OpLinearQuantizerConfig(mode="linear_symmetric", dtype="int8"))
    mlmodel_int8 = linear_quantize_weights(mlmodel, config=q_cfg)
    int8_path = os.path.join(BUILD, f"{short}_int8.mlpackage")
    mlmodel_int8.save(int8_path)
    rec["int8_mb"] = round(dir_size_mb(int8_path), 1)
    print(f"[{short}] INT8 = {rec['int8_mb']} MB", flush=True)

    # Sanity desktop: o .mlpackage INT8 preserva a saída?
    ids_np = ids_t.to(torch.int32).numpy()
    mask_np = mask_t.to(torch.int32).numpy()
    try:
        # CPU_ONLY no desktop: evita o backend MPSGraph do Mac, que pode abortar
        # o processo por MLIR/shape dinâmico (visto no ERNIE-M). Aqui só queremos a
        # referência de logits; o backend GPU/ANE é problema do device (Filtro 2).
        cm = ct.models.MLModel(int8_path, compute_units=ct.ComputeUnit.CPU_ONLY)
        out = cm.predict({"input_ids": ids_np, "attention_mask": mask_np})
        cm_logits = np.asarray(out[list(out.keys())[0]]).reshape(-1)
        rec["desktop_coreml_logits"] = [float(x) for x in cm_logits]
        rec["desktop_cos"] = round(cos(cm_logits, pt_logits), 4)
        rec["desktop_argmax_match"] = bool(
            int(np.argmax(cm_logits)) == int(np.argmax(pt_logits)))
        print(f"[{short}] DESKTOP CoreML INT8 vs PyTorch: cos={rec['desktop_cos']} "
              f"argmax_match={rec['desktop_argmax_match']} logits={cm_logits}",
              flush=True)
    except Exception as e:  # noqa: BLE001
        rec["error"] = f"predict_int8_desktop: {type(e).__name__}: {e}"
        print(f"[{short}] AVISO desktop predict: {rec['error']}", flush=True)

    # remove fp16 (não é embarcado; economiza espaço)
    import shutil
    shutil.rmtree(fp16_path, ignore_errors=True)
    return rec


def main():
    mpath = os.path.join(BUILD, "manifest.json")
    # Preserva entradas já geradas; argv opcional = rodar só alguns shorts.
    only = set(sys.argv[1:])
    if os.path.exists(mpath):
        with open(mpath) as f:
            manifest = json.load(f)
    else:
        manifest = {"pair": {"premise": NLI_PREMISE, "hypothesis": NLI_HYPOTHESIS},
                    "models": []}
    by_short = {m["short"]: i for i, m in enumerate(manifest["models"])}

    for c in CANDIDATES:
        if only and c["short"] not in only:
            continue
        try:
            rec = convert_one(c)
        except Exception as e:  # noqa: BLE001
            rec = {
                "short": c["short"], "id": c["id"], "kind": c["kind"],
                "converts": False, "error": f"{type(e).__name__}: {e}",
            }
            print(f"\n!!! [{c['short']}] FALHA NA CONVERSÃO !!!", flush=True)
            print(f"Tipo: {type(e).__name__}\nMensagem: {e}", flush=True)
            traceback.print_exc()
        if c["short"] in by_short:
            manifest["models"][by_short[c["short"]]] = rec
        else:
            manifest["models"].append(rec)

    # Sanitiza floats não-finitos (NaN/Inf) -> None. json.dump escreve `NaN`
    # literal por padrão, que é JSON INVÁLIDO e o JSONDecoder do Swift rejeita
    # (quebra o manifest inteiro). Ex.: erniem tem logits INT8 = NaN.
    def _clean(o):
        if isinstance(o, float):
            return o if math.isfinite(o) else None
        if isinstance(o, list):
            return [_clean(x) for x in o]
        if isinstance(o, dict):
            return {k: _clean(v) for k, v in o.items()}
        return o

    manifest = _clean(manifest)
    with open(mpath, "w") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=2, allow_nan=False)

    print("\n\n================ RESUMO FILTRO 1 ================")
    for m in manifest["models"]:
        print(f"  {m['short']:8s} converts={m.get('converts')} "
              f"int8={m.get('int8_mb')}MB cos_desktop={m.get('desktop_cos')} "
              f"err={m.get('error')}")
    print(f"\nmanifest -> {mpath}")


if __name__ == "__main__":
    main()
