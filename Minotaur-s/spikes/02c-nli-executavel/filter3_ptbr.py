# -*- coding: utf-8 -*-
"""
SPIKE 2c — FILTRO 3 (qualidade PT-BR) dos candidatos que sobreviveram ao Filtro 2.

Repete o Spike 1 — MESMO dataset (20 pares), MESMO pipeline — trocando só o modelo
de NLI, para cada sobrevivente. Reusa, sem copiar:
  - spikes/01-modelos-ptbr/dataset.py  (PAIRS)
  - spikes/01-modelos-ptbr/pipeline.py (analyze_pair; nli() lê id2label, não hardcode)

Baseline de referência: mDeBERTa 20/20 (Spike 1). O L12 já foi medido no Spike 2b
(17/20); aqui reconfirmo e adiciono L6 e symanto para comparação direta.

Roda offline (modelos já no cache HF). Inferência PyTorch no desktop — mesma
natureza do Spike 1; a conversão Core ML preserva a saída (Filtro 1: cos desktop
= 1,0), então a acurácia PyTorch transfere para o .mlpackage.

Uso (anaconda base tem sentence-transformers, como no Spike 2b):
    /opt/anaconda3/bin/python filter3_ptbr.py
"""
import os
import sys
from collections import defaultdict

os.environ.setdefault("HF_HUB_OFFLINE", "1")
os.environ.setdefault("TRANSFORMERS_OFFLINE", "1")
os.environ.setdefault("TOKENIZERS_PARALLELISM", "false")

SPIKE1_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "01-modelos-ptbr"))
sys.path.insert(0, SPIKE1_DIR)

import pipeline  # noqa: E402
from dataset import PAIRS  # noqa: E402

LABELS = ["entailment", "contradiction", "neutral"]

# Só os sobreviventes do Filtro 2 (execução correta em device/simulador).
SURVIVORS = [
    ("L6", "MoritzLaurer/multilingual-MiniLMv2-L6-mnli-xnli"),
    ("L12", "MoritzLaurer/multilingual-MiniLMv2-L12-mnli-xnli"),
    ("symanto", "symanto/xlm-roberta-base-snli-mnli-anli-xnli"),
]


def eval_model(short, model_id):
    # Reset do NLI lazy do pipeline p/ recarregar o novo modelo (embeddings ficam).
    pipeline.NLI_MODEL = model_id
    pipeline._nli_model = None
    pipeline._nli_tokenizer = None

    acertos = 0
    por_classe = defaultdict(lambda: {"total": 0, "acertos": 0})
    confusao = defaultdict(lambda: defaultdict(int))
    linhas = []
    for i, p in enumerate(PAIRS, 1):
        r = pipeline.analyze_pair(p["chunk"], p["afirmacao"])
        esperado, obtido = p["esperado"], r["label"]
        ok = esperado == obtido
        acertos += ok
        por_classe[esperado]["total"] += 1
        por_classe[esperado]["acertos"] += ok
        confusao[esperado][obtido] += 1
        linhas.append((i, esperado, obtido, r["score"], r["similarity"], ok))
    return acertos, por_classe, confusao, linhas


def main():
    total = len(PAIRS)
    summary = []
    for short, model_id in SURVIVORS:
        print("\n" + "=" * 90)
        print(f"FILTRO 3 — {short}  ({model_id})")
        print(f"  id2label ordem lida de config; baseline mDeBERTa = 20/20")
        print("=" * 90)
        acertos, por_classe, confusao, linhas = eval_model(short, model_id)

        print(f"\nTAXA GLOBAL: {acertos}/{total} = {acertos/total:.1%}")
        for c in LABELS:
            d = por_classe[c]
            if d["total"]:
                print(f"  {c:<13} {d['acertos']}/{d['total']} = {d['acertos']/d['total']:.0%}")
        print("\nMatriz de confusão (linha=esperado, coluna=obtido):")
        print("  " + " " * 15 + "".join(f"{c[:12]:>14}" for c in LABELS))
        for c in LABELS:
            print(f"  {c:<15}" + "".join(f"{confusao[c][o]:>14}" for o in LABELS))
        print("\n[markdown] por par (i | esperado | obtido | score | sim | ok):")
        for (i, esp, obt, score, sim, ok) in linhas:
            print(f"| {i} | {esp} | {obt} | {score:.2f} | {sim:.2f} | {'✓' if ok else '✗'} |")
        summary.append((short, acertos, total,
                        {c: (por_classe[c]['acertos'], por_classe[c]['total']) for c in LABELS}))

    print("\n\n" + "#" * 90)
    print("RESUMO FILTRO 3 (baseline mDeBERTa = 20/20 = 100%)")
    print("#" * 90)
    for short, acertos, total, byc in summary:
        cls = " ".join(f"{c[:3]}={a}/{t}" for c, (a, t) in byc.items())
        print(f"  {short:8s} {acertos}/{total} = {acertos/total:.0%}   [{cls}]")


if __name__ == "__main__":
    main()
