# SPIKE 10 — Segundo NLI (ensemble): MiniLMv2-L6 em Core ML

**Data:** 2026-11-24 · **Escopo:** só produzir e validar o artefato Core ML. Nada foi
copiado para `model-parts/`, o manifesto e o app não foram tocados, nenhum commit.

## Veredito rápido

- **Artefato pronto:** `build/NLI2.mlpackage` → `build/NLI2.mlmodelc`, 103,0 MiB,
  pesos INT8 (`linear_symmetric`) com compute FP16, iOS16 mlprogram, `RangeDim 1…512`.
  Entradas `input_ids`/`attention_mask` (Int32), **sem `token_type_ids`**; saída
  `logits` [1,3] Float16 (mesmo dtype do `NLI.mlmodelc` atual). Metadado
  `model_version = "minilmv2-l6-mnli-xnli-v1"` presente no `.mlpackage` e no
  `metadata.json` do `.mlmodelc`.
- **Rótulos:** `config.id2label` = 0 entailment, 1 neutral, 2 contradiction →
  [`NLI2Labels.json`](./NLI2Labels.json).
- **Tokenizer:** idêntico ao `EmbeddingsTokenizer.json` (vocabulário, scores e ids).
  Dá para reaproveitar o `XLMRTokenizer.swift` e o asset já embarcado, **mas falta
  um método de par** (`<s> P </s></s> H </s>`) com truncamento que reserva a hipótese.
- **Paridade PyTorch FP32 × Core ML INT8 (CPU):** 35 pares, **argmax 34/35**,
  max |Δprob| **0,062**, média 0,0085, todos finitos. A única troca (`spike7-B-2`)
  é um quase-empate e vem da quantização INT8 (FP16 sem INT8: 35/35, max 0,016).
- **Mac (M4, CPU_ONLY):** carga 0,47 s; predict mediana 1,44 ms nos pares reais,
  11,7 ms em 512 tokens.
- **Aviso para a próxima etapa (não é métrica):** nas 15 regressões conhecidas o L6
  diz `contradiction` em só 3 (A-9, B-4, B-5) e `entailment` com 0,79–0,99 em 9 que
  pedem `contradiction`. Com um gate "contradição só se os dois concordarem", ele vai
  vetar quase todas as contradições desses casos. Ver [Leitura para o ensemble](#leitura-para-o-ensemble).

## Ambiente e reprodução

- `uv` + CPython 3.11.16; [`pyproject.toml`](./pyproject.toml) + [`uv.lock`](./uv.lock):
  torch 2.7.0, transformers 4.46.3, coremltools 9.0, numpy<2.3 (mesmo toolchain dos
  Spikes 2/2c). Shims `new_ones`/`bitwise_and` de `../02-coreml-latencia/coreml_shims.py`
  (não mudam arquitetura).
- Modelo: `MoritzLaurer/multilingual-MiniLMv2-L6-mnli-xnli`, revisão
  `0a71e92a985b6e1ad1828cf67ce9c459639c1dca` (já estava no cache HF; rodado com
  `HF_HUB_OFFLINE=1`).
- Máquina: Apple M4, macOS 27.0.1.

```sh
cd spikes/10-ensemble-minilm
uv sync
HF_HUB_OFFLINE=1 uv run python convert.py              # NLI2.mlpackage + .mlmodelc + NLI2Labels.json
HF_HUB_OFFLINE=1 uv run python compare_tokenizers.py   # build/tokenizer_compare.json
HF_HUB_OFFLINE=1 uv run python parity_latency.py       # build/parity_latency.json
HF_HUB_OFFLINE=1 uv run python attribute_precision.py /tmp/attr   # build/attribution.json
```

`convert.py` reaproveita `../02c-nli-executavel/candidates.py` (entrada `L6`,
`MAX_SEQ=512`) e o fluxo de `convert_and_reference.py` (trace → convert FP16 →
`linear_quantize_weights` INT8), e acrescenta metadados e a compilação via
`xcrun coremlcompiler compile`.

## Artefato

| Item | Valor |
|---|---|
| `build/NLI2.mlpackage` | 103,0 MiB |
| `build/NLI2.mlmodelc` | 103,0 MiB (`weights/weight.bin` 102,8 MiB) |
| SHA-256 `NLI2.mlmodelc/weights/weight.bin` | `8bfbf634db0dc8bb2ecf708a27121586dfefd886673af0962fb3e1fa8935eed8` |
| Precisão | `storagePrecision: Mixed (Float16, Int8)`, specificationVersion 7 |
| Entradas | `input_ids`, `attention_mask`: Int32 `[1, 1…512]` |
| Saída | `logits`: Float16 `[1,3]`, sem softmax |
| Metadados | `model_version`, `source_model`, `source_revision`, `id2label`, `quantization` |

Tamanho igual ao do Spike 2c (103,0 MB). O `weight.bin` passa de 100 MB, então, se for
versionado, precisa ser fatiado como os outros em `model-parts/` (não feito aqui).

**Avisos na conversão:** `overflow encountered in cast` (passe `optimize_repeat_ops`)
e, na quantização INT8, `invalid value encountered in cast` — a mesma família de
avisos que, no ERNIE-M do Spike 2c, terminou em NaN. Aqui **todas as saídas foram
finitas** (35 pares reais + entradas sintéticas de 64/128/256/512 tokens) e a
paridade bate, então o aviso não se materializou. Não investiguei qual tensor o dispara.

## Tokenizer × `EmbeddingsTokenizer.json`

Script: [`compare_tokenizers.py`](./compare_tokenizers.py) → `build/tokenizer_compare.json`.

| Verificação | Resultado |
|---|---|
| Vocabulário Unigram (250.002 tokens, ordem e scores) | **idêntico** |
| `normalizer`, `post_processor`, `added_tokens` | idênticos |
| `pre_tokenizer`/`decoder` | equivalentes: o do modelo usa o formato antigo `add_prefix_space: true`; o do app, o novo `prepend_scheme: "always", split: true` |
| `model` além do vocab | só falta `byte_fallback: false` (padrão) no do modelo |
| `truncation` embutido no JSON | modelo 256, app 128 (ambos ignorados pelo código, que trunca à mão) |
| Ids em 60 frases PT × (sem/com especiais) = 120 codificações, 1.407 tokens | **0 divergências** (fast do modelo = fast do app = HF) |
| 35 pares `encode(P, H)` vs. montagem manual `[0] + P + [2, 2] + H + [2]` com o tokenizer do app | **0 divergências** |

Frases: premissas/hipóteses dos 35 pares abaixo + afirmações de
`evaluation/data/dev_claims.jsonl` (sem rótulo usado).

**Reaproveitar `XLMRTokenizer.swift`?** Sim, com uma extensão. O asset é o mesmo, então
basta `XLMRTokenizer.embeddings()`, sem embarcar outro `tokenizer.json`. Hoje o tipo só
sabe codificar texto isolado (`<s> X </s>`). Para o NLI2 falta:
1. um `encodePair(premise:hypothesis:)` que monte `<s> P </s></s> H </s>` (ids 0 e 2
   lidos do tokenizer, como já é feito) e devolva `attention_mask` toda em 1;
2. truncamento só da premissa, reservando a hipótese no limite de 512 (4 especiais),
   coerente com a regra do CLAUDE.md para o NLI atual.

Ressalva: esta comparação é em Python (`tokenizers`/HF). A paridade Swift
(`swift-transformers`) × Python do asset de embeddings é a do Spike 7
(`../07-tokenizer-parity/`); o `do_lower_case: true` do
`EmbeddingsTokenizerConfig.json` não tem efeito no Python (ids iguais aos do modelo),
mas o comportamento do lado Swift para o NLI2 deve ser conferido num teste de paridade
com ids de par quando houver integração.

## Paridade PyTorch × Core ML (CPU_ONLY)

Script: [`parity_latency.py`](./parity_latency.py) → `build/parity_latency.json` (logits
e probabilidades por par). Pares: 15 de `evaluation/data/known_regressions.jsonl` + 20
do Spike 1 (`../01-modelos-ptbr/dataset.py`); 27–104 tokens. Softmax T=1.

| Métrica | INT8 final |
|---|---|
| argmax igual | **34/35** |
| max \|Δprob\| | **0,0618** (spike1-6) |
| média do max \|Δprob\| por par | 0,0085 |
| max \|Δlogit\| | 0,203 |
| NaN/Inf | nenhum |

Troca de argmax: `spike7-B-2`, PyTorch neutral 0,523 / entailment 0,456 → Core ML
entailment 0,500 / neutral 0,478. Nenhum lado chega perto de contradição (0,021/0,022).

**Atribuição** ([`attribute_precision.py`](./attribute_precision.py), variantes
temporárias, apagadas depois):

| Variante | argmax igual | max \|Δprob\| |
|---|---|---|
| FP32 mlprogram | 35/35 | 2,2e-6 |
| FP16 sem quantização | 35/35 | 0,016 |
| **FP16 + INT8 (artefato)** | 34/35 | 0,062 |

O desvio vem da quantização INT8. Se uma margem de 0,06 for demais para os limiares do
ensemble, a alternativa medida é FP16 puro (≈204 MB pelo Spike 2c, 35/35, 0,016).

## Tamanho e latência no Mac

Apple M4, macOS 27.0.1, `CompiledMLModel(..., CPU_ONLY)`, 3 aquecimentos.

| Medida | Mediana | p90 |
|---|---|---|
| Carga a frio do `.mlmodelc` | 0,465 s | — |
| 35 pares reais × 10 | 1,44 ms | 1,83 ms |
| 64 tokens (×30) | 1,17 ms | 1,20 ms |
| 128 tokens | 1,98 ms | 2,02 ms |
| 256 tokens | 4,30 ms | 4,48 ms |
| 512 tokens | 11,74 ms | 12,36 ms |

Para 24 pares de até 512 tokens: ~0,3 s no Mac. **Não medi RAM nem iPhone**; a
referência em device é a do Spike 2c (iPhone 16, `.cpuOnly`, 2,0 ms no par curto, 73 MB
de RAM), em outro artefato da mesma conversão.

## Leitura para o ensemble

Só informativo: rótulos do Core ML contra `allowed_labels`/`esperado` dos 35 pares. Não
é métrica de acurácia nem base para calibração.

- Spike 1 (20): 18/20, como no Spike 2c (erros: spike1-2 → neutral; spike1-17 →
  **contradiction** 0,69 onde se espera neutral).
- Regressões conhecidas (15): **4/15** no rótulo permitido. `contradiction` só em A-9
  (0,86), B-4 (0,64) e B-5 (0,98). Em A-1…A-6 e B-3, que pedem `contradiction`, o L6 dá
  `entailment` com 0,79–0,99; B-1 vira neutral (0,99). A-7/A-8 (neutral) → entailment.

Consequência para o plano "aceitar contradição só se os dois concordarem": nesses casos
de refutação (premissa que desmente a hipótese), o L6 tende a ler tema compartilhado
como entailment, então vetaria contradições que o BERTimbau acerte. O gate reduz
contradições espúrias, mas pode zerar a cobertura de contradição nesses padrões. A
avaliação no harness tem que medir as duas coisas.

## Limpeza e disco

- Mantidos: `build/NLI2.mlpackage`, `build/NLI2.mlmodelc`, JSONs de resultado.
  `build/` e `.venv/` estão no `.gitignore` local.
- Apagados: variantes FP32/FP16 temporárias (scratchpad) e `.venv` (recriável com `uv sync`).
- Não mexi no cache global do `uv` (~12 GB, cresceu ~1 GB com o torch 2.7.0) nem no
  cache HF (o modelo já estava lá): outras sessões usam os mesmos caches agora.

## Arquivos

- [`convert.py`](./convert.py), [`pt_data.py`](./pt_data.py),
  [`compare_tokenizers.py`](./compare_tokenizers.py),
  [`parity_latency.py`](./parity_latency.py),
  [`attribute_precision.py`](./attribute_precision.py)
- [`NLI2Labels.json`](./NLI2Labels.json), `pyproject.toml`, `uv.lock`, `.gitignore`
- `build/` (ignorado): `NLI2.mlpackage`, `NLI2.mlmodelc`, `tokenizer_compare.json`,
  `parity_latency.json`, `attribution.json`
