# -*- coding: utf-8 -*-
"""
SPIKE 7 — FILTRO 3: qualidade PT-BR nos pares reais.

Roda DEPOIS do gate de execução (FILTRO 2). Medir qualidade de um modelo que não
executa em device é o erro que custou o mDeBERTa; aqui a ordem é a corrigida no
Spike 2c.

Mede, para o baseline e para cada candidato:
  - grupos A+B: acertos nos pares adversariais reais (a tabela do relatório);
  - grupo C: estabilidade do rótulo entre redações do MESMO claim (item 25).

Roda em PyTorch fp32, no desktop. A paridade Core ML INT8 x PyTorch é assunto do
FILTRO 2 — separar as duas coisas é o que permite dizer "o modelo julga mal" em
vez de "alguma coisa no caminho está errada".

Uso:
  ../02-coreml-latencia/.venv/bin/python qualidade_ptbr.py [short ...]
"""
import json
import os
import sys

import torch
from transformers import AutoModelForSequenceClassification, AutoTokenizer

from candidates import BASELINE, CANDIDATES, MAX_SEQ
from dataset import CLAIMS_CURTOS, acertou, todos_os_pares

BUILD = os.path.join(os.path.dirname(__file__), "build")


def carregar(spec):
    tok = AutoTokenizer.from_pretrained(spec["id"])
    model = AutoModelForSequenceClassification.from_pretrained(spec["id"]).eval()
    return tok, model


def prever(tok, model, ordem, premissa, hipotese):
    enc = tok(premissa, hipotese, return_tensors="pt", truncation=True, max_length=MAX_SEQ)
    with torch.no_grad():
        probs = torch.softmax(model(**enc).logits[0], dim=-1)
    nomeados = {ordem[i]: float(probs[i]) for i in range(len(ordem))}
    return ordem[int(probs.argmax())], nomeados


def avaliar(spec):
    short = spec["short"]
    ordem = spec["label_order"]
    print(f"\n===== [{short}] {spec['id']}")
    print(f"      base: {spec['base']}  |  dados: {spec['data']}")
    tok, model = carregar(spec)

    # --- Grupos A + B: pares adversariais reais
    acertos, linhas = 0, []
    for premissa, hipotese, esperado, fonte, grupo in todos_os_pares():
        obtido, probs = prever(tok, model, ordem, premissa, hipotese)
        ok = acertou(obtido, esperado)
        acertos += ok
        linhas.append({"grupo": grupo, "fonte": fonte, "premissa": premissa,
                       "hipotese": hipotese, "esperado": esperado,
                       "obtido": obtido, "probs": {k: round(v, 4) for k, v in probs.items()}})
        p = " ".join(f"{k[:3]}={v:.3f}" for k, v in probs.items())
        print(f"  {'OK  ' if ok else 'ERRO'} [{grupo}] esp={esperado:22.22} "
              f"obt={obtido:14.14} {p} | {hipotese[:38]}")
    total = len(linhas)
    print(f"  --> pares reais: {acertos}/{total}")

    # --- Grupo C: estabilidade entre redações do mesmo claim
    estaveis, grupos_c = 0, []
    for caso in CLAIMS_CURTOS:
        obtidos = []
        for variante in caso["variantes"]:
            obtido, probs = prever(tok, model, ordem, caso["premissa"], variante)
            obtidos.append({"claim": variante, "obtido": obtido,
                            "probs": {k: round(v, 4) for k, v in probs.items()}})
        rotulos = [o["obtido"] for o in obtidos]
        estavel = len(set(rotulos)) == 1
        corretos = sum(acertou(r, caso["esperado"]) for r in rotulos)
        estaveis += estavel
        grupos_c.append({"grupo": caso["grupo"], "esperado": caso["esperado"],
                         "estavel": estavel, "corretos": corretos,
                         "total": len(rotulos), "variantes": obtidos})
        print(f"  [C:{caso['grupo']:14s}] estável={estavel!s:5s} "
              f"corretos={corretos}/{len(rotulos)} rótulos={rotulos}")
    print(f"  --> claims curtos: {estaveis}/{len(CLAIMS_CURTOS)} grupos estáveis")

    return {"short": short, "id": spec["id"], "base": spec["base"], "data": spec["data"],
            "acertos_pares": acertos, "total_pares": total, "linhas": linhas,
            "grupos_estaveis": estaveis, "total_grupos": len(CLAIMS_CURTOS),
            "claims_curtos": grupos_c}


def main():
    only = set(sys.argv[1:])
    specs = [BASELINE] + CANDIDATES
    if only:
        specs = [s for s in specs if s["short"] in only]

    resultados = []
    for spec in specs:
        try:
            resultados.append(avaliar(spec))
        except Exception as e:  # noqa: BLE001
            print(f"  FALHA [{spec['short']}]: {type(e).__name__}: {e}")
            resultados.append({"short": spec["short"], "id": spec["id"],
                               "erro": f"{type(e).__name__}: {e}"})

    caminho = os.path.join(BUILD, "qualidade_ptbr.json")
    with open(caminho, "w") as f:
        json.dump(resultados, f, ensure_ascii=False, indent=2)

    print("\n\n================ RESUMO FILTRO 3 ================")
    print(f"  {'modelo':16s} {'pares reais':>12s}  {'grupos estáveis':>16s}")
    for r in resultados:
        if "erro" in r:
            print(f"  {r['short']:16s} {'FALHOU':>12s}  {r['erro'][:40]}")
            continue
        print(f"  {r['short']:16s} {r['acertos_pares']:>5d}/{r['total_pares']:<6d} "
              f"{r['grupos_estaveis']:>10d}/{r['total_grupos']:<5d}")
    print(f"\n-> {caminho}")


if __name__ == "__main__":
    main()
