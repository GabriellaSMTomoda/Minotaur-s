# NLI v2 — retreino local do BERTimbau-base

Pipeline para retreinar o NLI do Verificador no Mac (MPS, FP32, sem custo
externo), partindo de `neuralmind/bert-base-portuguese-cased` na revisão
`94d69c95f98f7d5b2a8700c420230ae10def0baa`, porque o checkpoint PyTorch do
Spike 9 está perdido. **O treino completo ainda não foi executado.** Só o smoke
de 24/11/2026 descrito abaixo rodou. Nenhuma métrica de qualidade foi medida.

| Arquivo | Papel |
|---|---|
| `../train_nli_v2.py` | prepara os dados, treina, seleciona e salva estado retomável |
| `evaluate_nli_v2.py` | avalia um checkpoint nas 15 regressões, no PLUE dev e no hold-out 2mil7 |
| `pyproject.toml` | ambiente `uv`: Python 3.11, torch 2.7.0, transformers 4.46.3 (as versões do Spike 9), pyarrow. Extra `convert`: coremltools 9.0 |
| `build/` | dados, checkpoints e logs, ignorado pelo Git |

## Dados

| Fonte | Pares de treino* | Observação |
|---|---:|---|
| PLUE/MNLI v1.0.0 `train.tsv` | 391.497 | mesmo release/MD5 do Spike 9; 40 hipóteses vazias excluídas |
| 2mil7 `pt_mnli` | 23.516 | amostra do MNLI train, logo **as mesmas origens inglesas do PLUE** com outra tradução (reforça 25 mil pares; não serve como hold-out) |
| 2mil7 `pt_fever` | 23.945 | FEVER-NLI (verificação de fatos) |
| 2mil7 `pt_anli` | 23.982 | ANLI R1–R3, premissas mais longas (média de 94 tokens) |
| 2mil7 `pt_ling` | 3.997 | LingNLI |
| 2mil7 `pt_wanli` | 23.964 | WANLI |
| **Total** | **490.901** | digest `74b1f164…1961a` |

\* Depois dos filtros, com os padrões. O 2mil7 é
`MoritzLaurer/multilingual-NLI-26lang-2mil7` na revisão fixa
`510a2339…0538`. Os cinco parquets `pt_*` somam 36 MB e têm o SHA-256
conferido contra o oid LFS do Hub. Os rótulos 0/1/2 do dataset já seguem a
ordem do app.

Filtros, todos contados em `training_manifest.json` → `data.filters`:

- **Textos protegidos.** Premissa ou hipótese igual, após NFKC, casefold,
  espaços e pontuação das bordas, a qualquer texto de
  `data/known_regressions.jsonl` ou `data/dev_claims.jsonl`. Isso inclui os
  campos `premise`, `hypothesis`, `claim` e `text`. Textos protegidos com 40
  caracteres ou mais também são procurados como substring. Vale para treino,
  dev e hold-out. Hoje são 139 textos. Saiu um par, do WANLI: "Ele disse que a
  terra era plana." → "A terra é plana.". Outros arquivos podem ser passados
  com `--protected`.
- **Sem vazamento.** Ficam fora do treino os pares e as premissas que
  aparecem no PLUE dev ou no hold-out (968 pares).
- **Duplicatas.** Para o mesmo par normalizado, fica a primeira ocorrência: o
  PLUE vence o 2mil7, e um rótulo gold vence o silver. Pares com rótulos gold
  conflitantes são descartados (341 pares).

O hold-out tem 1.000 pares por fonte, separados por grupo de premissa original
para não dividir grupos. Ele sai de FEVER, ANLI, LingNLI e WANLI, num total de
4.002 pares, e é gravado em `heldout_2mil7.jsonl`. O hold-out é reportado a
cada época, mas fica **fora da seleção** por padrão. A opção
`--selection plue+heldout` seleciona pela média dos dois.

**Silver (opcional).** Passe `--silver ../artifacts/silver_nli.jsonl`
explicitamente. O arquivo não é incluído automaticamente. Cada linha tem
`{"premise", "hypothesis", "label"}`, com `label` como nome ou como 0/1/2.
O loss de cada exemplo silver é multiplicado por `--silver-weight` (padrão
0,5; com 0, o silver fica fora). O SHA-256 do arquivo vai para o manifesto, e
os filtros acima também se aplicam a ele.

## Protocolo (igual ao Spike 9)

AdamW, LR 2e-5 com schedule linear e warm-up de 10%, weight decay 0,01, clip
1,0, microbatch 16 × acumulação 2 (batch efetivo 32), 3 épocas, `max_len`
256, seed 42 e FP32. Os lotes são agrupados por comprimento, com padding
múltiplo de 32, e o cache MPS é liberado a cada 100 updates. Rótulos: 0
entailment, 1 neutral, 2 contradiction. O checkpoint é escolhido pelo maior
macro-F1 no PLUE `dev_matched` (9.815 pares), com o loss como desempate. As
regressões não entram no treino nem na seleção.

Para retomar, o script grava `build/<run>/state/train_state.pt` (modelo,
otimizador, scheduler, RNG e posição exata no lote) a cada `--save-every`
updates (padrão 1.000, cerca de 11 min), ao fim de cada época e ao receber
Ctrl-C ou SIGTERM. Nesses dois sinais, ele salva no próximo update e sai com
código 3. Com `--resume`, o script recusa retomar se os digests dos dados, os
hiperparâmetros ou o schedule tiverem mudado. Ao concluir, o estado é
apagado; use `--keep-state` para mantê-lo.

O manifesto e o `train.log` registram o SHA-256 e o MD5 de cada arquivo de
origem, os digests SHA-256 dos conjuntos finais (treino, dev e hold-out), as
contagens por fonte e rótulo, a revisão do modelo base e as versões do
runtime.

## Comandos

Todos partem de `Minotaur-s/evaluation/`:

```bash
uv sync --project nli_v2 --python 3.11 --extra convert
```

1) Preparar os dados e estimar o tempo, sem treinar (cerca de 1 min):

```bash
uv run --project nli_v2 python train_nli_v2.py --prepare-only --estimate --output-dir nli_v2/build/prepare
```

2) Treino completo. `caffeinate` impede o Mac de dormir; o log também vai para
`nli_v2/build/train/train.log`:

```bash
caffeinate -dims uv run --project nli_v2 python train_nli_v2.py --output-dir nli_v2/build/train
```

3) Depois de uma interrupção, repetir o comando com `--resume`:

```bash
caffeinate -dims uv run --project nli_v2 python train_nli_v2.py --output-dir nli_v2/build/train --resume
```

4) Avaliar o checkpoint selecionado (regressões + PLUE dev + hold-out, com
matrizes de confusão; `max_length` 512, como no app):

```bash
uv run --project nli_v2 python nli_v2/evaluate_nli_v2.py --checkpoint nli_v2/build/train/checkpoint-best --output nli_v2/build/train/evaluation.json
```

5) Exportar para Core ML com o conversor do Spike 9, **sem modificação**. Ele
lê `model_version` de `training_summary.json`, que traz
`bertimbau-base-nli-v2` no treino completo e `bertimbau-base-nli-v2-smoke`
em qualquer execução com `--max-*`. O conversor também confere `status:
COMPLETE` e `selected_checkpoint`, quantiza para INT8 e grava a paridade
PyTorch × Core ML. Rodar a partir da raiz do app (`Minotaur-s/`):

```bash
uv run --project evaluation/nli_v2 --extra convert python spikes/09-nli-base-search/convert_trained_model.py --checkpoint evaluation/nli_v2/build/train/checkpoint-best --output-dir evaluation/nli_v2/build/train/coreml
```

O pacote sai com o nome herdado `bertimbau_base_plue_dynamic512_int8.mlpackage`.
O que identifica a versão é o metadado. Para promover, seguir o
`evaluation/README.md` e o `CLAUDE.md`: sondas de ordem de rótulos, paridade,
RAM/latência em iPhone físico e regressões. Além disso, `VerificationModelManifest.json`
e `EvidencePolicy.json` precisam usar o mesmo `model_version`. Este pipeline
não substitui os modelos do app.

## Estimativa de tempo e disco do treino completo

**Tempo: cerca de 9 h, com faixa provável de 8,5 a 10 h**, no mesmo Mac do
Spike 9. A estimativa (`--estimate`) parte de duas medidas:

- o Spike 9 levou 23.333 s (6 h 29 min) para 3 épocas só de PLUE;
- o novo treino tem 1,336× mais tokens com padding por época (35,7 M contra
  26,7 M), porque ANLI e FEVER são mais longos.

Daí sai 31.266 s, cerca de 8 h 41 min. Somam-se 3 validações (PLUE dev +
hold-out, ~14 mil pares cada) e as gravações de estado (~6 s cada, umas 46 no
total). Como a atenção cresce mais que linearmente, sequências longas puxam
para cima. O smoke mediu 30–54 ex/s em regime, compatível com os 50,5 ex/s do
Spike 9. Resultam 30.682 lotes por época, ou 15.341 updates por época, ou
46.023 no total.

**Disco: reservar ≥ 5 GB livres** além do que já existe.

| Item | Tamanho |
|---|---:|
| `.venv` (já criado) | 0,58 GB |
| Dados (`build/data`, já baixados) | 0,44 GB |
| Modelo base no cache HF (já presente) | 0,44 GB |
| `state/train_state.pt` | 1,31 GB, **pico de 2,6 GB** durante a troca atômica |
| `checkpoint-best` | 0,44 GB |
| Export Core ML INT8 | 0,10 GB |
| Logs, métricas, hold-out | < 0,02 GB |
| **Pico novo durante o treino** | **≈ 3,2 GB** (cai para ≈ 0,55 GB ao concluir) |

A memória unificada do Mac de 24 GB comporta a configuração 16×2: o smoke
usou ~1,8 GB alocados e ~7 GB de driver MPS. O microbatch 32 do Spike 9
falhou por falta de memória; não usar.

## Smoke executado (24/11/2026)

Configuração: `--max-train-samples 500 --max-eval-samples 200 --max-steps 20
--save-every 5`, com interrupção forçada no update 12 e depois `--resume`.

- Download e validação dos dados: PLUE MD5/SHA-256 e os 5 parquets conferem.
- MPS: 20 updates em 40,5 s de treino. A retomada recomeçou no lote 24 da
  época 1 (update 12), o estado foi salvo nos updates 5, 10, 12 e 15 e na
  troca de época, a seleção ficou na época 1 e o status final foi `COMPLETE`.
- `evaluate_nli_v2.py`: rodou nas 15 regressões (3/15 aceitas), em 300 pares
  do PLUE dev (macro-F1 0,215) e no hold-out. Esses números são **esperados
  de um modelo quase aleatório** com 20 updates e não medem qualidade.
- Conversão Core ML sem alterar o conversor: metadado `model_version =
  bertimbau-base-nli-v2-smoke`, cosseno mínimo de paridade 0,99989, argmax
  idênticos e 104 MB em INT8.
- Os pesos do smoke foram apagados para liberar disco. Ficaram logs e JSONs
  em `build/smoke/`.
