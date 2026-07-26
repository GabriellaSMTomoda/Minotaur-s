#!/bin/bash
# SPIKE 4b — build + install + run do harness no iPhone FÍSICO.
# Mesmo padrão de signing/device de spikes/02c-nli-executavel/run_bench_device.sh
# (mesma conta/team já logada no Xcode).
#
# Uso:
#   ./run_device.sh                 # usa o DEVICE_ID default abaixo
#   ./run_device.sh <DEVICE_ID>     # roda em outro device físico
set -uo pipefail

DEVICE_ID="${1:-EFEE75FC-18B6-5948-BC37-9F9A6AA0C0F8}"   # br-NKHFRW9FDY (iPhone 16), mesmo device do Spike 2c
TEAM="2DK23BZ7KB"                                          # conta já logada; perfil wildcard cobre o device
BUNDLE="com.spike.ddgurlsession"
ROOT="$(cd "$(dirname "$0")" && pwd)"
SCRATCH="/private/tmp/claude-502/-Users-henriquelacerdasilveira-Documents-Academy-Minotaur-s-Minotaur-s/935cf48d-80ce-4aae-a710-690857abac0f/scratchpad"
DD="$SCRATCH/dd-ddgspike"
LOG="$SCRATCH/ddgspike_device_run.log"
OUT="$ROOT/device_run.log"

mkdir -p "$SCRATCH"

echo "=== [0/3] xcodegen generate ==="
(cd "$ROOT" && xcodegen generate) || { echo "xcodegen falhou"; exit 1; }

echo "=== [1/3] build (assinatura automática, team $TEAM) ==="
xcodebuild -project "$ROOT/DDGSpike.xcodeproj" -scheme DDGSpike \
  -sdk iphoneos -configuration Release \
  -destination "platform=iOS,id=$DEVICE_ID" -derivedDataPath "$DD" \
  DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_STYLE=Automatic \
  -allowProvisioningUpdates build 2>&1 | tail -20
APP=$(find "$DD/Build/Products" -name '*.app' -maxdepth 3 2>/dev/null | head -1)
[ -z "$APP" ] && { echo "BUILD FALHOU (sem .app). Verifique conta/assinatura/conexão do device."; exit 1; }
echo "app: $APP"

echo "=== [2/3] install no device ==="
xcrun devicectl device install app --device "$DEVICE_ID" "$APP" 2>&1 | tail -5

echo "=== [3/3] launch (console, app sai sozinho após o run) ==="
: > "$LOG"
xcrun devicectl device process launch --console --terminate-existing \
  --device "$DEVICE_ID" "$BUNDLE" > "$LOG" 2>&1
echo "launch exit: $?"

cp "$LOG" "$OUT"
echo "log completo salvo em: $OUT"
echo "=== JSON do resultado (entre marcadores) ==="
sed -n '/RESULTJSON_BEGIN/,/RESULTJSON_END/p' "$LOG"
