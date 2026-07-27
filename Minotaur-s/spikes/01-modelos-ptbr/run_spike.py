# -*- coding: utf-8 -*-
"""
Executa o SPIKE 1 sobre todos os pares do dataset e reporta, por par:
  rótulo esperado | rótulo obtido | score | similaridade | acertou?

Ao final, imprime taxa de acerto global, por classe, e matriz de confusão.
"""

from collections import defaultdict

from dataset import PAIRS
from pipeline import EMBEDDING_MODEL, NLI_MODEL, analyze_pair

LABELS = ["entailment", "contradiction", "neutral"]


def main():
    print("=" * 100)
    print("SPIKE 1 — Validação de modelos em PT-BR")
    print(f"  Embeddings: {EMBEDDING_MODEL}")
    print(f"  NLI:        {NLI_MODEL}")
    print(f"  Pares:      {len(PAIRS)}")
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

        print(f"\n[{i:02d}] {'✓' if ok else '✗'}  esperado={esperado:<13} obtido={obtido:<13} "
              f"score={r['score']:.2f}  sim={r['similarity']:.2f}")
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


if __name__ == "__main__":
    main()
