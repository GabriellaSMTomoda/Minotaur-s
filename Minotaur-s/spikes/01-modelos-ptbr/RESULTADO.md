# SPIKE 1 — Resultado: Modelos de Embeddings + NLI em PT-BR

**Data:** 2026-07-24
**Objetivo:** validar, em Python no desktop, se o par de modelos
embeddings + NLI tem desempenho aceitável em português brasileiro — o maior
risco técnico da spec (§7.1, §7.3 item 1 `[EM ABERTO]`). Etapa exigida por
§7.4 antes de qualquer código Swift.

Este é código de validação descartável, isolado do projeto iOS. Nada aqui foi
integrado ao app e nenhum item `[EM ABERTO]` foi resolvido.

---

## Modelos testados

| Papel | Modelo | Tamanho aprox. |
|---|---|---|
| Embeddings | `sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2` | ~120 MB |
| NLI | `MoritzLaurer/mDeBERTa-v3-base-xnli-multilingual-nli-2mil7` | ~560 MB |

Testado **um único** modelo NLI (decisão do usuário). A ordem de rótulos foi
lida de `model.config.id2label`, não hardcoded.

## Pipeline avaliado

Reproduz a direção da spec (RF-06/RF-07):
`embedding(chunk) + embedding(afirmação)` → similaridade de cosseno →
`NLI(premissa = chunk, hipótese = afirmação)` → distribuição
entailment / contradiction / neutral → rótulo de maior probabilidade + score.

## Dataset

**20 pares** (mínimo exigido: 15), com trechos **reais** copiados verbatim de
3 reportagens da Agência Brasil / EBC (tarifa dos EUA, subsídio da gasolina,
acidente da Voepass). Afirmações escritas à mão, casos deliberadamente claros:
- entailment: 8 pares
- contradiction: 7 pares
- neutral: 5 pares

Arquivo: [`dataset.py`](./dataset.py). Fontes citadas por par no próprio arquivo.

---

## Resultados

**Taxa de acerto global: 20/20 = 100%**

| Classe | Acerto |
|---|---|
| entailment | 8/8 = 100% |
| contradiction | 7/7 = 100% |
| neutral | 5/5 = 100% |

**Matriz de confusão** (linha = esperado, coluna = obtido):

|  | entailment | contradiction | neutral |
|---|---|---|---|
| **entailment** | 8 | 0 | 0 |
| **contradiction** | 0 | 7 | 0 |
| **neutral** | 0 | 0 | 5 |

**Confiança do NLI:** alta e bem separada — scores do rótulo vencedor entre
0,98 e 1,00 em todos os pares; classe errada quase sempre com probabilidade
~0,00.

**Similaridade de cosseno (embeddings):** separou os casos como esperado —
pares neutros/sem relação ficaram baixos (0,09–0,58) enquanto
entailment/contradiction ficaram mais altos. Sinal de que o filtro por
similaridade (RF-06.6) é discriminativo em PT-BR. **Observação:** o par neutro
"maior exportador de café" teve sim=0,58 (mesmo tema econômico), lembrando que
o limiar de similaridade precisará de calibração — mas isso é RF-06.7
`[EM ABERTO]` e **não** foi decidido aqui.

Nenhum modelo se destacou sobre outro porque apenas um NLI foi testado.

Log completo por par: reproduzível via `python3 run_spike.py`.

---

## Critério de decisão (definido antes de rodar)

- **≥ 80% global** (e nenhuma classe com 0 acertos) → viável.
- 60–79% → marginal, decisão devolvida ao usuário.
- < 60% → não viável.

Resultado (100%) fica muito acima do limiar. Nenhum ajuste de prompt/parâmetro
foi feito — não foi necessário.

## Recomendação

> **VIÁVEL PARA PROSSEGUIR.**

O par de modelos multilíngues classifica corretamente e com alta confiança os
três casos em PT-BR, sobre trechos reais de imprensa brasileira. O risco
"modelos com desempenho ruim em português" (§7.1) está **substancialmente
reduzido** para este par de modelos.

## Ressalvas (o que este spike NÃO prova)

- Dataset pequeno (20) e com casos **claros, escritos à mão**. Não cobre
  ambiguidade, ironia/sátira, negação sutil, números aproximados, nem chunks
  longos (>512 tokens). Casos reais do app serão mais ruidosos.
- Rodou em **desktop com PyTorch**, não em Core ML no iPhone. Latência,
  conversão para `.mlpackage` e tamanho pós-quantização são o **SPIKE 2** —
  ainda em aberto (RD-01, NF-01/NF-02/NF-05).
- Limiares continuam `[EM ABERTO]`: similaridade mínima (RF-06.7) e confiança
  mínima do NLI (RF-07.5). Aqui só foram observados, não calibrados.
- Testado só o mDeBERTa-base. Um modelo NLI **menor** (mais realista para
  on-device) não foi comparado nesta rodada.

## Próximo passo sugerido

Avançar para o **SPIKE 2** (conversão Core ML + latência real no dispositivo) —
somente após confirmação do usuário. Não executado nesta tarefa.
