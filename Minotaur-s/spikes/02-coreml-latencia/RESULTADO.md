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
