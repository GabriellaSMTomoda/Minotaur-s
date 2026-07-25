# SPIKE 2 — Resultado: Conversão Core ML + Latência

**Data:** 2026-07-24
**Objetivo (§7.4, item 2):** converter os modelos validados no Spike 1 para
Core ML, quantizar, medir latência em dispositivo e determinar a versão mínima
de iOS. Insumo para os itens `[EM ABERTO]` §7.3 #9 (iOS mínimo) e #11 (tamanho).

Código de validação descartável, isolado do projeto Xcode. Nenhum item
`[EM ABERTO]` foi resolvido por conta própria.

---

## Veredito rápido

| Modelo | Converte p/ Core ML? | Tamanho INT8 | Saída preservada | Latência device |
|---|---|---|---|---|
| **Embeddings** (MiniLM multilíngue) | ✅ Sim | **113,2 MB** | ✅ cos=0,9999 vs PyTorch | ⛔ não medida (sem device) |
| **NLI** (mDeBERTa-v3) | ❌ **Não** | — | — | — |

> **Recomendação: PARCIALMENTE VIÁVEL / BLOQUEADO NO NLI.**
> Os embeddings são plenamente viáveis. O NLI **mDeBERTa-v3 não converte** para
> Core ML sem modificar a arquitetura do modelo (custom op `XSoftmax`). Isso
> **reabre a escolha do modelo de NLI** (§7.3 item 1). A latência em device
> (NF-01/NF-02) e a RAM (NF-06) **não puderam ser medidas neste ambiente**.

---

## Limitação central do ambiente

Este ambiente tem apenas **Command Line Tools**, sem **Xcode** completo:
`xcodebuild`, `simctl` e `xctrace` indisponíveis. Portanto **não foi possível**:
- compilar/rodar o app de medição (nem em simulador),
- medir latência em dispositivo real (nem simulador — não havia fallback),
- medir RAM de pico.

O harness de medição foi **escrito** (`xcode-bench/`, o `.xcodeproj` gera com
`xcodegen generate`), mas precisa ser rodado por você num Mac com Xcode +
iPhone. Os alvos NF-01/NF-02/NF-06 seguem **não confirmados**.

---

## Toolchain

A tentativa inicial usou o ambiente do Spike 1 (**torch 2.13**), que o
**coremltools 9.0 não testa** (máx. testado: 2.7.0). Isso gerou uma cascata de
ops/dtypes incompatíveis (`new_ones`, `bitwise_and` int/bool, `layer_norm`
fp16). Com sua autorização, o toolchain foi **alinhado** num venv isolado
(`requirements-pinned.txt`): **torch 2.7.0 · transformers 4.46.3 ·
coremltools 9.0**. Nesse ambiente suportado, os shims de versão **não são
acionados** — a conversão dos embeddings é limpa. Os shims (`coreml_shims.py`)
ficaram apenas como salvaguarda documentada.

---

## Embeddings — `paraphrase-multilingual-MiniLM-L12-v2`

**Converte para Core ML: SIM**, limpo no toolchain alinhado.

| Formato | Tamanho |
|---|---|
| FLOAT16 | 224,3 MB |
| **INT8 (pesos)** | **113,2 MB** |

- **Correção da conversão validada** rodando o `.mlpackage` via coremltools no
  desktop e comparando com o PyTorch sobre um chunk real em PT-BR:
  - fp16: `cos(CoreML, PyTorch) = 1,0000`
  - int8: `cos(CoreML, PyTorch) = 0,9999` → a quantização quase não altera a saída.
- Latência **desktop** (Mac, coremltools): ~20 ms (fp16) / ~25 ms (int8).
  **NÃO é latência de device** — serve só como sanity check de que roda.
- Grafo: `input_ids + attention_mask → mean pooling → L2 normalize`, com seq
  flexível (1..512).

**Pontos de atenção:**
- O modelo é **grande** (fp16 224 MB) por causa do vocabulário multilíngue de
  ~250k tokens (a matriz de embedding domina o tamanho). INT8 corta para ~113 MB.
- Aviso recorrente no runtime: `Data-dependent shapes were disabled:
  embedding [?, 384]`. O modelo **roda** (via CPU), mas o shape de sequência
  dinâmico pode **impedir uso da ANE**. Para device, avaliar **shapes fixos ou
  enumerados** (ex.: 128/256/512) em vez de `RangeDim` — a decidir no Spike de
  implementação, não aqui.

## NLI — `mDeBERTa-v3-base-xnli` — **NÃO CONVERTE**

**Bloqueio (confirmado no toolchain suportado):**
```
NotImplementedError: PyTorch convert function for op 'pythonop' not implemented.
```
Causa raiz (verificada na fonte do transformers): o DeBERTa-v2/v3 usa uma
`torch.autograd.Function` **customizada**, `XSoftmax`
(`modeling_deberta_v2.py:72`, usada na disentangled-attention em
`:726`), além de `XDropout`. No grafo traçado ela vira um `prim::PythonOp`, que
o coremltools **não sabe converter**.

- **Isto é o risco §7.1 materializado** ("conversão para Core ML falhar por
  operações não suportadas"), e é **arquitetural**, não de versão: ocorre
  igualmente no toolchain suportado (torch 2.7).
- Antes desse bloqueio, a conversão exigiu ainda: carregar o checkpoint (salvo
  em fp16) como fp32. Isso foi feito (é precisão de carregamento, não
  arquitetura). O `pythonop`/`XSoftmax` é que é o muro.
- **Não foi contornado.** Contornar exige **modificar a atenção do modelo**
  (trocar `XSoftmax.apply` por um softmax mascarado padrão) — mudança de
  arquitetura que, pela instrução do passo 3, **não faço sem sua decisão**.

## Caminhos possíveis para o NLI (decisão sua — reabre §7.3 item 1)

1. **Patchar a atenção do DeBERTa** (substituir `XSoftmax` por
   `softmax(masked_scores)`), reconverter e **validar que a saída bate** com o
   modelo original antes de confiar. Mantém o modelo do Spike 1, mas mexe na
   arquitetura.
2. **Trocar por um NLI amigável a Core ML** — variantes XNLI baseadas em
   **XLM-R / mBERT** (usam softmax padrão, sem custom op). Isso **reabre a
   escolha de modelo** e idealmente **revalidar em PT-BR** (repetir o Spike 1
   para o novo modelo).
3. **Adiar** e seguir com o resto do pipeline usando só os embeddings, deixando
   o NLI pendente.

---

## Metas da spec — status

| Meta | Alvo | Status |
|---|---|---|
| NF-01 (embeddings) | < 150 ms / chunk | ⛔ não medido em device (desktop ~20-25 ms como referência frouxa) |
| NF-02 (NLI) | < 1 s / par | ⛔ N/A — NLI não converteu |
| NF-05 (tamanho app) | < 500 MB | ⚠️ Parcial: embeddings INT8 = 113 MB; NLI desconhecido (não converteu) |
| NF-06 (RAM pico) | < 1 GB | ⛔ não medido (sem device) |
| iOS mínimo (§7.3 #9) | a definir | Para o que converteu: **iOS 16** (alvo usado na conversão, com pesos INT8, roda). Pipeline completo depende de resolver o NLI. |

## Versão mínima de iOS

O modelo de embeddings foi convertido com
`minimum_deployment_target = ct.target.iOS16` (mlprogram + pesos INT8 via
`ct.optimize.coreml`) e roda. Logo, **iOS 16 é suficiente** para o caminho de
embeddings. Não dá para fechar o iOS mínimo do **pipeline completo** enquanto o
NLI não converter. O app principal hoje mira iOS 17 (`project.yml`), o que
cobre iOS 16 com folga.

---

## Arquivos deste spike

- `convert_embeddings.py` / `convert_nli.py` — conversão + quantização.
- `validate_embeddings.py` — confirma que o Core ML de embeddings bate com o PyTorch.
- `coreml_shims.py` — shims de versão (só necessários no torch 2.13; documentado).
- `requirements-pinned.txt` — toolchain alinhado (torch 2.7 etc.).
- `xcode-bench/` — app de medição de latência (rodar em iPhone real; ver README).
- `build/` — `.mlpackage` gerados (git-ignored; grandes).

## Reproduzir
```sh
cd spikes/02-coreml-latencia
python3 -m venv .venv && ./.venv/bin/pip install -r requirements-pinned.txt
./.venv/bin/python convert_embeddings.py   # gera build/Embeddings_{fp16,int8}.mlpackage
./.venv/bin/python validate_embeddings.py  # confirma cos≈1.0 vs PyTorch
./.venv/bin/python convert_nli.py          # FALHA esperada: 'pythonop' (XSoftmax)
```

---

## Medição com Xcode Completo

**Data:** 2026-07-24
**Objetivo:** retomar o Spike 2 agora que o ambiente tem Xcode 26.6 completo
(`xcodebuild`, `simctl`, `devicectl`) — gerar os dois `.mlpackage` definitivos
(DT-18), rodar o harness `xcode-bench/` de verdade e medir NF-01/NF-02/NF-06 e o
iOS mínimo (§7.3 #9). Não editou `spec.md`, não avançou para o Spike 4, não
resolveu nenhum `[EM ABERTO]` — só mede e documenta.

> **Veredito rápido:** Embeddings ✅ passa com folga em NF-01 e NF-06 em device
> real. **NLI ❌ bloqueado num ponto novo e mais grave que o Spike 2/2b haviam
> encontrado**: o `.mlpackage` patchado **converte e carrega**, mas **não
> executa uma única inferência com sucesso** em nenhum ambiente testado (device
> físico em duas configurações de `computeUnits`, e simulador). NF-02 não pôde
> ser medido. Isso não estava capturado no Spike 2b, que só validou que a
> conversão não lançava erro — nunca chegou a rodar o `.mlpackage` resultante.

### O que foi gerado

- `spikes/02b-alternativas-nli/convert_nli_final.py` (novo): reaproveita a
  classe `XSoftmaxPatched` e a lógica de trace/monkeypatch já escritas e
  verificadas em `patch_deberta.py` (não reabre a escolha do modelo), finaliza
  o artefato — quantiza INT8 e salva no caminho que `xcode-bench` espera.
  Reconfirma a equivalência do patch imediatamente antes de converter:
  `max|Δlogit|=0.000e+00`, `cos=1.000000` (idêntico ao que o Spike 2b já
  havia medido).
- `spikes/02-coreml-latencia/build/`:
  - `Embeddings_int8.mlpackage` — 113,2 MB (já existia do Spike 2, reaproveitado).
  - `NLI_int8.mlpackage` — **275,9 MB** (novo).
- `xcode-bench/` recebeu 3 alterações pontuais, todas no harness de medição
  (não no modelo nem no app principal):
  - `Benchmark.swift`: amostragem de RAM residente via `mach_task_basic_info`
    (antes do warmup e a cada inferência), reportando o pico — cobre NF-06.
  - `ContentView.swift`: auto-run no `onAppear` (mantendo o botão manual) e
    publicação do resultado de cada modelo assim que fica pronto, em vez de
    esperar os dois — necessário porque o NLI trava por minutos ou morre antes
    de terminar (ver abaixo), o que impedia até o resultado do Embeddings de
    aparecer.
  - `CoreMLBenchApp.swift`: `setbuf(stdout, nil)` — sem isso, a saída do
    `print()` ficava presa no buffer do processo e se perdia quando o app
    morria antes de um flush natural.

### Ambientes usados

- **Simulador:** iPhone 16 Pro, iOS 18.6.
- **Device físico:** iPhone 16 (`iPhone17,3`), iOS 26.3.1, pareado e
  disponível (`br-NKHFRW9FDY`) — atende ao piso "iPhone 13 ou superior" de
  NF-01/NF-02. Build assinado com o certificado de desenvolvimento already
  presente no keychain (`Apple Development: Henrique Silveira`).
- `computeUnits = .all` (ANE/GPU/CPU, o padrão do harness) foi tentado
  primeiro; travou/crashou (ver NLI abaixo). As medições finais usam
  `computeUnits = .cpuOnly` para conseguir números válidos onde possível —
  ainda uma medição honesta de inferência real, só que num backend específico.

### Embeddings — `paraphrase-multilingual-MiniLM-L12-v2` (INT8, 113 MB)

| Ambiente | mediana | média | min | max | RAM pico (sessão) |
|---|---|---|---|---|---|
| iPhone 16 físico, iOS 26.3.1, `.cpuOnly` (run 1) | 7,27 ms | 7,23 ms | 6,97 ms | 7,38 ms | 98,9 MB |
| iPhone 16 físico, iOS 26.3.1, `.cpuOnly` (run 2) | 7,09 ms | 7,10 ms | 6,98 ms | 7,29 ms | 107,9 MB |
| Simulador iPhone 16 Pro, iOS 18.6, `.cpuOnly` | 93,0 ms | 93,6 ms | 90,7 ms | 123,9 ms | 2233 MB* |

\* RAM do simulador não é comparável à de device real — o simulador roda o
processo como um binário macOS host com overhead próprio (não reflete o
runtime iOS real). Tratar só o número de device físico como válido para NF-06.

**NF-01 (< 150 ms): PASSA** em device real com folga grande (7 ms, ~21x abaixo
do alvo). No simulador também passa (93 ms), mas a margem é bem menor —
esperado, pois o simulador não tem Neural Engine e a CPU-only path ali é mais
lenta que no device.

Repetido 2x em device físico (reinstalação limpa entre execuções) com
resultados consistentes (diferença < 0,2 ms na mediana).

### NLI — `mDeBERTa-v3-base-xnli` patchado (INT8, 276 MB) — **BLOQUEADO EM RUNTIME**

O modelo **converte** (Spike 2b) e o `.mlpackage` **carrega no app** (o
`MLModel.compileModel`/mmap do `NLI_int8.mlmodelc` completa sem erro — visto
nos logs unificados do simulador). O bloqueio é **na predição**:

| Ambiente | `computeUnits` | Resultado |
|---|---|---|
| iPhone 16 físico, iOS 26.3.1 | `.all` | **Crash** (`SIGABRT`, signal 6). Log: `MetalPerformanceShadersGraph/MPSGraphExecutable.mm:5036: failed assertion 'Error: MLIR pass manager failed'`. |
| iPhone 16 físico, iOS 26.3.1 | `.cpuOnly` | **Falha controlada**, reproduzida identicamente em 2 execuções: `Error Domain=com.apple.CoreML Code=0 "Unable to compute the prediction using ML Program..." NSUnderlyingError=... "E5RT: Error(s) occurred executing a BNNS Op: (No messages were received from the BNNS graph context log callback. Please file a radar on BasicNeuralNetworkSubroutines...)"`. |
| Simulador iPhone 16 Pro, iOS 18.6 | `.cpuOnly` | O processo **morre sem completar a inferência** — em 3 tentativas: uma travou consumindo CPU por ~7 min antes de ser encerrada pelo sistema sem gerar crash log; as outras morreram silenciosamente após alguns segundos/minutos de computação (RAM do processo chegando a >5 GB antes de terminar). Nenhuma mensagem de erro específica foi capturável no console. |

**NF-02 (< 1 s): NÃO MEDIDO.** Não há como medir latência de um modelo que não
completa uma única predição. Pela mesma razão, a **RAM de pico do NLI durante
inferência real também não pôde ser medida** (NF-06 fica incompleto: só o
componente de embeddings foi confirmado dentro do alvo).

**Por que isso é uma descoberta nova, não uma repetição do Spike 2b:** o Spike
2b validou (a) equivalência numérica do patch em **PyTorch** (cos=1,0) e (b)
que `ct.convert(...)` **não lança exceção** — nunca chegou a chamar
`.predict()`/`MLModel.prediction` no `.mlpackage` resultante, nem em
coremltools no desktop nem em device. "Converte sem erro" e "executa
corretamente" acabaram sendo coisas diferentes para este modelo. Um candidato
a causa raiz (não investigada a fundo, registrada só como pista): o aviso
visto durante a conversão — `Core ML embedding (gather) layer does not
support any inputs besides the weights and indices. Those given will be
ignored.` — é suspeito para a atenção desentrelaçada do DeBERTa, que usa
gather com informação de posição relativa além de pesos+índices; se esse
argumento extra foi mesmo descartado na conversão, o grafo convertido pode
estar semanticamente incorreto, o que é consistente com falhar na execução
(BNNS/MPSGraph) em vez de na conversão.

### Comparação com os alvos da spec

| Meta | Alvo | Status |
|---|---|---|
| NF-01 (embeddings) | < 150 ms/chunk | ✅ **Passa** — 7 ms em device real (iPhone 16) |
| NF-02 (NLI) | < 1 s/par | ⛔ **Não medido** — modelo não executa uma predição sequer em nenhum ambiente testado |
| NF-05 (tamanho app) | < 500 MB | ⚠️ Parcial, como já registrado: 113 + 276 = 389 MB cabe no alvo *se* o NLI vier a funcionar; tamanho não é o problema agora |
| NF-06 (RAM pico) | < 1 GB | ⚠️ Parcial: embeddings sozinho em device real = ~100 MB (bem dentro do alvo); RAM do pipeline completo (com NLI executando) continua desconhecida |

### Versão mínima de iOS (§7.3 #9) — ainda não resolvido

Confirmado **empiricamente** (não só por `minimum_deployment_target` de
compilação):
- **iOS 18.6** (simulador) — embeddings roda.
- **iOS 26.3.1** (device físico) — embeddings roda.

**Não foi possível testar iOS 17 ou 16 neste ambiente**: `xcrun simctl runtime
list` e `xcodebuild -downloadPlatform` confirmam que este Xcode 26.6 só
oferece runtimes de simulador iOS 18.6 e 26.x para download — não é uma
escolha, é uma limitação do ambiente. Isso não é uma resposta ao item
`[EM ABERTO]` §7.3 #9; é só o que deu para confirmar por execução real. Além
disso, como o NLI não executa em nenhum ambiente testado, a pergunta "qual o
iOS mínimo do **pipeline completo**" segue sem sentido prático até o bloqueio
do NLI ser resolvido — é secundária a esse problema maior.

### O que esta tarefa NÃO fez (limites respeitados)

- Não editou `spec.md`.
- Não implementou nada do app principal.
- Não avançou para o Spike 4 (scraping do DDG).
- **Não tentou contornar/otimizar o bloqueio do NLI** (ex.: mexer mais na
  arquitetura do patch, tentar outro modo de quantização, tentar outros
  `computeUnits` além de `.all`/`.cpuOnly`) — por instrução explícita, isso é
  documentado e parado aqui, não resolvido por conta própria.
- Não resolveu nenhum item `[EM ABERTO]` da spec.

### Recomendação (proposta, não decisão)

O bloqueio de runtime do NLI é mais sério que o bloqueio de conversão que o
Spike 2b endereçou: significa que **nenhum dos candidatos avaliados até agora
foi de fato comprovado rodando em Core ML real** — nem o Caminho 1 (mDeBERTa
patchado, testado aqui e bloqueado) nem o Caminho 2 (MiniLMv2 L6/L12, que no
Spike 2b só foram comparados ao PyTorch via coremltools no **desktop**, nunca
executados em device/simulador). Antes de reabrir a escolha do modelo de NLI
(§7.3 #1, já reaberta uma vez pelo Spike 2b), sugiro que qualquer candidato
futuro seja testado neste mesmo harness (`.predict()` real em device, não só
"converteu sem erro") como critério de aceite — do contrário o mesmo problema
pode se repetir com outro modelo. Fica para você decidir como prosseguir.
