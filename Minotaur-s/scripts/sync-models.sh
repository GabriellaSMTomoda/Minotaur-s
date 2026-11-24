#!/usr/bin/env bash
# Restaura os modelos Core ML validados em Minotaur-s/Resources/Models, sem baixar nem treinar.
#
# Fontes, em ordem:
#   1. $MINOTAURS_MODEL_BACKUP (padrão ~/Library/Application Support/Minotaur-s/models/...),
#      se contiver NLI.mlmodelc e Embeddings.mlmodelc completos;
#   2. o próprio repositório: arquivos pequenos em Resources/Models + pesos remontados
#      a partir de model-parts/*.part* (o GitHub rejeita arquivos > 100 MB).
# Tudo é verificado por SHA-256 (VerificationModelManifest.json) em staging antes de substituir.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESOURCES="$ROOT/Minotaur-s/Resources"
PARTS="$ROOT/model-parts"
BACKUP="${MINOTAURS_MODEL_BACKUP:-$HOME/Library/Application Support/Minotaur-s/models/bertimbau-base-plue-spike9}"
VERIFY=(/usr/bin/python3 "$ROOT/scripts/verify-model-assets.py")

# Já íntegro: nada a fazer.
if "${VERIFY[@]}" --resources "$RESOURCES" >/dev/null 2>&1; then
  echo "OK. Modelos já instalados e verificados."
  exit 0
fi

mkdir -p "$RESOURCES"
STAGING="$(mktemp -d "$RESOURCES/.model-restore.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
mkdir -p "$STAGING/Models"
ln -s "$RESOURCES/Tokenizers" "$STAGING/Tokenizers"
ln -s "$RESOURCES/Verification" "$STAGING/Verification"

if [ -d "$BACKUP/NLI.mlmodelc" ] && [ -d "$BACKUP/Embeddings.mlmodelc" ]; then
  echo "Restaurando do backup local: $BACKUP"
  for model in NLI Embeddings; do
    cp -R "$BACKUP/$model.mlmodelc" "$STAGING/Models/$model.mlmodelc"
  done
else
  echo "Remontando pesos a partir de model-parts/ ..."
  for model in NLI Embeddings; do
    src="$RESOURCES/Models/$model.mlmodelc"
    dst="$STAGING/Models/$model.mlmodelc"
    if [ ! -f "$src/model.mil" ]; then
      echo "Arquivos de $model.mlmodelc ausentes no checkout ($src)." >&2
      echo "Faça git pull/checkout completo ou aponte MINOTAURS_MODEL_BACKUP para um conjunto validado." >&2
      exit 1
    fi
    # Tudo menos o weight.bin (versionado fatiado).
    cp -R "$src" "$dst"
    mkdir -p "$dst/weights"
    rm -f "$dst/weights/weight.bin"
    parts=("$PARTS/$model.weight.bin.part"*)
    if [ ! -e "${parts[0]}" ]; then
      echo "Partes dos pesos ausentes: $PARTS/$model.weight.bin.part*" >&2
      exit 1
    fi
    cat "${parts[@]}" > "$dst/weights/weight.bin"
  done
fi

# Verifica antes de substituir; um restore interrompido ou corrompido nunca chega ao bundle.
"${VERIFY[@]}" --resources "$STAGING"
rm -rf "$RESOURCES/Models"
mv "$STAGING/Models" "$RESOURCES/Models"
echo "OK. Embeddings e NLI validados restaurados para o bundle."
