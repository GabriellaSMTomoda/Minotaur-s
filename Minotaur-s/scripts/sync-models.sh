#!/usr/bin/env bash
#
# Copia os modelos Core ML dos spikes para o bundle do app.
#
# Os .mlpackage não são versionados: os weight.bin têm 113 MB e 103 MB, acima do limite de
# 100 MB por arquivo do GitHub. Quem clona o repositório roda este script uma vez antes do
# primeiro build; sem ele, EmbeddingService/NLIService falham com `.modelLoadFailed` (RF-10.3).
#
# Os modelos vêm dos spikes 2 e 2c, que são a única fonte validada em device físico:
#   - embeddings: paraphrase-multilingual-MiniLM-L12-v2 INT8 (cos=0,9999 vs PyTorch, 7 ms)
#   - NLI:        multilingual-MiniLMv2-L6-mnli-xnli INT8 (cos=1,0 vs PyTorch, 2 ms .cpuOnly)
#
# Uso:  ./scripts/sync-models.sh

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$ROOT/Minotaur-s/Resources/Models"

EMBEDDINGS_SRC="$ROOT/spikes/02-coreml-latencia/build/Embeddings_int8.mlpackage"
NLI_SRC="$ROOT/spikes/02c-nli-executavel/build/L6_int8.mlpackage"

copy_model() {
  local src="$1" dest="$2" label="$3"

  if [ ! -d "$src" ]; then
    echo "ERRO: modelo de $label não encontrado em:" >&2
    echo "  $src" >&2
    echo "" >&2
    echo "Rode a conversão do spike correspondente antes:" >&2
    echo "  spikes/02-coreml-latencia/convert_embeddings.py   (embeddings)" >&2
    echo "  spikes/02c-nli-executavel/convert_and_reference.py (NLI)" >&2
    exit 1
  fi

  rm -rf "$dest"
  cp -R "$src" "$dest"
  echo "  $label -> $(basename "$dest") ($(du -sh "$dest" | cut -f1))"
}

mkdir -p "$DEST"

echo "Sincronizando modelos Core ML para $DEST"
copy_model "$EMBEDDINGS_SRC" "$DEST/Embeddings.mlpackage" "embeddings"
copy_model "$NLI_SRC" "$DEST/NLI.mlpackage" "NLI"
echo "OK."
