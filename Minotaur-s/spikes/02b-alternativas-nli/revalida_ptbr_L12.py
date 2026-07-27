# -*- coding: utf-8 -*-
"""
SPIKE 2b — Revalidação PT-BR do MiniLMv2-L12 (repetição do Spike 1).

Objetivo: repetir o Spike 1 trocando SÓ o modelo de NLI, para decidir entre
  - Caminho 1: mDeBERTa patchado (PT-BR já provado, 20/20)
  - Caminho 2: MoritzLaurer/multilingual-MiniLMv2-L12-mnli-xnli (menor, sem patch)

Metodologia IDÊNTICA ao Spike 1 e comparação VÁLIDA:
  - REUSA os mesmos 20 pares (importa `PAIRS` de spikes/01-modelos-ptbr/dataset.py;
    NÃO copia, NÃO cria dataset novo).
  - REUSA o mesmo pipeline (importa spikes/01-modelos-ptbr/pipeline.py) e faz
    override APENAS de `pipeline.NLI_MODEL`. Os embeddings continuam idênticos ao
    Spike 1; `nli()` lê a ordem de rótulos de `config.id2label` (não hardcoded),
    então a ordem do L12 (0:entailment, 1:neutral, 2:contradiction) é tratada certa.
  - REPRODUZ o mesmo relatório de `run_spike.py`: por par -> esperado | obtido |
    score | similaridade | acertou; e ao final taxa global, por classe e matriz de
    confusão.

Não modifica nenhum arquivo do Spike 1 (só importa e sobrescreve um global em
runtime). Roda offline (modelos já no cache HF). Código descartável, fora do app.

Uso:
    HF_HUB_OFFLINE=1 /opt/anaconda3/bin/python revalida_ptbr_L12.py
"""

import os
import sys
from collections import defaultdict

# Rodar offline: os 3 modelos já estão no cache HF (sem download).
os.environ.setdefault("HF_HUB_OFFLINE", "1")
os.environ.setdefault("TRANSFORMERS_OFFLINE", "1")
os.environ.setdefault("TOKENIZERS_PARALLELISM", "false")

# --- Reuso do Spike 1: importa dataset e pipeline sem copiá-los -----------------
SPIKE1_DIR = os.path.abspath(
    os.path.join(os.path.dirname(__file__), "..", "01-modelos-ptbr")
)
sys.path.insert(0, SPIKE1_DIR)

import pipeline  # noqa: E402  (spikes/01-modelos-ptbr/pipeline.py)
from dataset import PAIRS  # noqa: E402  (spikes/01-modelos-ptbr/dataset.py)

# --- ÚNICA mudança vs. Spike 1: o modelo de NLI --------------------------------
# `_load()` do pipeline é lazy e lê este global no momento da chamada; sobrescrever
# ANTES do primeiro analyze_pair garante que o L12 seja o NLI usado.
NEW_NLI_MODEL = "MoritzLaurer/multilingual-MiniLMv2-L12-mnli-xnli"
pipeline.NLI_MODEL = NEW_NLI_MODEL

from pipeline import analyze_pair  # noqa: E402  (importado após o override)

LABELS = ["entailment", "contradiction", "neutral"]


def main():
    print("=" * 100)
    print("SPIKE 2b — Revalidação PT-BR do MiniLMv2-L12 (Spike 1 repetido)")
    print(f"  Embeddings: {pipeline.EMBEDDING_MODEL}  (já validado no Spike 1)")
    print(f"  NLI:        {pipeline.NLI_MODEL}  (candidato do Caminho 2)")
    print(f"  Dataset:    reusado de {SPIKE1_DIR}/dataset.py")
    print(f"  Pares:      {len(PAIRS)}")
    print(f"  Baseline:   mDeBERTa 20/20 = 100%  ->  empate se >= 19/20; caiu se <= 18/20")
    print("=" * 100)

    acertos = 0
    por_classe = defaultdict(lambda: {"total": 0, "acertos": 0})
    confusao = defaultdict(lambda: defaultdict(int))  # esperado -> obtido -> n
    linhas = []

    for i, p in enumerate(PAIRS, 1):
        r = analyze_pair(p["chunk"], p["afirmacao"])
        esperado, obtido = p["esperado"], r["label"]
        ok = esperado == obtido
        acertos += ok
        por_classe[esperado]["total"] += 1
        por_classe[esperado]["acertos"] += ok
        confusao[esperado][obtido] += 1

        print(f"\n[{i:02d}] {'OK ' if ok else 'ERR'}  esperado={esperado:<13} "
              f"obtido={obtido:<13} score={r['score']:.2f}  sim={r['similarity']:.2f}")
        print(f"     afirmação: {p['afirmacao']}")
        print(f"     dist: " + "  ".join(f"{k}={v:.2f}" for k, v in r["dist"].items()))
        linhas.append((i, esperado, obtido, r["score"], r["similarity"], ok))

    total = len(PAIRS)
    print("\n" + "=" * 100)
    print(f"TAXA DE ACERTO GLOBAL: {acertos}/{total} = {acertos/total:.1%}")
    print("\nPor classe:")
    for c in LABELS:
        d = por_classe[c]
        if d["total"]:
            print(f"  {c:<13} {d['acertos']}/{d['total']} = {d['acertos']/d['total']:.0%}")

    print("\nMatriz de confusão (linha = esperado, coluna = obtido):")
    header = "  " + " " * 15 + "".join(f"{c[:12]:>14}" for c in LABELS)
    print(header)
    for c in LABELS:
        row = f"  {c:<15}" + "".join(f"{confusao[c][o]:>14}" for o in LABELS)
        print(row)
    print("=" * 100)

    # --- Aplicação do critério de empate (CRITERIO-EMPATE.md, fixado antes) ------
    empate = acertos >= 19
    print("\nCRITÉRIO (fixado em CRITERIO-EMPATE.md, antes de rodar):")
    print(f"  baseline mDeBERTa = 20/20 | portão: empate >= 19/20, caiu <= 18/20")
    print(f"  MiniLMv2-L12 = {acertos}/20  ->  "
          + ("EMPATOU -> Caminho 2 / L12" if empate else "CAIU -> Caminho 1 / mDeBERTa patchado"))
    print("=" * 100)

    # Linhas em formato pronto para a tabela do RESULTADO.md
    print("\n[markdown] linhas por par (i | esperado | obtido | score | sim | ok):")
    for (i, esperado, obtido, score, sim, ok) in linhas:
        print(f"| {i} | {esperado} | {obtido} | {score:.2f} | {sim:.2f} | {'✓' if ok else '✗'} |")


if __name__ == "__main__":
    main()
