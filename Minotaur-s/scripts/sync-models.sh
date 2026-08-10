#!/usr/bin/env bash
#
# Copia os modelos Core ML dos spikes para o bundle do app.
#
# Os .mlpackage não são versionados: os weight.bin excedem o limite de arquivo do GitHub.
# 100 MB por arquivo do GitHub. Quem clona o repositório roda este script uma vez antes do
# primeiro build; sem ele, EmbeddingService/NLIService falham com `.modelLoadFailed` (RF-10.3).
#
# Os modelos vêm dos spikes que foram validados em device físico:
#   - embeddings: paraphrase-multilingual-MiniLM-L12-v2 INT8 (cos=0,9999 vs PyTorch, 7 ms)
#   - NLI:        BERTimbau-base fine-tuned PLUE/MNLI INT8 (Spike 9, .cpuOnly)
#
# Uso:  ./scripts/sync-models.sh

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$ROOT/Minotaur-s/Resources/Models"

EMBEDDINGS_SRC="$ROOT/spikes/02-coreml-latencia/build/Embeddings_int8.mlpackage"
NLI_SRC="$ROOT/spikes/09-nli-base-search/build/trained/bertimbau_base_plue_dynamic512_int8.mlpackage"

copy_model() {
  local src="$1" dest="$2" label="$3"

  if [ ! -d "$src" ]; then
    echo "ERRO: modelo de $label não encontrado em:" >&2
    echo "  $src" >&2
    echo "" >&2
    echo "Rode a conversão do spike correspondente antes:" >&2
    echo "  spikes/02-coreml-latencia/convert_embeddings.py   (embeddings)" >&2
    echo "  spikes/09-nli-base-search/convert_trained_model.py (NLI selecionado)" >&2
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
