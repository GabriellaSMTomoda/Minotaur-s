# CoreMLBench — harness de latência (Spike 2)

App iOS **mínimo e descartável** para medir a latência de inferência dos
modelos Core ML do Spike 2 **em iPhone real**. Não é o app principal.

Foi escrito aqui, mas **não pôde ser compilado/rodado neste ambiente** (sem
Xcode completo, sem simulador, sem dispositivo). Os números de latência
(NF-01/NF-02) dependem de você rodar isto num Mac com Xcode + iPhone.

## Pré-requisitos
- Xcode instalado (não apenas Command Line Tools).
- `xcodegen` (`brew install xcodegen`) — o app principal já usa.
- Os `.mlpackage` gerados em `../build/` (rode `convert_embeddings.py` e,
  se/quando o NLI for viabilizado, `convert_nli.py`).

## Passos
```sh
cd spikes/02-coreml-latencia/xcode-bench
xcodegen generate
open CoreMLBench.xcodeproj
```
1. Selecione um **iPhone físico** (iPhone 13 ou superior, conforme NF-01/NF-02).
2. Ajuste o *Signing Team* no target (necessário para rodar em device).
3. Rode e toque em **“Rodar benchmark”**.

O app carrega `Embeddings_int8` e `NLI_int8` do bundle, roda 50 inferências
(após 5 de warmup) com input de tamanho realista e reporta mediana/média/min/max.
Resultados aparecem na tela e no console do Xcode.

## O que ele mede (e o que não mede)
- **Mede:** só `MLModel.prediction(...)` — a inferência pura, coerente com a
  definição de NF-01 (“inferência de embeddings … < 150 ms”) e NF-02
  (“inferência de NLI … < 1 s”).
- **Não mede:** tokenização (feita em Swift via `swift-transformers` no app
  real), busca, download nem parsing. Os `input_ids` são sintéticos — não
  afetam a latência de forma relevante.

## Notas
- `deploymentTarget` está em 16.0 (os modelos foram convertidos com
  `minimum_deployment_target = iOS16`). O app principal hoje mira iOS 17.
- Compute units = `.all` (deixa o Core ML escolher CPU/GPU/ANE). Para comparar,
  dá para trocar por `.cpuOnly` / `.cpuAndGPU` em `ContentView.swift`.
- Se um modelo não estiver no bundle, o card correspondente mostra erro em
  vez de crashar — útil enquanto o NLI não é viabilizado.
