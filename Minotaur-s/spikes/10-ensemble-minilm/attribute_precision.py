# -*- coding: utf-8 -*-
"""Atribui o desvio de paridade: FP32 puro vs FP16 sem quantização vs INT8 (artefato final).

Converte variantes temporárias em um diretório descartável (argv[1]) e compara os
mesmos 35 pares contra PyTorch FP32. Não altera build/NLI2.*.

Uso:  uv run python attribute_precision.py /caminho/tmp  -> build/attribution.json
"""
import json
import os
import shutil
import sys

import coremltools as ct
import numpy as np
import torch
from transformers import AutoModelForSequenceClassification, AutoTokenizer

import convert  # noqa: F401  (aplica coreml_shims + paths)
from convert import MAX_SEQ, MODEL_ID, NLIWrapper
from pt_data import all_pairs

HERE = os.path.dirname(os.path.abspath(__file__))


def softmax(x):
    e = np.exp(x - x.max())
    return e / e.sum()


def main():
    tmp = sys.argv[1]
    os.makedirs(tmp, exist_ok=True)
    tok = AutoTokenizer.from_pretrained(MODEL_ID)
    pt = AutoModelForSequenceClassification.from_pretrained(MODEL_ID).float().eval()
    with torch.no_grad():
        traced = torch.jit.trace(NLIWrapper(pt).eval(),
                                 (torch.randint(5, 1000, (1, 32)), torch.ones((1, 32), dtype=torch.long)),
                                 strict=False)
    dim = ct.RangeDim(1, MAX_SEQ, default=32)
    inputs = [ct.TensorType(name="input_ids", shape=(1, dim), dtype=np.int32),
              ct.TensorType(name="attention_mask", shape=(1, dim), dtype=np.int32)]
    models = {}
    for name, prec in (("fp32", ct.precision.FLOAT32), ("fp16", ct.precision.FLOAT16)):
        m = ct.convert(traced, inputs=inputs, outputs=[ct.TensorType(name="logits")],
                       compute_precision=prec, minimum_deployment_target=ct.target.iOS16,
                       convert_to="mlprogram")
        path = os.path.join(tmp, f"{name}.mlpackage")
        m.save(path)
        models[name] = ct.models.MLModel(path, compute_units=ct.ComputeUnit.CPU_ONLY)
    models["int8_final"] = ct.models.CompiledMLModel(
        os.path.join(HERE, "build", "NLI2.mlmodelc"), compute_units=ct.ComputeUnit.CPU_ONLY)

    res = {k: {"argmax_equal": 0, "max_abs_prob_diff": 0.0, "flips": []} for k in models}
    for p in all_pairs():
        enc = tok(p["premise"], p["hypothesis"], truncation="only_first", max_length=512, return_tensors="np")
        x = {"input_ids": enc["input_ids"].astype(np.int32),
             "attention_mask": enc["attention_mask"].astype(np.int32)}
        with torch.no_grad():
            ref = softmax(pt(input_ids=torch.from_numpy(x["input_ids"]).long(),
                             attention_mask=torch.from_numpy(x["attention_mask"]).long()).logits.numpy()[0])
        for k, m in models.items():
            pr = softmax(np.asarray(m.predict(x)["logits"], dtype=np.float64).reshape(-1))
            r = res[k]
            same = int(pr.argmax()) == int(ref.argmax())
            r["argmax_equal"] += same
            r["max_abs_prob_diff"] = max(r["max_abs_prob_diff"], float(np.abs(pr - ref).max()))
            if not same:
                r["flips"].append({"id": p["id"], "pytorch": [round(float(v), 4) for v in ref],
                                   k: [round(float(v), 4) for v in pr]})
    shutil.rmtree(tmp, ignore_errors=True)
    with open(os.path.join(HERE, "build", "attribution.json"), "w") as f:
        json.dump(res, f, indent=2)
    print(json.dumps(res, indent=2))


if __name__ == "__main__":
    main()
