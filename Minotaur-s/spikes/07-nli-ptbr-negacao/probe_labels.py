# -*- coding: utf-8 -*-
"""
SPIKE 7 — Confirma empiricamente a ordem índice->rótulo de cada candidato.

Roda ANTES de qualquer medição de qualidade e é bloqueante. Dois dos três
candidatos trazem `id2label` genérico ({0:0, 1:1, 2:2} ou LABEL_0/1/2), então a
ordem vem do model card — e model card é documentação, não evidência. Trocar
`entailment` por `contradiction` inverteria todo o veredito sem produzir erro
visível em lugar nenhum; foi a primeira hipótese que a investigação pós-Fase 5
teve de refutar no modelo atual.

Sondas: pares em que a resposta é inequívoca em qualquer modelo de NLI que
funcione. Se a ordem declarada estiver certa, os quatro batem. Se não baterem, o
candidato sai do spike com "ordem de rótulos indeterminada" — não se chuta.

Uso:
  ../02-coreml-latencia/.venv/bin/python probe_labels.py
"""
import json
import os

import torch
from transformers import AutoModelForSequenceClassification, AutoTokenizer

from candidates import BASELINE, CANDIDATES

BUILD = os.path.join(os.path.dirname(__file__), "build")
os.makedirs(BUILD, exist_ok=True)

# (premissa, hipótese, rótulo esperado). Casos de laboratório de propósito: aqui
# não se mede qualidade, se identifica qual saída é qual.
SONDAS = [
    ("A Terra é plana.", "A Terra é plana.", "entailment"),
    ("A Terra é plana.", "A Terra não é plana.", "contradiction"),
    ("A Terra não é plana, e sim aproximadamente esférica.", "A Terra é plana.", "contradiction"),
    ("O gato dormiu no sofá.", "A inflação subiu no trimestre.", "neutral"),
]


def probe(spec: dict) -> dict:
    short, model_id = spec["short"], spec["id"]
    ordem = spec["label_order"]
    print(f"\n===== [{short}] {model_id}")
    print(f"  ordem declarada: {ordem}  (fonte: {spec['label_source']})")

    tok = AutoTokenizer.from_pretrained(model_id)
    model = AutoModelForSequenceClassification.from_pretrained(model_id).eval()

    n = int(model.config.num_labels)
    if n != len(ordem):
        msg = f"num_labels={n} != len(label_order)={len(ordem)}"
        print(f"  REPROVADO: {msg}")
        return {"short": short, "id": model_id, "ok": False, "erro": msg}

    acertos, detalhes = 0, []
    for premissa, hipotese, esperado in SONDAS:
        enc = tok(premissa, hipotese, return_tensors="pt", truncation=True, max_length=512)
        with torch.no_grad():
            probs = torch.softmax(model(**enc).logits[0], dim=-1)
        obtido = ordem[int(probs.argmax())]
        ok = obtido == esperado
        acertos += ok
        nomeados = {ordem[i]: round(float(probs[i]), 4) for i in range(n)}
        detalhes.append({"premissa": premissa, "hipotese": hipotese,
                         "esperado": esperado, "obtido": obtido, "probs": nomeados})
        print(f"  {'OK  ' if ok else 'ERRO'} esperado={esperado:14s} obtido={obtido:14s} {nomeados}")

    ok = acertos == len(SONDAS)
    print(f"  --> {acertos}/{len(SONDAS)} — ordem {'CONFIRMADA' if ok else 'NÃO confirmada'}")
    return {"short": short, "id": model_id, "ok": ok, "acertos": acertos,
            "ordem": ordem, "detalhes": detalhes}


def main():
    resultados = [probe(s) for s in [BASELINE] + CANDIDATES]
    caminho = os.path.join(BUILD, "probe_labels.json")
    with open(caminho, "w") as f:
        json.dump(resultados, f, ensure_ascii=False, indent=2)

    print("\n================ RESUMO ================")
    for r in resultados:
        estado = "CONFIRMADA" if r.get("ok") else "NÃO CONFIRMADA"
        print(f"  {r['short']:16s} {estado:16s} {r.get('acertos', '-')}/{len(SONDAS)}"
              f"  {r.get('erro', '')}")
    print(f"\n-> {caminho}")


if __name__ == "__main__":
    main()
