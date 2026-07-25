#!/bin/bash
# SPIKE 2c — build + install + run do harness no iPhone FÍSICO (Filtro 2).
# Requer: conta Apple logada no Xcode (Settings > Accounts) para assinatura
# automática. Rode DEPOIS de logar a conta.
#
# Uso:
#   ./run_bench_device.sh                 # build + roda tudo (.cpuOnly e .all)
#   ./run_bench_device.sh cpuOnly L6      # só um combo (isola crash)
set -uo pipefail

DEVICE_ID="EFEE75FC-18B6-5948-BC37-9F9A6AA0C0F8"   # br-NKHFRW9FDY (iPhone 16)
TEAM="2DK23BZ7KB"                                   # conta logada; perfil wildcard cobre o device
BUNDLE="com.spike.coremlbench"
BENCH_ROOT="/Users/henriquelacerdasilveira/Documents/Academy/Minotaur-s/Minotaur-s/spikes/02-coreml-latencia/xcode-bench"
SCRATCH="/private/tmp/claude-502/-Users-henriquelacerdasilveira-Documents-Academy-Minotaur-s-Minotaur-s/dcd2497b-cab3-44db-81e6-d8710951bedf/scratchpad"
DD="$SCRATCH/dd-dev-auto"
LOG="$SCRATCH/device_run.log"
OUT="$(dirname "$0")/device_results_iphone.log"

UNITS="${1:-}"      # opcional: cpuOnly | all
MODEL="${2:-}"      # opcional: L6 | L12 | symanto | erniem

echo "=== [1/3] build (assinatura automática, team $TEAM) ==="
xcodebuild -project "$BENCH_ROOT/CoreMLBench.xcodeproj" -scheme CoreMLBench \
  -sdk iphoneos -configuration Release \
  -destination "platform=iOS,id=$DEVICE_ID" -derivedDataPath "$DD" \
  DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_STYLE=Automatic \
  -allowProvisioningUpdates build 2>&1 | tail -6
APP=$(find "$DD/Build/Products" -name '*.app' -maxdepth 3 2>/dev/null | head -1)
[ -z "$APP" ] && { echo "BUILD FALHOU (sem .app). Verifique a conta/assinatura."; exit 1; }
echo "app: $APP"

echo "=== [2/3] install no device ==="
xcrun devicectl device install app --device "$DEVICE_ID" "$APP" 2>&1 | tail -3

echo "=== [3/3] launch (console, app sai sozinho após o run) ==="
: > "$LOG"
ENVJSON="{}"
[ -n "$UNITS" ] && ENVJSON=$(printf '{"BENCH_UNITS":"%s"' "$UNITS")
[ -n "$UNITS" ] && [ -n "$MODEL" ] && ENVJSON="$ENVJSON,\"BENCH_MODEL\":\"$MODEL\""
[ -n "$UNITS" ] && ENVJSON="$ENVJSON}"
echo "env: $ENVJSON"
xcrun devicectl device process launch --console --terminate-existing \
  --device "$DEVICE_ID" -e "$ENVJSON" "$BUNDLE" > "$LOG" 2>&1
echo "launch exit: $?"

echo "=== BENCHLINEs ==="
grep 'BENCHLINE' "$LOG" | tee -a "$OUT"
echo "(log completo: $LOG ; resultados salvos em $OUT)"
