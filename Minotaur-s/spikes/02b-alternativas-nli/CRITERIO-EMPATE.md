# Critério de empate — Revalidação PT-BR do MiniLMv2-L12

**Data:** 2026-07-24
**Fixado ANTES de rodar qualquer teste** (para não decidir informalmente depois
de ver os números). Este arquivo é a referência congelada; a aplicação do
critério fica no `RESULTADO.md`.

---

## Contexto

O Spike 2b deixou a escolha do NLI em aberto entre:

- **Caminho 1** — `mDeBERTa-v3-base-xnli` com XSoftmax patchado. PT-BR **já
  provado** no Spike 1 (**20/20 = 100%**). Custo: 275,9 MB INT8 + monkeypatch a
  manter no pipeline de conversão.
- **Caminho 2** — `MoritzLaurer/multilingual-MiniLMv2-L12-mnli-xnli`. Converte
  limpo, menor (113,3 MB INT8), sem patch. **PT-BR nunca validado** (português não
  está entre as línguas do XNLI).

Esta revalidação repete o **Spike 1** — **mesmo dataset, mesmos 20 pares, mesma
metodologia** (embeddings já validados + NLI, rótulo por `id2label`) — trocando
**apenas o modelo de NLI** pelo MiniLMv2-L12. É isso que torna a comparação com o
baseline válida.

## Baseline

mDeBERTa-v3-base-xnli no dataset do Spike 1: **20/20 = 100%**.

## Critério objetivo (portão de decisão)

O **portão** é a **taxa de acerto global** (nº de pares corretos entre os 20).

- **EMPATE → adotar Caminho 2 / MiniLMv2-L12.**
  Taxa do L12 **≥ 19/20** — igual ao baseline (20/20) ou no máximo **1 caso
  abaixo** (19/20).

- **CAIU → adotar Caminho 1 / mDeBERTa patchado.**
  Taxa do L12 **≤ 18/20** — **2 ou mais casos abaixo** do baseline.

### Justificativa da regra "±1 caso"

Segue a sugestão do usuário, ancorada no baseline **real de 20** (o exemplo de
15/15 na instrução era ilustrativo). Uma única divergência de rótulo é ruído
esperado ao trocar o mDeBERTa-base por um destilado menor (6→12 camadas do
MiniLMv2); duas ou mais indicam degradação sistemática — exatamente o risco que o
Spike 2b levantou para PT-BR (negação sutil, ironia, números aproximados). Um caso
de folga tolera o ruído sem tolerar a degradação.

### Observações que NÃO movem o portão

A quebra **por classe** (entailment/contradiction/neutral) e a **matriz de
confusão** são registradas como diagnóstico — úteis para entender *onde* o modelo
erra —, mas **não alteram** a decisão binária acima depois de ver os resultados. O
portão é só a taxa global. (Se o único erro cair numa classe crítica como
`contradiction`, isso será **sinalizado ao usuário como ressalva**, não usado para
reabrir o critério por conta própria.)

## Escopo

Esta tarefa aplica o critério e **recomenda**. **Não grava** a escolha na `spec.md`
(resolver o `[EM ABERTO]` §7.3 #1 é decisão do usuário), não inicia o Spike 3 nem a
implementação.
