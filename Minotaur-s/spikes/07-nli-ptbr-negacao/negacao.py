# -*- coding: utf-8 -*-
"""
SPIKE 7 — caminho (b): verificação por negação.

Ideia: rodar o par duas vezes — com a afirmação original e com a afirmação
negada como hipótese — e decidir comparando as duas distribuições. Um chunk que
"sustenta" tanto X quanto não-X não é evidência de nada.

Duas leituras do sinal, medidas separadamente (o pedido é saber QUAL recupera
mais casos, não escolher uma a priori):

  (i)  SIMETRIA(tau) — se P(entailment|X) e P(entailment|¬X) são AMBOS >= tau,
       o chunk é ruído: o rótulo vira `neutral`. Fora disso, mantém o argmax
       direto. É uma regra de VETO: só desfaz decisão, nunca cria uma.

  (ii) DIFERENCIAL(delta) — decide pela diferença:
         P(ent|¬X) - P(ent|X) >  delta -> contradiction
         P(ent|X) - P(ent|¬X) >  delta -> entailment
         caso contrário                -> neutral
       É uma regra SUBSTITUTIVA: ignora o argmax direto e decide só pelo par de
       probabilidades. Mais poderosa e mais arriscada.

Duas fontes de negação, também medidas separadamente:
  - `manual`: negação escrita à mão (dataset.NEGACOES). Mede a QUALIDADE DO
    SINAL no melhor caso possível — se não funcionar aqui, não funciona.
  - `auto`: negação produzida pelo `negador/negador.swift` (NLTagger on-device,
    a ferramenta que o app de fato teria). Mede o CUSTO REAL.

A diferença entre as duas é o custo de gerar a negação, e faz parte do
resultado — não é detalhe de implementação.

Uso:
  ../02-coreml-latencia/.venv/bin/python negacao.py --exportar-claims
  swift negador/negador.swift build/claims.json build/negacoes_auto.json
  ../02-coreml-latencia/.venv/bin/python negacao.py [short ...]
"""
import json
import os
import sys

import torch
from transformers import AutoModelForSequenceClassification, AutoTokenizer

from candidates import BASELINE, CANDIDATES, MAX_SEQ
from dataset import CLAIMS_CURTOS, NEGACOES, acertou, todos_os_pares

BUILD = os.path.join(os.path.dirname(__file__), "build")
os.makedirs(BUILD, exist_ok=True)

TAUS = [0.50, 0.60, 0.70, 0.80, 0.90]
DELTAS = [0.00, 0.05, 0.10, 0.20, 0.30, 0.50]


# --------------------------------------------------------------------------
# Claims -> negador Swift
# --------------------------------------------------------------------------

def claims_unicos():
    vistos, saida = set(), []
    for _p, hipotese, _e, _f, _g in todos_os_pares():
        if hipotese not in vistos:
            vistos.add(hipotese)
            saida.append(hipotese)
    for caso in CLAIMS_CURTOS:
        for variante in caso["variantes"]:
            if variante not in vistos:
                vistos.add(variante)
                saida.append(variante)
    return saida


def exportar_claims():
    caminho = os.path.join(BUILD, "claims.json")
    claims = claims_unicos()
    with open(caminho, "w") as f:
        json.dump(claims, f, ensure_ascii=False, indent=2)
    print(f"{len(claims)} claims -> {caminho}")
    print("agora rode:  swift negador/negador.swift build/claims.json build/negacoes_auto.json")


def carregar_negacoes_auto():
    caminho = os.path.join(BUILD, "negacoes_auto.json")
    if not os.path.exists(caminho):
        return {}
    with open(caminho) as f:
        registros = json.load(f)
    return {r["claim"]: r for r in registros}


# --------------------------------------------------------------------------
# Regras de decisão
# --------------------------------------------------------------------------

def regra_simetria(direto, negado, tau):
    """Veto: chunk que sustenta X e ¬X ao mesmo tempo vira neutro."""
    if direto["entailment"] >= tau and negado["entailment"] >= tau:
        return "neutral"
    return max(direto, key=direto.get)


def regra_diferencial(direto, negado, delta):
    """Decide pela diferença entre P(entailment|X) e P(entailment|¬X)."""
    diferenca = direto["entailment"] - negado["entailment"]
    if diferenca > delta:
        return "entailment"
    if -diferenca > delta:
        return "contradiction"
    return "neutral"


# --------------------------------------------------------------------------
# Medição
# --------------------------------------------------------------------------

def prever(tok, model, ordem, premissa, hipotese):
    enc = tok(premissa, hipotese, return_tensors="pt", truncation=True, max_length=MAX_SEQ)
    with torch.no_grad():
        probs = torch.softmax(model(**enc).logits[0], dim=-1)
    return {ordem[i]: float(probs[i]) for i in range(len(ordem))}


def avaliar(spec, negacoes_auto):
    short, ordem = spec["short"], spec["label_order"]
    print(f"\n===== [{short}] {spec['id']}")
    tok = AutoTokenizer.from_pretrained(spec["id"])
    model = AutoModelForSequenceClassification.from_pretrained(spec["id"]).eval()

    fontes = {"manual": {}, "auto": {}}
    linhas = []
    pulados = {"manual": 0, "auto": 0}

    for premissa, hipotese, esperado, fonte, grupo in todos_os_pares():
        direto = prever(tok, model, ordem, premissa, hipotese)
        base = max(direto, key=direto.get)

        registro = {"grupo": grupo, "fonte": fonte, "hipotese": hipotese,
                    "esperado": esperado, "base": base,
                    "probs_direto": {k: round(v, 4) for k, v in direto.items()}}

        for nome_fonte in ("manual", "auto"):
            if nome_fonte == "manual":
                negacao = NEGACOES.get(hipotese)
            else:
                negacao = (negacoes_auto.get(hipotese) or {}).get("negacao")

            if not negacao:
                pulados[nome_fonte] += 1
                continue

            negado = prever(tok, model, ordem, premissa, negacao)
            registro[f"negacao_{nome_fonte}"] = negacao
            registro[f"probs_negado_{nome_fonte}"] = {k: round(v, 4) for k, v in negado.items()}

            alvo = fontes[nome_fonte].setdefault(
                "pares", {"base": 0, "total": 0, "simetria": {}, "diferencial": {}})
            alvo["total"] += 1
            alvo["base"] += acertou(base, esperado)
            for tau in TAUS:
                chave = f"{tau:.2f}"
                alvo["simetria"][chave] = alvo["simetria"].get(chave, 0) + \
                    acertou(regra_simetria(direto, negado, tau), esperado)
            for delta in DELTAS:
                chave = f"{delta:.2f}"
                alvo["diferencial"][chave] = alvo["diferencial"].get(chave, 0) + \
                    acertou(regra_diferencial(direto, negado, delta), esperado)

        linhas.append(registro)
        e_x = direto["entailment"]
        e_n_m = registro.get("probs_negado_manual", {}).get("entailment")
        print(f"  [{grupo}] esp={esperado:22.22} base={base:14.14} "
              f"P(ent|X)={e_x:.3f} P(ent|¬X)={e_n_m if e_n_m is None else format(e_n_m, '.3f')}"
              f" | {hipotese[:34]}")

    resultado = {"short": short, "id": spec["id"], "linhas": linhas, "pulados": pulados}
    for nome_fonte, dados in fontes.items():
        if not dados:
            continue
        pares = dados["pares"]
        resultado[nome_fonte] = pares
        print(f"  --- negação {nome_fonte}: {pares['total']} pares "
              f"(base {pares['base']}/{pares['total']})")
        print("      simetria    " + "  ".join(
            f"tau={k}:{v}/{pares['total']}" for k, v in pares["simetria"].items()))
        print("      diferencial " + "  ".join(
            f"d={k}:{v}/{pares['total']}" for k, v in pares["diferencial"].items()))

    return resultado


def main():
    if "--exportar-claims" in sys.argv:
        exportar_claims()
        return

    negacoes_auto = carregar_negacoes_auto()
    if not negacoes_auto:
        print("AVISO: build/negacoes_auto.json ausente — só a negação manual será medida.")

    only = {a for a in sys.argv[1:] if not a.startswith("-")}
    specs = [BASELINE] + CANDIDATES
    if only:
        specs = [s for s in specs if s["short"] in only]

    resultados = []
    for spec in specs:
        try:
            resultados.append(avaliar(spec, negacoes_auto))
        except Exception as e:  # noqa: BLE001
            print(f"  FALHA [{spec['short']}]: {type(e).__name__}: {e}")
            resultados.append({"short": spec["short"], "erro": f"{type(e).__name__}: {e}"})

    caminho = os.path.join(BUILD, "negacao.json")
    with open(caminho, "w") as f:
        json.dump(resultados, f, ensure_ascii=False, indent=2)
    print(f"\n-> {caminho}")


if __name__ == "__main__":
    main()
