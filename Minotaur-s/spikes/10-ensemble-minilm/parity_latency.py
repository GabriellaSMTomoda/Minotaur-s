# -*- coding: utf-8 -*-
"""Paridade PyTorch (FP32) × Core ML INT8 (CPU_ONLY) + tamanho + latência no Mac.

Pares: 15 regressões conhecidas + 20 do Spike 1 (`pt_data.all_pairs`).
Tokenização: tokenizer HF do modelo, par `<s> P </s></s> H </s>`, truncation
only_first em 512 (reserva a hipótese, como o app faz).

Mede:
  - argmax igual, max |Δprob| (softmax T=1), max |Δlogit|, NaN/Inf;
  - concordância de rótulo com `allowed` (só informativo; não é métrica de acurácia);
  - tamanho .mlpackage / .mlmodelc / weight.bin;
  - latência Mac CPU_ONLY: carga a frio do .mlmodelc e predict por comprimento
    (pares reais + entradas sintéticas de 64/128/256/512 tokens).

Uso:  uv run python parity_latency.py   -> build/parity_latency.json
"""
import hashlib
import json
import os
import platform
import statistics
import subprocess
import time

import coremltools as ct
import numpy as np
import torch
from transformers import AutoModelForSequenceClassification, AutoTokenizer

from pt_data import all_pairs

HERE = os.path.dirname(os.path.abspath(__file__))
BUILD = os.path.join(HERE, "build")
PKG = os.path.join(BUILD, "NLI2.mlpackage")
COMPILED = os.path.join(BUILD, "NLI2.mlmodelc")
MODEL_ID = "MoritzLaurer/multilingual-MiniLMv2-L6-mnli-xnli"
LABELS = ["entailment", "neutral", "contradiction"]


def softmax(x):
    x = np.asarray(x, dtype=np.float64)
    e = np.exp(x - x.max())
    return e / e.sum()


def size_mib(path):
    return sum(os.path.getsize(os.path.join(r, f)) for r, _, fs in os.walk(path) for f in fs) / 2**20


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def main():
    tok = AutoTokenizer.from_pretrained(MODEL_ID)
    pt = AutoModelForSequenceClassification.from_pretrained(MODEL_ID).float().eval()
    torch.set_num_threads(os.cpu_count() or 1)

    t0 = time.perf_counter()
    cm = ct.models.CompiledMLModel(COMPILED, compute_units=ct.ComputeUnit.CPU_ONLY)
    load_s = time.perf_counter() - t0
    spec_meta = ct.models.MLModel(PKG, skip_model_load=True).user_defined_metadata

    rows = []
    for p in all_pairs():
        enc = tok(p["premise"], p["hypothesis"], truncation="only_first", max_length=512,
                  return_tensors="np")
        assert "token_type_ids" not in enc
        ids = enc["input_ids"].astype(np.int32)
        mask = enc["attention_mask"].astype(np.int32)
        with torch.no_grad():
            pl = pt(input_ids=torch.from_numpy(ids).long(),
                    attention_mask=torch.from_numpy(mask).long()).logits.numpy()[0]
        cl = np.asarray(cm.predict({"input_ids": ids, "attention_mask": mask})["logits"]).reshape(-1)
        pp, cp = softmax(pl), softmax(cl)
        rows.append({
            "id": p["id"], "seq_len": int(ids.shape[1]), "allowed": p["allowed"],
            "pytorch_logits": [round(float(x), 5) for x in pl],
            "coreml_logits": [round(float(x), 5) for x in cl],
            "pytorch_label": LABELS[int(pp.argmax())], "coreml_label": LABELS[int(cp.argmax())],
            "argmax_equal": int(pp.argmax()) == int(cp.argmax()),
            "max_abs_prob_diff": float(np.abs(pp - cp).max()),
            "max_abs_logit_diff": float(np.abs(pl - cl).max()),
            "coreml_finite": bool(np.isfinite(cl).all()),
            "pytorch_probs": [round(float(x), 4) for x in pp],
            "coreml_probs": [round(float(x), 4) for x in cp],
        })

    # latência
    def bench(ids, mask, n):
        x = {"input_ids": ids, "attention_mask": mask}
        for _ in range(3):
            cm.predict(x)
        ts = []
        for _ in range(n):
            t = time.perf_counter()
            cm.predict(x)
            ts.append((time.perf_counter() - t) * 1000)
        return ts

    real_ms = []
    for p in all_pairs():
        enc = tok(p["premise"], p["hypothesis"], truncation="only_first", max_length=512,
                  return_tensors="np")
        real_ms += bench(enc["input_ids"].astype(np.int32), enc["attention_mask"].astype(np.int32), 10)
    synth = {}
    rng = np.random.default_rng(0)
    for L in (64, 128, 256, 512):
        ids = rng.integers(5, 250000, size=(1, L)).astype(np.int32)
        ids[0, 0], ids[0, -1] = 0, 2
        ts = bench(ids, np.ones((1, L), dtype=np.int32), 30)
        synth[str(L)] = {"median_ms": round(statistics.median(ts), 2),
                         "p90_ms": round(float(np.percentile(ts, 90)), 2)}

    weight = os.path.join(COMPILED, "weights", "weight.bin")
    chip = subprocess.run(["sysctl", "-n", "machdep.cpu.brand_string"], capture_output=True,
                          text=True).stdout.strip()
    summary = {
        "pairs": len(rows),
        "argmax_equal": sum(r["argmax_equal"] for r in rows),
        "max_abs_prob_diff": max(r["max_abs_prob_diff"] for r in rows),
        "mean_abs_prob_diff": statistics.mean(r["max_abs_prob_diff"] for r in rows),
        "max_abs_logit_diff": max(r["max_abs_logit_diff"] for r in rows),
        "all_finite": all(r["coreml_finite"] for r in rows),
        "seq_len_min_max": [min(r["seq_len"] for r in rows), max(r["seq_len"] for r in rows)],
        "coreml_label_in_allowed": sum(r["coreml_label"] in r["allowed"] for r in rows),
        "regressions_coreml_label_in_allowed": sum(
            r["coreml_label"] in r["allowed"] for r in rows if not r["id"].startswith("spike1")),
        "regressions_coreml_contradiction": sum(
            r["coreml_label"] == "contradiction" for r in rows if not r["id"].startswith("spike1")),
        "size_mib": {"mlpackage": round(size_mib(PKG), 1), "mlmodelc": round(size_mib(COMPILED), 1),
                     "mlmodelc_weight_bin": round(os.path.getsize(weight) / 2**20, 1)},
        "sha256_mlmodelc_weight_bin": sha256(weight),
        "metadata": dict(spec_meta),
        "latency_mac_cpu_only": {
            "machine": f"{chip} / macOS {platform.mac_ver()[0]}",
            "compiled_load_s": round(load_s, 3),
            "real_pairs_median_ms": round(statistics.median(real_ms), 2),
            "real_pairs_p90_ms": round(float(np.percentile(real_ms, 90)), 2),
            "synthetic_by_len": synth,
        },
        "versions": {"coremltools": ct.__version__, "torch": torch.__version__},
    }
    with open(os.path.join(BUILD, "parity_latency.json"), "w", encoding="utf-8") as f:
        json.dump({"summary": summary, "rows": rows}, f, ensure_ascii=False, indent=2)
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    for r in rows:
        print(f"{r['id']:14s} L={r['seq_len']:3d} pt={r['pytorch_label']:13s} cm={r['coreml_label']:13s} "
              f"dP={r['max_abs_prob_diff']:.4f} allowed={r['allowed']}")


if __name__ == "__main__":
    main()
