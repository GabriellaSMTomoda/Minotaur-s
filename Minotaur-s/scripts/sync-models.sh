#!/usr/bin/env bash
# Restore the checksum-locked compiled baseline, without downloading or training.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESOURCES="$ROOT/Minotaur-s/Resources"
BACKUP="${MINOTAURS_MODEL_BACKUP:-$HOME/Library/Application Support/Minotaur-s/models/bertimbau-base-plue-spike9}"

if [ ! -d "$BACKUP/NLI.mlmodelc" ] || [ ! -d "$BACKUP/Embeddings.mlmodelc" ]; then
  echo "Backup validado não encontrado: $BACKUP" >&2
  echo "Conferindo os modelos já instalados no projeto..." >&2
  /usr/bin/python3 "$ROOT/scripts/verify-model-assets.py" --resources "$RESOURCES"
  exit 0
fi

# Verify before replacing either model; an interrupted/bad restore cannot ship.
STAGING="$(mktemp -d "$RESOURCES/.model-restore.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
mkdir -p "$STAGING/Models"
ln -s "$RESOURCES/Tokenizers" "$STAGING/Tokenizers"
ln -s "$RESOURCES/Verification" "$STAGING/Verification"
for model in NLI Embeddings; do
  cp -R "$BACKUP/$model.mlmodelc" "$STAGING/Models/$model.mlmodelc"
done
/usr/bin/python3 "$ROOT/scripts/verify-model-assets.py" --resources "$STAGING"
rm -rf "$RESOURCES/Models"
mv "$STAGING/Models" "$RESOURCES/Models"
echo "OK. Embeddings e NLI validados restaurados para o bundle."
