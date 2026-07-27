# -*- coding: utf-8 -*-
"""
Validação do modelo de embeddings CONVERTIDO (Core ML).

Roda o .mlpackage via coremltools no desktop e compara a saída com o PyTorch
original sobre um chunk real em PT-BR. Objetivo: confirmar que a conversão
preserva o resultado (similaridade de cosseno ~1.0 entre os dois vetores).

ATENÇÃO: o tempo medido aqui é no DESKTOP (Mac, via coremltools), NÃO é
latência de dispositivo. Serve só como sanity check de que o modelo roda;
os alvos NF-01/NF-02 exigem medição em iPhone (ver xcode-bench/).
"""
import os
import time

import numpy as np
import torch
from transformers import AutoModel, AutoTokenizer

import coremltools as ct

from common import EMBEDDING_MODEL

BUILD = os.path.join(os.path.dirname(__file__), "build")

CHUNK = (
    "Os Estados Unidos anunciaram nesta quinta-feira a aplicação de uma nova "
    "sobretaxa de 12,5% sobre produtos brasileiros. A medida entra em vigor na "
    "madrugada desta sexta-feira e se soma a tarifas anteriores, podendo elevar "
    "a tributação de parte das exportações do Brasil a até 37,5%."
)


def torch_embedding(ids, mask):
    backbone = AutoModel.from_pretrained(EMBEDDING_MODEL).eval()
    with torch.no_grad():
        out = backbone(input_ids=torch.tensor(ids), attention_mask=torch.tensor(mask),
                       return_dict=False)[0]
        m = torch.tensor(mask).unsqueeze(-1).float()
        mean = (out * m).sum(1) / m.sum(1).clamp(min=1e-9)
        return torch.nn.functional.normalize(mean, p=2, dim=1).numpy()[0]


def main():
    tok = AutoTokenizer.from_pretrained(EMBEDDING_MODEL)
    enc = tok(CHUNK, return_tensors="np", truncation=True, max_length=256)
    ids = enc["input_ids"].astype(np.int32)
    mask = enc["attention_mask"].astype(np.int32)
    print(f"chunk tokenizado: {ids.shape[1]} tokens")

    for variant in ("Embeddings_fp16", "Embeddings_int8"):
        path = os.path.join(BUILD, f"{variant}.mlpackage")
        if not os.path.exists(path):
            print(f"[{variant}] ausente, pulando")
            continue
        model = ct.models.MLModel(path)
        feed = {"input_ids": ids, "attention_mask": mask}
        # warmup + timing (DESKTOP)
        try:
            out = model.predict(feed)
        except Exception as e:
            print(f"[{variant}] ERRO ao rodar no desktop: {type(e).__name__}: {e}")
            continue
        key = list(out.keys())[0]
        cm_vec = np.asarray(out[key]).reshape(-1)

        t0 = time.time()
        for _ in range(20):
            model.predict(feed)
        dt = (time.time() - t0) / 20 * 1000

        ref = torch_embedding(ids, mask)
        cos = float(np.dot(cm_vec, ref) / (np.linalg.norm(cm_vec) * np.linalg.norm(ref)))
        print(f"[{variant}] roda OK | cos(CoreML, PyTorch) = {cos:.4f} | "
              f"~{dt:.1f} ms/inferência (DESKTOP, não-device)")


if __name__ == "__main__":
    main()
