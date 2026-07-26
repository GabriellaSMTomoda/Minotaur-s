# Minotaur-s

## Antes do primeiro build

```bash
./scripts/sync-models.sh
```

Copia os modelos Core ML já convertidos de:
- `spikes/02-coreml-latencia/build/Embeddings_int8.mlpackage`
- `spikes/02c-nli-executavel/build/L6_int8.mlpackage`

para `Minotaur-s/Resources/Models/{Embeddings,NLI}.mlpackage`.

Esses `.mlpackage` (113 MB + 103 MB) não são versionados no git — os `weight.bin` excedem o
limite de 100 MB por arquivo do GitHub (ver `.gitignore` e DT-31 em `spec.md`). Sem esse passo,
`EmbeddingService`/`NLIService` falham com `.modelLoadFailed` (RF-10.3).

## Tokenizers (`Resources/Tokenizers/`)

Diferente dos `.mlpackage`, os arquivos de tokenizer **já estão versionados no git** — nenhum
passo manual é necessário em um clone normal.

`spikes/07-tokenizer-parity/export_assets.py` só precisa ser rodado de novo se houver suspeita
de drift (ex.: versão do `transformers` mudou, ou o modelo upstream no Hugging Face mudou).
Reutiliza o venv do Spike 2:

```bash
cd spikes/07-tokenizer-parity
../02-coreml-latencia/.venv/bin/python export_assets.py
```

A validação real de que os tokenizers estão corretos é o `TokenizerParityTests` (Swift/Xcode)
rodando contra `parity_fixture.json` — a simples existência dos arquivos não garante nada.

## Limitação conhecida

`sync-models.sh` depende dos builds dos spikes 2 e 2c já existirem localmente:
- `spikes/02-coreml-latencia/build/Embeddings_int8.mlpackage`
- `spikes/02c-nli-executavel/build/L6_int8.mlpackage`

Em uma máquina nova, sem esses spikes já buildados, o script falha com uma mensagem apontando
para rodar `convert_embeddings.py` (spike 02) e `convert_and_reference.py` (spike 02c) antes.
Essa dependência não está automatizada — é uma limitação conhecida, não corrigida neste
momento.
