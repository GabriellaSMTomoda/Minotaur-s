# SPIKE 2c — Resultado: NLI que EXECUTA em Core ML de device real

**Data:** 2026-07-24
**Objetivo:** substituir o NLI da spec (DT-18, `mDeBERTa-v3-base-xnli` com
XSoftmax patchado), que **converte e bate os logits em PyTorch mas NÃO EXECUTA em
device** (crash MPSGraph em `.all`, erro BNNS em `.cpuOnly`, trava no simulador —
Spike 2). A lição estrutural: *"converte sem erro" e "logits batem em PyTorch"*
**não** garantem *"executa em device"*. Por isso, aqui a ordem dos filtros é
**invertida**: execução em device real vem **antes** de qualidade PT-BR.

Código descartável, isolado do app. **Não editei `spec.md`** (DT-18 segue gravada
até sua decisão). Não implementei nada do app principal. Não avancei para o Spike 4.
**A escolha final do modelo é sua** — este documento é RECOMENDAÇÃO, não decisão.

---

## Veredito rápido

> **3 candidatos passaram em TODOS os filtros, incluindo execução com logits
> corretos no iPhone físico** — o gate onde o mDeBERTa falhou. Recomendação:
> **`multilingual-MiniLMv2-L6-mnli-xnli`** (o menor, o mais rápido e o de melhor
> PT-BR neste dataset), com o **L12** como alternativa próxima. **ERNIE-M
> reprovado** por reproduzir o mesmo crash MPSGraph do mDeBERTa + gerar NaN.

Havia risco real de **nenhum** candidato passar no Filtro 2 (a instrução previa
parar e avisar). **Não foi o caso:** os XLM-R de atenção padrão executam de fato.

---

## Tabela mestra — candidato × filtro

| # | Candidato | Arquitetura | F1 Converte | F2 Executa device | F3 PT-BR | F4 Tamanho | Resultado |
|---|---|---|:---:|:---:|:---:|:---:|:---:|
| 1 | **MiniLMv2-L6-mnli-xnli** | XLM-R-large destilado, 6 cam. | ✅ | ✅ `.cpuOnly`+`.all` | **18/20** | 103 MB | ✅ **PASSA** |
| 2 | **MiniLMv2-L12-mnli-xnli** | XLM-R-large destilado, 12 cam. | ✅ | ✅ `.cpuOnly`+`.all` | 17/20 | 113 MB | ✅ **PASSA** |
| 3 | **symanto xlm-roberta-base** | XLM-R-base, 12 cam. | ✅ | ✅ `.cpuOnly` (⚠️ `.all` = jetsam) | 16/20 | 266 MB | ✅ **PASSA** |
| 4 | ernie-m-base-mnli-xnli | ERNIE-M (base RoBERTa/XLM-R) | ⚠️ converte, artefato quebrado | ❌ NaN em `.cpuOnly`; SIGABRT MPSGraph em `.all` | — | — | ❌ **REPROVA (F2)** |

Referências documentadas, **não testadas** (com motivo):

| Candidato | Motivo de não testar |
|---|---|
| `mDeBERTa-v3-base-xnli` (patchado) | Já REPROVADO no Filtro 2 no Spike 2 (crash MPSGraph `.all`, BNNS `.cpuOnly`, trava simulador). É o incumbente que motivou este spike. |
| `joeddav/xlm-roberta-large-xnli` | XLM-R-large, atenção padrão, 3 classes — converteria, mas ~560 MB INT8 estoura NF-05 junto com os 113 MB dos embeddings. Teto de qualidade, fora de orçamento. |
| `MoritzLaurer/xlm-v-base-mnli-xnli` | Atenção padrão e 3 classes, MAS vocab de ~901k tokens → matriz de embedding gigante, tamanho inviável para NF-05. |
| `bert-base-portuguese-cased-nli-assin-2` (BERTimbau) | **2 classes** (entailment/none) → não produz `contradiction` → viola RF-07.2/RF-08.1 (Spike 2b). |

---

## FILTRO 1 — Converte para Core ML sem custom op

Fluxo por candidato (reusa o do Spike 2/2b): `trace → ct.convert(FLOAT16, iOS16,
mlprogram) → linear_quantize_weights(INT8)`, e **sanity no desktop** rodando o
`.mlpackage` INT8 sobre um par PT-BR real e comparando os logits com o PyTorch.
Script: [`convert_and_reference.py`](./convert_and_reference.py) · candidatos e
justificativa arquitetural (escrita **antes** de testar):
[`candidates.py`](./candidates.py).

| Candidato | id2label | FP16 | INT8 | cos(logits) INT8 vs PyTorch (desktop) |
|---|---|---|---|---|
| L6 | 0:entailment 1:neutral 2:contradiction | 204,2 MB | **103,0 MB** | **1,0000** |
| L12 | 0:entailment 1:neutral 2:contradiction | 224,6 MB | **113,3 MB** | **1,0000** |
| symanto | 0:ENTAILMENT 1:NEUTRAL 2:CONTRADICTION | 530,6 MB | 266,4 MB | 1,0000 |
| erniem | 0:entailment 1:neutral 2:contradiction | 530,5 MB | 266,3 MB | **NaN** (ver abaixo) |

**Os 3 XLM-R convertem limpo** (mesma família de atenção padrão do Spike 2b;
`cos=1,0`, sem custom op).

**ERNIE-M é o caso-armadilha que este spike existe para pegar:** `ct.convert(...)`
**não lança exceção** e gera um `.mlpackage`, mas o artefato INT8 está
**numericamente quebrado** — o predict de sanity no desktop (CPU) retorna
`[nan, nan, nan]`. Durante a quantização apareceram avisos
`invalid value encountered in divide` (scale zero → divisão por zero) e, na
conversão FP16, `overflow encountered in cast` (pesos estouram o range do FP16).
Ou seja, "converteu" ≠ "converteu para um modelo que funciona". Por rigor, ele
foi mesmo assim levado ao Filtro 2.

---

## FILTRO 2 — EXECUTA de fato em device real (gate crítico)

Reusa o harness [`../02-coreml-latencia/xcode-bench/`](../02-coreml-latencia/xcode-bench)
(medição de RAM via `mach_task_basic_info`, auto-run, `setbuf(stdout,nil)`),
**estendido** para: ler um `manifest.json` embarcado com o par PT-BR já tokenizado
por modelo + os logits PyTorch de referência, rodar `.predict()` e **verificar se
os logits do device batem com a referência** (`cos`, argmax) — não só "não lançou
exceção". Ordena `.cpuOnly` antes de `.all` para não perder dados se `.all`
crashar. Driver: [`run_bench_device.sh`](./run_bench_device.sh). Evidência bruta:
[`device_results_iphone.log`](./device_results_iphone.log) (device) e
[`device_results_sim.log`](./device_results_sim.log) (simulador).

**Ambientes:** simulador iPhone 16 Pro, **iOS 18.6**; iPhone 16 físico
(`iPhone17,3`) **`br-NKHFRW9FDY`, iOS 26.3.1** (atende ao piso "iPhone 13+" de
NF-01/NF-02). Testados `.all` **e** `.cpuOnly` separadamente.

### iPhone 16 físico (br-NKHFRW9FDY, iOS 26.3.1)

| Modelo | `.cpuOnly` | `.all` | logits corretos? |
|---|---|---|---|
| **L6** | ✅ mediana **2,0 ms** · RAM 73 MB | ✅ mediana 10,5 ms | **cos=1,0** (ambos) |
| **L12** | ✅ mediana **3,05 ms** · RAM 100 MB | ✅ mediana 20,7 ms | **cos=1,0** (ambos) |
| **symanto** | ✅ mediana **14,3 ms** · RAM 221 MB | ❌ **SIGKILL (jetsam)** | cos=1,0 em `.cpuOnly` |
| erniem | ❌ **NaN** (roda, saída inválida) | ❌ **SIGABRT** `MPSGraph MLIR pass manager failed` | — |

- **Os 3 XLM-R executam com logits corretos no device físico** — inclusive em
  `.cpuOnly`/BNNS, **o caminho exato onde o mDeBERTa falhou** (Spike 2:
  "E5RT BNNS Op"). L6 e L12 rodam também em `.all` sem crash (o mDeBERTa dava
  SIGABRT em `.all`).
- **symanto:** viável **só em `.cpuOnly`**. Em `.all`, mesmo em processo isolado,
  o modelo de 266 MB estoura a memória na compilação ANE/MPSGraph e o iOS mata o
  processo (jetsam, signal 9). Passa o Filtro 2 (produz logits corretos em ≥1
  config de device físico), mas com menos folga que L6/L12.
- **ERNIE-M reprova:** `.cpuOnly` produz **NaN** (artefato quebrado do Filtro 1) e
  `.all` reproduz **exatamente** o crash do mDeBERTa
  (`MPSGraphExecutable.mm: failed assertion 'Error: MLIR pass manager failed'`,
  SIGABRT). É a materialização da lição do spike: converteu, mas não executa.

> **Nota sobre a RAM em `.all`:** o harness carrega todos os modelos no mesmo
> processo sem descarregar, então o pico de RAM em `.all` **acumula** (ex.: L12
> `.all` reportou ~1093 MB, mas isso inclui o runtime ANE já carregado do L6). O
> número **limpo por modelo** é o de `.cpuOnly` (L6 73 MB, L12 100 MB, symanto
> 221 MB) — todos folgados em NF-06 (<1 GB). Em `.cpuOnly` a latência também é
> **menor** que em `.all` (o shape dinâmico RangeDim não aproveita bem a ANE), o
> que sugere `.cpuOnly` como config padrão do NLI no app.

### Simulador iPhone 16 Pro, iOS 18.6 (confirmação secundária)

| Modelo | `.cpuOnly` (mediana) | `.all` (mediana) | logits |
|---|---|---|---|
| L6 | 17,5 ms | 17,7 ms | cos=1,0 |
| L12 | 35,1 ms | 35,8 ms | cos=1,0 |
| symanto | 93,2 ms | 91,4 ms | cos=1,0 |
| erniem | NaN | NaN | quebrado |

(RAM do simulador **não** é comparável — roda como processo host do macOS, como já
registrado no Spike 2. Serve só como confirmação de que os XLM-R executam e o
ERNIE-M é NaN em todo ambiente.)

---

## FILTRO 3 — Qualidade PT-BR (só sobreviventes do Filtro 2)

Repete o **Spike 1** — mesmos 20 pares, mesmo pipeline (importa
`spikes/01-modelos-ptbr/dataset.py` e `pipeline.py`, sobrescreve só o NLI; `nli()`
lê a ordem de rótulos de `config.id2label`). Inferência PyTorch no desktop — a
conversão preserva a saída (Filtro 1: `cos=1,0`), então a acurácia transfere para
o `.mlpackage`. Script: [`filter3_ptbr.py`](./filter3_ptbr.py). **Baseline
mDeBERTa (Spike 1) = 20/20 = 100%** (mas não-executável em device).

| Modelo | Global | entailment | contradiction | neutral | Erros perigosos* |
|---|---|---|---|---|---|
| **L6** | **18/20 = 90%** | 7/8 | **7/7** | 4/5 | **1** (par 17) |
| L12 | 17/20 = 85% | **8/8** | 6/7 | 3/5 | 2 (pares 17, 19) |
| symanto | 16/20 = 80% | 5/8 | 6/7 | **5/5** | 2 (pares 1, 8) |

\* *"erro perigoso"* = classificar como `contradiction` algo que é `neutral` ou
`entailment` — geraria um veredito falso `CONTRADITO PELAS FONTES`, o pior erro
para esta feature.

**Matrizes de confusão** (linha=esperado, coluna=obtido):

```
L6                 ent  con  neu       L12                ent  con  neu       symanto            ent  con  neu
entailment          7    0    1        entailment          8    0    0        entailment          5    2    1
contradiction       0    7    0        contradiction       0    6    1        contradiction       0    6    1
neutral             0    1    4        neutral             0    2    3        neutral             0    0    5
```

**Leitura:** neste dataset o **L6 lidera** (90%), com só 1 erro perigoso e
`contradiction` perfeito. O L12 acerta todos os `entailment` mas erra 2 neutros
como contradição (o padrão nocivo que o Spike 2b já apontara). O symanto é o mais
fraco em `entailment` (5/8, com 2 virando contradição). **Ressalva honesta:** 20
pares é pouco; diferença de 1-2 acertos é ruído estatístico. O que se pode afirmar
com segurança é que **os 3 ficam na faixa 80-90%, abaixo dos 100% do mDeBERTa** —
esse é o preço de usar um modelo que **de fato executa** em device.

---

## FILTRO 4 — Tamanho (NF-05 < 500 MB)

Embeddings INT8 = **113 MB** (Spike 2). Somando o NLI:

| Modelo | NLI INT8 | + Embeddings | NF-05 (<500 MB) |
|---|---|---|---|
| **L6** | 103,0 MB | **216 MB** | ✅ folgado |
| L12 | 113,3 MB | **226 MB** | ✅ folgado |
| symanto | 266,4 MB | 379 MB | ✅ cabe |

Todos passam. L6/L12 deixam bastante folga (~280 MB) para o resto do app.

---

## Comparativo final dos sobreviventes

| Critério | **L6** | L12 | symanto |
|---|---|---|---|
| Executa device `.cpuOnly` | ✅ 2,0 ms | ✅ 3,05 ms | ✅ 14,3 ms |
| Executa device `.all` | ✅ 10,5 ms | ✅ 20,7 ms | ❌ jetsam |
| Logits corretos (cos vs PyTorch) | 1,0 | 1,0 | 1,0 |
| PT-BR (20 pares) | **18/20** | 17/20 | 16/20 |
| Erros perigosos (neu/ent→contra) | **1** | 2 | 2 |
| Tamanho NLI INT8 | **103 MB** | 113 MB | 266 MB |
| App total (+113 MB emb.) | **216 MB** | 226 MB | 379 MB |
| RAM device (`.cpuOnly`) | **73 MB** | 100 MB | 221 MB |
| Robustez em `.all` | ✅ | ✅ | ❌ |
| Pipeline de conversão | limpo | limpo | limpo |

---

## RECOMENDAÇÃO (proposta, decisão sua)

> **Adotar `MoritzLaurer/multilingual-MiniLMv2-L6-mnli-xnli` como NLI**, em
> substituição ao mDeBERTa do DT-18, rodando em **`.cpuOnly`** no app.

Motivos:
1. **É o único que domina em todos os eixos:** melhor PT-BR do grupo (18/20),
   menor (103 MB / 216 MB total), mais rápido (2 ms em device), menor RAM (73 MB),
   executa correto em device nas **duas** configs de compute, e sem custom op no
   pipeline de conversão.
2. **Passou o gate que reprovou o incumbente:** logits corretos em `.cpuOnly`/BNNS
   no iPhone físico — onde o mDeBERTa quebrava.
3. **Menos erros perigosos** (1 vs 2 dos outros dois), reduzindo o risco de
   `CONTRADITO PELAS FONTES` falso.

**Alternativa próxima — L12:** se você preferir mais capacidade de arquitetura
(12 camadas) como seguro para casos mais difíceis que os 20 pares não cobrem, o
L12 também passa tudo e custa só +10 MB e +1 ms. A diferença de PT-BR (17 vs 18)
está dentro do ruído do dataset. **symanto fica como plano C** (maior, e não roda
em `.all` no device).

**O trade-off que é seu para decidir:** todos os candidatos executáveis ficam em
**80-90%** de PT-BR neste dataset, **abaixo dos 100% do mDeBERTa** — que, no
entanto, **não executa em device** e por isso não é uma opção real. A escolha é
entre um NLI que roda a ~90% e um que não roda. Se 90% não for aceitável, o
próximo passo não é outro modelo desta lista, e sim **repensar a abordagem do
pipeline** (ex.: XLM-R-large com download sob demanda para caber em NF-05, ou
reavaliar se o NLI on-device é a via) — e isso é decisão sua, como você pediu.

**Se você aprovar um destes**, os próximos passos (fora deste spike) seriam:
atualizar DT-18/§3.2 da spec (você grava), calibrar os limiares `[EM ABERTO]` de
similaridade (RF-06.7) e confiança do NLI (RF-07.5), e avaliar **shape
fixo/enumerado** em vez de RangeDim para eventualmente habilitar a ANE (hoje o
`.cpuOnly` é mais rápido justamente por causa do shape dinâmico).

---

## O que este spike NÃO fez (limites respeitados)

- **Não editei `spec.md`** — DT-18 (mDeBERTa) segue gravada até sua decisão.
- Não implementei nada do app principal, nem avancei para o Spike 4 (scraping DDG).
- **Não tentei patchar/contornar** o ERNIE-M nem o mDeBERTa — reprovados no Filtro
  2 são documentados e parados aqui, não "consertados" por conta própria.
- Não resolvi nenhum item `[EM ABERTO]` da spec.
- Os limiares de similaridade/confiança seguem `[EM ABERTO]` (aqui só observados).

## Arquivos deste spike

- [`candidates.py`](./candidates.py) — candidatos + justificativa arquitetural (pré-teste).
- [`convert_and_reference.py`](./convert_and_reference.py) — Filtro 1 + geração do `manifest.json`.
- [`filter3_ptbr.py`](./filter3_ptbr.py) — Filtro 3 (reusa dataset/pipeline do Spike 1).
- [`run_bench_device.sh`](./run_bench_device.sh) — build assinado + install + run no device.
- `device_results_iphone.log` / `device_results_sim.log` — evidência bruta de execução.
- `build/manifest.json` + `build/*_int8.mlpackage` — artefatos (git-ignored; grandes).
- Harness estendido: `../02-coreml-latencia/xcode-bench/Sources/{Benchmark,ContentView}.swift`.

## Reproduzir
```sh
cd spikes/02c-nli-executavel
../02-coreml-latencia/.venv/bin/python convert_and_reference.py   # Filtro 1 + manifest
/opt/anaconda3/bin/python filter3_ptbr.py                         # Filtro 3 (PT-BR)
# Filtro 2 (device) — requer conta Apple logada no Xcode:
cd ../02-coreml-latencia/xcode-bench && xcodegen generate && cd -
./run_bench_device.sh                                             # build+install+run no iPhone
```
