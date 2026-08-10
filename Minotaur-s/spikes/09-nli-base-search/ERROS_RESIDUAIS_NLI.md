# Investigação — erros residuais do NLI

Data: 2026-08-10

## Decisão

Não há correção geral sustentada por estes dados. Os erros permanecem como regressão conhecida;
nenhum limiar, regra de votação ou contrato de DT-25/DT-26/DT-29 foi alterado.

O diagnóstico reproduzível está em `investigate_residuals.py`; a saída integral, incluindo
logits, probabilidades, margens, IDs WordPiece, tokens, `token_type_ids`, similaridades e chunks
selecionados, fica em `build/residual_investigation.json`.

## Reprodução

Os dois pares residuais foram reproduzidos sem mudança de texto:

| Fonte/premissa | Esperado | Previsto | P(ent) | P(neu) | P(con) | margem top-2 |
|---|---|---|---:|---:|---:|---:|
| Metrópoles — “forma inovadora de tratar” | neutral | entailment | 0,866445 | 0,044731 | 0,088824 | 0,777621 |
| G1/Fantástico — “médico … diz curar” | neutral | entailment | 0,892064 | 0,075320 | 0,032617 | 0,816744 |

Não são erros de baixa confiança. Uma margem global entre classes pequena não os resolveria.
No primeiro par, `tratar` vira entailment correto quando a hipótese também diz tratamento
(0,989708), mas a troca por `cura` continua entailment forte. No segundo, preservar “diz curar”
dá entailment correto (0,986408), porém remover a atribuição mantém entailment errado; até
“comprovou a cura” fica entailment por 0,588847 contra neutral 0,392941. O modelo perde modalidade,
atribuição e generalização exatamente onde o overlap lexical é alto.

A tokenização está íntegra: o par usa `[CLS] premissa [SEP] hipótese [SEP]`, segmentos 0/1 e
comprimentos 25 e 32. `cura` aparece como token inteiro; `curar` aparece como `cura ##r`.
Logo, não há evidência de inversão de label, truncamento ou perda do sufixo na entrada.

## Instabilidade de claims curtos

Na família Terra plana, pequenas redações atravessam três classes:

| Claim | Previsto | P(ent) | P(neu) | P(con) | margem top-2 |
|---|---|---:|---:|---:|---:|
| `A Terra é plana.` | contradiction | 0,328418 | 0,209359 | 0,462223 | 0,133805 |
| `A Terra é plana` | contradiction | 0,160816 | 0,357456 | 0,481728 | 0,124272 |
| `Terra plana` | entailment | 0,451336 | 0,424574 | 0,124089 | 0,026762 |
| `A Terra é plana e a NASA esconde isso das pessoas.` | neutral | 0,012181 | 0,666252 | 0,321567 | 0,344686 |
| `Cientistas confirmaram que a Terra é plana.` | contradiction | 0,011282 | 0,018802 | 0,969916 | 0,951113 |

O sintagma sem verbo é realmente ambíguo para o classificador (margem 0,026762), mas a variante
NASA não é um simples caso de margem: a premissa contradiz a primeira conjunção e não cobre a
segunda, de modo que neutral é uma leitura NLI plausível do claim composto. Isso mostra que uma
margem ad hoc trataria fenômenos semanticamente diferentes como se fossem o mesmo problema.

## Chunks, similaridade e agregação

Uma sonda de artigo com cinco chunks sobre o mesmo tema selecionou, sem mudar 0,25/top-3:

| Chunk resumido | Similaridade | NLI |
|---|---:|---|
| manchete “forma inovadora de tratar” | 0,718078 | entailment 0,955673 |
| “técnica experimental … não uma cura geral” | 0,470139 | contradiction 0,924057 |
| “remissão … não permite concluir cura para todos” | 0,422897 | contradiction 0,973509 |

Os três passam ao NLI. Pela DT-29, o maior score decisivo é contradiction 0,973509, superando o
entailment da manchete. Portanto, chunk de corpo de boa qualidade corrige o erro no nível do
artigo; o risco residual aparece quando busca/extração entrega apenas a manchete ou omite a
ressalva. Filtrar toda manchete proposicional seria regressivo: títulos também podem ser a única
evidência válida e o conjunto atual não mede recall suficiente para justificar essa regra.

## Pequena ampliação adversarial

Foram adicionadas quatro sondas justificadas, sem usá-las para ajustar o modelo:

- tratamento explicitamente distinto de cura → contradiction 0,874949;
- fala atribuída sem estudos de eficácia → contradiction 0,976544;
- remissão de um paciente → neutral 0,983816;
- hipótese que preserva fala e quantificador → entailment 0,991824.

As duas primeiras derivam diretamente das matérias do Metrópoles e do Fantástico; a página do
Fantástico registra que o médico “diz curar” e não apresentou estudos de eficácia. As demais
isolam remissão, quantificador e atribuição, os fenômenos já documentados no Spike 9.

## Próximo experimento recomendado

Montar um conjunto cego, por artigo completo, com pelo menos 30 casos reais e anotações separadas
para (a) headline/snippet, (b) corpo extraído, (c) top-3 do embedding e (d) rótulo agregado.
Estratificar por fala atribuída, modalidade (`pode`, `diz`), tratamento/remissão/cura e claims
compostos. Comparar o pipeline atual com uma alternativa de reranking de chunks que valorize
ressalvas/negações, sem trocar thresholds. Só reabrir DT-25 ou DT-29 se esse conjunto mostrar
ganho geral e zero regressão nos seis casos críticos.
