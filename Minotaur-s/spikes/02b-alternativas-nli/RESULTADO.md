# SPIKE 2b — Resultado: Alternativas de NLI conversíveis para Core ML

**Data:** 2026-07-24
**Objetivo:** o Spike 2 travou — o NLI validado no Spike 1
(`mDeBERTa-v3-base-xnli`) **não converte para Core ML** por causa da custom op
`XSoftmax` (vira `prim::PythonOp`). Isso reabriu o item `[EM ABERTO]` §7.3 #1 da
spec. Esta tarefa **avalia** dois caminhos e mede o que dá para medir; **não
escolhe o modelo final, não revalida acurácia em PT-BR e não avança para o Spike 3**.

> **Escopo do que foi medido:** *converte para Core ML?*, *tamanho fp16/INT8* e
> *a conversão preserva a saída?* (cos dos logits vs. PyTorch sobre um par PT-BR
> real). **NÃO** foi medida acurácia em PT-BR (isso é repetir o Spike 1) nem
> latência em device (ambiente só tem Command Line Tools, sem Xcode — mesma
> limitação registrada no Spike 2). Código descartável, isolado do app.

Toolchain: o venv **pinado** do Spike 2 (`torch 2.7.0 · transformers 4.46.3 ·
coremltools 9.0 · sentencepiece · numpy<2.3`).

---

## Veredito rápido

**Os dois caminhos são tecnicamente viáveis.** Todos os candidatos testados
converteram para Core ML, e o Caminho 1 (patchar o XSoftmax) também converteu com
saída **idêntica** à original. A decisão não é mais "o que converte?", e sim um
**trade-off entre tamanho, limpeza do pipeline e necessidade de revalidar PT-BR**
— e é sua para tomar.

| Caminho | Modelo | Converte? | INT8 | 3 classes? | PT-BR já provado? |
|---|---|---|---|---|---|
| **2** | `multilingual-MiniLMv2-L6-mnli-xnli` | ✅ | **103,0 MB** | ✅ | ❌ (revalidar) |
| **2** | `multilingual-MiniLMv2-L12-mnli-xnli` | ✅ | **113,3 MB** | ✅ | ❌ (revalidar) |
| **2** | `symanto/xlm-roberta-base-snli-mnli-anli-xnli` | ✅ | 266,4 MB | ✅ | ❌ (revalidar) |
| **2** | `bert-base-portuguese-cased-nli-assin-2` (BERTimbau) | ✅ | 104,5 MB | ❌ **2 classes** | parcial (ASSIN2) |
| **1** | `mDeBERTa-v3-base-xnli` **com XSoftmax patchado** | ✅ | 275,9 MB | ✅ | ✅ (Spike 1 = 100%) |

Embeddings (Spike 2) = **113 MB INT8**. Somando com o NLI, **todos os candidatos
cabem no alvo NF-05 (<500 MB)** — logo, tamanho sozinho não elimina ninguém; é
peso na balança, não corte.

---

## Caminho 2 — modelos amigáveis a Core ML

**Critério:** atenção padrão (softmax normal, sem custom autograd op), 3 classes
(`entailment`/`contradiction`/`neutral`) quando possível, e tamanho compatível com
NF-05. A ausência de custom op foi **verificada pela conversão de fato**, não
assumida — cada candidato foi convertido com o mesmo fluxo do Spike 2
(`trace → ct.convert(FLOAT16, iOS16, mlprogram) → linear_quantize_weights(INT8)`),
e a saída do `.mlpackage` INT8 foi comparada ao PyTorch sobre um par PT-BR real.

| Modelo | Base / atenção | Classes (id2label) | fp16 | INT8 | cos(logits) INT8 vs PyTorch |
|---|---|---|---|---|---|
| `MoritzLaurer/multilingual-MiniLMv2-L6-mnli-xnli` | XLM-R-large destilado, 6 camadas, h384 — softmax padrão | 3: entailment/neutral/contradiction | 204,2 MB | **103,0 MB** | **1,0000** |
| `MoritzLaurer/multilingual-MiniLMv2-L12-mnli-xnli` | XLM-R destilado, 12 camadas — softmax padrão | 3: entailment/neutral/contradiction | 224,6 MB | **113,3 MB** | **1,0000** |
| `symanto/xlm-roberta-base-snli-mnli-anli-xnli` | XLM-R-base — softmax padrão | 3: ENTAILMENT/NEUTRAL/CONTRADICTION | 530,6 MB | 266,4 MB | 1,0000 |
| `ricardo-filho/bert-base-portuguese-cased-nli-assin-2` | BERTimbau (BERT PT-BR base) — softmax padrão | **2: LABEL_0/LABEL_1** | 208,0 MB | 104,5 MB | 0,9997 |

**Leitura dos resultados:**

- **Os dois MiniLMv2 (L6/L12) são os destaques do Caminho 2:** convertem limpo,
  são os menores (103 / 113 MB INT8), têm as **3 classes** com rótulos semânticos
  corretos, e a quantização INT8 não mexeu na saída (cos = 1,0000). São variantes
  destiladas do XLM-R-large treinadas em MNLI+XNLI — mesma família multilíngue e
  mesma lógica de transferência PT-BR que sustentou o Spike 1.

- **`symanto` (XLM-R-base cheio):** também 3 classes e converte, mas é **~2,6x**
  maior que o L6 (266 MB) sem uma vantagem de qualidade comprovada aqui. Fica como
  opção "XLM-R base completo" caso os MiniLM se mostrem fracos na revalidação.

- **BERTimbau/ASSIN2 (PT-BR nativo) — reprovado para este pipeline:** converte,
  mas tem **apenas 2 classes** (`LABEL_0`/`LABEL_1`, sem rótulos semânticos), fruto
  do ASSIN2 RTE ser *entailment/none*. **Não produz `contradiction`**, então não
  atende RF-07.2/RF-08.1 (o veredito `CONTRADITO PELAS FONTES` ficaria impossível).
  E, ao contrário do que se esperava, **não é menor** que os MiniLM (104,5 MB) —
  é um BERT-base de 12 camadas. Ou seja, é dominado: nem 3 classes, nem menor.
  (Um modelo PT-nativo *de 3 classes* — ex. treinado em ASSIN2 + um dataset com
  contradição, ou em XNLI-pt — não foi encontrado pronto nesta rodada.)

**Referência fora de orçamento (não convertida aqui):**
`joeddav/xlm-roberta-large-xnli` — XLM-R-large, softmax padrão, 3 classes, alta
qualidade de referência. Por arquitetura converteria (mesma família do XLM-R-base
que converteu), mas ~560 MB INT8 sozinho **come quase todo o orçamento** NF-05
junto com os 113 MB dos embeddings. Citado como teto de qualidade, não como
candidato viável. Não baixado (~2 GB) para não desperdiçar rede.

**Ressalva comum aos dois MiniLM (e a qualquer modelo do Caminho 2):**
1. **PT-BR não está validado.** São modelos **diferentes** do Spike 1 (menores,
   destilados) e o português **não está entre as 15 línguas do XNLI**. A
   qualidade em PT-BR precisa ser **revalidada repetindo o Spike 1** antes de
   confiar — especialmente em negação sutil, ironia e números aproximados, onde
   um modelo de 6 camadas destilado tende a degradar mais que o mDeBERTa-base.
2. Aparece o mesmo aviso de **shape dinâmico** do Spike 2
   (`Data-dependent shapes were disabled … logits [?, 3]`, do `RangeDim` de
   sequência 1..512). O modelo **roda** (produziu a saída correta no desktop), mas
   para usar a ANE no device pode ser preciso **shape fixo ou enumerado**
   (128/256/512) — decisão do spike de implementação, não desta tarefa.

---

## Caminho 1 — patchar o `XSoftmax` do mDeBERTa

Duas verificações, ambas rodadas (`patch_deberta.py`):

### (1) Equivalência numérica do patch — **idêntica**

O `XSoftmax.apply` foi trocado por um **softmax mascarado padrão**
(`masked_fill(-inf) → softmax → masked_fill(0)`) via monkeypatch do global do
módulo `transformers…modeling_deberta_v2`, e os logits do modelo **patchado** vs.
**original** foram comparados sobre um par PT-BR real:

```
logits ORIGINAL (XSoftmax) = [ 3.6802218  -0.87476844 -2.7974386 ]
logits PATCHADO (softmax)  = [ 3.6802218  -0.87476844 -2.7974386 ]
  max|Δlogit| = 0.000e+00
  cos(logits) = 1.000000
  argmax igual = True
```

**Diferença zero (bit a bit).** Isso confirma a hipótese: o *forward* do XSoftmax
**é** um masked softmax; a `autograd.Function` customizada existe só pelo *backward*
otimizado (treino), irrelevante em inferência. **Risco numérico do patch ≈ 0.**

### (2) Conversão do modelo patchado — **converteu**

Com o XSoftmax patchado, o mDeBERTa **converteu para Core ML**:

- FLOAT16 = **549,3 MB** · INT8 = **275,9 MB**.
- **O XSoftmax era o único muro arquitetural** — os gathers da disentangled-
  attention e o resto do grafo convertem normalmente. A "próxima parede" temida
  não apareceu.
- Durante a conversão disparou o shim `bitwise_and` (reaproveitado do Spike 2).
  **Isso é uma lacuna de versão do coremltools, não arquitetura** — um tradutor
  trivial de op de máscara, já documentado e aprovado no Spike 2. Não altera o
  modelo. (Mesmo assim é uma dependência do pipeline de conversão a registrar.)

### Esforço e risco — avaliação honesta

- **A favor (forte):** o Caminho 1 mantém **exatamente** o modelo que já passou no
  Spike 1 com **100%** em PT-BR, e como a saída patchada é **idêntica**, essa
  validação de PT-BR **transfere sem re-teste**. É o único caminho onde a
  qualidade em português **já está comprovada**.
- **Contra:**
  - **Tamanho:** 275,9 MB INT8 — **~2,7x** o MiniLMv2-L6 (embora ainda caiba no
    NF-05: 113 + 276 = 389 MB).
  - **Manutenção:** o patch é um monkeypatch de interno do `transformers` que
    precisa viver no **pipeline de conversão offline** (não no app) e ser
    **re-verificado a cada upgrade** de `transformers`/`coremltools` — a estrutura
    interna do DeBERTa pode mudar de nome/forma.
  - Depende também do shim `bitwise_and` no ato da conversão (não no app).

---

## Comparativo final (para você decidir)

| Critério | Caminho 1 (mDeBERTa patchado) | Caminho 2 — MiniLMv2-L6 | Caminho 2 — MiniLMv2-L12 |
|---|---|---|---|
| Converte p/ Core ML | ✅ (com patch + shim) | ✅ limpo | ✅ limpo |
| Tamanho INT8 | 275,9 MB | **103,0 MB** | 113,3 MB |
| App total c/ embeddings (113 MB) | ~389 MB ✅ | **~216 MB** ✅ | ~226 MB ✅ |
| 3 classes (entail/contra/neutral) | ✅ | ✅ | ✅ |
| Qualidade PT-BR | ✅ **já provada** (Spike 1, idêntica) | ❌ **revalidar** | ❌ **revalidar** |
| Pipeline de conversão | monkeypatch + shim (manter/re-verificar) | off-the-shelf, limpo | off-the-shelf, limpo |
| Risco principal | manutenção do patch entre versões | qualidade PT-BR do modelo destilado | idem, um pouco menos (12 camadas) |

## Recomendação (proposta, não decisão)

Há um trade-off real e nenhuma opção domina a outra:

- **Se a prioridade é qualidade em PT-BR com o menor risco de retrabalho**, o
  **Caminho 1** é o mais seguro: mantém o modelo já validado a 100% e a saída
  patchada é comprovadamente idêntica — não precisa repetir o Spike 1. O preço é
  276 MB INT8 e um monkeypatch a manter no pipeline offline.

- **Se a prioridade é app enxuto e pipeline de conversão limpo**, o **Caminho 2 com
  o MiniLMv2** é atraente: 103–113 MB INT8, sem patch. **Mas isso exige, antes de
  confiar, repetir o Spike 1 em PT-BR** para o modelo escolhido (sugiro o **L12**,
  que tende a segurar melhor os casos sutis que um destilado de 6 camadas). Se o
  L12 passar com folga no dataset do Spike 1, ele vira a melhor relação
  tamanho/qualidade/limpeza.

**Minha sugestão de sequência (para você aprovar):** rodar uma revalidação PT-BR
(Spike 1) do **MiniLMv2-L12** e comparar com o baseline de 100% do mDeBERTa. Se
empatar, seguir com o L12 (menor, sem patch). Se cair de forma relevante, adotar o
**Caminho 1** (patch) pela qualidade já garantida. O `symanto` fica como plano C, e
o BERTimbau/ASSIN2 está descartado por ser 2 classes.

> **Não escolhi o modelo final, não revalidei PT-BR e não iniciei o Spike 3.**
> Aguardo sua decisão sobre qual caminho seguir.

---

## Arquivos deste spike

- `common.py` — lista de candidatos, `dir_size_mb`, par PT-BR de sanity-check.
- `convert_candidate.py` — harness genérico (trace → convert → INT8 → tamanho →
  cos vs PyTorch). Registra falha com a op exata, sem reescrever arquitetura.
- `run_all.py` — roda todos os candidatos e imprime a tabela-resumo.
- `patch_deberta.py` — Caminho 1: monkeypatch do XSoftmax, equivalência e conversão.
- `results/*.json` — saída bruta por candidato (evidência das tabelas acima).
- `build/` — `.mlpackage` gerados (git-ignored; apagados após medir).

## Reproduzir
```sh
cd spikes/02b-alternativas-nli
# usa o venv pinado do Spike 2:
../02-coreml-latencia/.venv/bin/python run_all.py          # Caminho 2 (todos)
../02-coreml-latencia/.venv/bin/python patch_deberta.py    # Caminho 1 (patch)
```

---

# Revalidação PT-BR do MiniLMv2-L12 (Spike 1 repetido)

**Data:** 2026-07-24
**Objetivo:** decidir entre os dois caminhos deixados em aberto acima, repetindo o
**Spike 1** — mesmo dataset, mesmos 20 pares, mesma metodologia — trocando **apenas
o modelo de NLI** pelo candidato do Caminho 2, `MoritzLaurer/multilingual-MiniLMv2-L12-mnli-xnli`.
É a revalidação em PT-BR que faltava para esse modelo (o português **não** está
entre as línguas do XNLI).

## Método (por que a comparação é válida)

- **Dataset reusado, não recriado:** o runner importa os mesmos `PAIRS` de
  [`../01-modelos-ptbr/dataset.py`](../01-modelos-ptbr/dataset.py) (20 pares reais
  de Agência Brasil/EBC). Nada de dataset novo.
- **Pipeline reusado:** importa [`../01-modelos-ptbr/pipeline.py`](../01-modelos-ptbr/pipeline.py)
  e sobrescreve **só** `NLI_MODEL`. Embeddings idênticos ao Spike 1
  (`paraphrase-multilingual-MiniLM-L12-v2`); `nli()` lê a ordem de rótulos de
  `config.id2label` (não hardcoded), então a ordem do L12 (`0:entailment,
  1:neutral, 2:contradiction`) é tratada corretamente. Nenhum arquivo do Spike 1
  foi modificado.
- **Ambiente:** anaconda base (`sentence-transformers` 5.6.1, `transformers`
  5.14.1, `torch` 2.13.0), offline (`HF_HUB_OFFLINE=1`); modelos já no cache HF.
  Inferência PyTorch no desktop — **mesma natureza do Spike 1**.
- **Critério de empate fixado ANTES de rodar:** ver
  [`CRITERIO-EMPATE.md`](./CRITERIO-EMPATE.md). Baseline mDeBERTa = 20/20.
  **Empate ≥ 19/20** (→ Caminho 2/L12); **Caiu ≤ 18/20** (→ Caminho 1). O portão é
  a taxa **global**; classe/matriz entram como observação, não movem o portão.
- Runner: [`revalida_ptbr_L12.py`](./revalida_ptbr_L12.py). Log completo:
  `revalida_ptbr_L12.log` (git-ignored por `*.log`).

## Resultados — por par (mesmo formato do Spike 1)

| # | esperado | obtido | score | sim | acerto |
|---|---|---|---|---|---|
| 1 | entailment | entailment | 1,00 | 0,85 | ✓ |
| 2 | entailment | entailment | 0,98 | 0,86 | ✓ |
| 3 | entailment | entailment | 1,00 | 0,80 | ✓ |
| 4 | entailment | entailment | 1,00 | 0,82 | ✓ |
| 5 | entailment | entailment | 1,00 | 0,68 | ✓ |
| 6 | entailment | entailment | 0,99 | 0,76 | ✓ |
| 7 | entailment | entailment | 0,99 | 0,52 | ✓ |
| 8 | entailment | entailment | 0,99 | 0,69 | ✓ |
| 9 | contradiction | contradiction | 0,99 | 0,67 | ✓ |
| 10 | contradiction | **neutral** | 0,65 | 0,72 | ✗ |
| 11 | contradiction | contradiction | 1,00 | 0,44 | ✓ |
| 12 | contradiction | contradiction | 1,00 | 0,31 | ✓ |
| 13 | contradiction | contradiction | 1,00 | 0,32 | ✓ |
| 14 | contradiction | contradiction | 0,99 | 0,63 | ✓ |
| 15 | contradiction | contradiction | 1,00 | 0,61 | ✓ |
| 16 | neutral | neutral | 0,99 | 0,58 | ✓ |
| 17 | neutral | **contradiction** | 0,66 | 0,09 | ✗ |
| 18 | neutral | neutral | 0,99 | 0,17 | ✓ |
| 19 | neutral | **contradiction** | 0,79 | 0,13 | ✗ |
| 20 | neutral | neutral | 1,00 | 0,15 | ✓ |

**Taxa de acerto global: 17/20 = 85,0%** (baseline mDeBERTa: 20/20 = 100%).

| Classe | Acerto |
|---|---|
| entailment | 8/8 = 100% |
| contradiction | 6/7 = 86% |
| neutral | 3/5 = 60% |

**Matriz de confusão** (linha = esperado, coluna = obtido):

|  | entailment | contradiction | neutral |
|---|---|---|---|
| **entailment** | 8 | 0 | 0 |
| **contradiction** | 0 | 6 | 1 |
| **neutral** | 0 | 2 | 3 |

## Os 3 erros (diagnóstico — não alteram o portão)

- **Par 10 (contradiction → neutral, score 0,65):** "a tarifa só entra em vigor no
  ano que vem" vs. artigo que diz vigorar já nesta sexta. O L12 **não capturou a
  contradição temporal** e ficou em cima do muro (contra=0,35). É exatamente a
  "negação sutil / número-data aproximado" que o Spike 2b apontou como ponto fraco
  de um destilado.
- **Pares 17 e 19 (neutral → contradiction, scores 0,66 e 0,79):** afirmações
  **fora do tema** (dólar em queda; lucro da Petrobras) foram lidas como
  *contradição* em vez de *neutro*. O L12 **superprediz contradiction** em pares
  não relacionados — o erro mais perigoso para o produto, porque geraria
  `CONTRADITO PELAS FONTES` falso.
  *Ressalva de contexto:* esses dois pares têm similaridade muito baixa (0,09 e
  0,13) e, no pipeline real (RF-06.6, top-3 chunks acima do limiar), provavelmente
  seriam filtrados antes do NLI. Mas isso é o limiar de similaridade (`[EM ABERTO]`
  RF-06.7), **não** acurácia do NLI — e a repetição estrita do Spike 1 mede o NLI
  puro. Por isso contam como erro. Ainda assim, o par 10 (sim=0,72, alta) **não**
  seria filtrado e erraria mesmo no pipeline real.

## Aplicação do critério (como escrito, sem reinterpretar)

> MiniLMv2-L12 = **17/20**. Portão: empate ≥ 19/20, caiu ≤ 18/20.
> **17 ≤ 18 → CAIU.** (3 casos abaixo do baseline; o limite tolerava no máximo 1.)

O erro não é aleatório: concentra-se na fronteira **neutral↔contradiction**, com a
tendência mais nociva (neutro virar contradição). O critério reprova, e o padrão
de erro **reforça** a reprovação.

## Recomendação final

> **Adotar o Caminho 1 — `mDeBERTa-v3-base-xnli` com XSoftmax patchado.**

Motivos:
1. **Qualidade PT-BR comprovada e reprodutível.** O mDeBERTa fez 20/20 no Spike 1,
   e o Spike 2b provou que a versão **patchada** produz logits **idênticos** ao
   original (cos=1,0, max|Δ|=0). Logo os 100% **transferem sem re-teste** para o
   `.mlpackage` que embarca.
2. **O L12 caiu (17/20) e caiu no lugar errado** — confundindo neutro com
   contradição, o que produziria vereditos `CONTRADITO PELAS FONTES` falsos, o pior
   tipo de erro para esta feature.
3. **Cabe no orçamento.** mDeBERTa patchado = 275,9 MB INT8; com os embeddings
   (113 MB) = **~389 MB**, dentro do alvo NF-05 (<500 MB).

**Preço aceito do Caminho 1** (já mapeado no Spike 2b): o monkeypatch do XSoftmax
vive no **pipeline de conversão offline** (não no app) e precisa ser re-verificado
a cada upgrade de `transformers`/`coremltools`; depende também do shim
`bitwise_and` no ato da conversão. Nada disso entra no runtime do app.

> **Nota sobre acurácia vs. artefato Core ML:** a acurácia PyTorch medida aqui (para
> qualquer candidato) transfere para o `.mlpackage` INT8 porque o Spike 2b já provou
> a conversão preservando a saída (L12: cos=1,0000, argmax_match=true; mDeBERTa
> patchado: cos=1,0). Ou seja, medir em PyTorch é suficiente para decidir.

## O que esta tarefa NÃO fez (limites respeitados)

- **Não editou `spec.md`.** A escolha do modelo de NLI (`[EM ABERTO]` §7.3 #1)
  continua **formalmente em aberto na spec** — gravar a decisão lá é do usuário.
  Esta seção é **recomendação**, não resolução.
- Não iniciou o Spike 3 nem a implementação do pipeline.
- `symanto` segue como plano C; BERTimbau/ASSIN2 segue descartado (2 classes).
- **Latência em device (NF-01/NF-02) e RAM (NF-06) continuam não medidas** — é o
  Spike 3, ainda pendente, e independe de qual NLI for escolhido.
