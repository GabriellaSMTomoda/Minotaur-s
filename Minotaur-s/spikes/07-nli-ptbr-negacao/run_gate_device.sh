#!/bin/bash
# SPIKE 7 — FILTRO 2: build + install + run do harness no iPhone FÍSICO.
#
# Este é o gate que o mDeBERTa não passou: "converte" e "logits batem no
# desktop" não implicaram execução em device. Aqui o app roda .predict() de
# verdade e compara os logits com a referência PyTorch do manifest.
#
# UM MODELO POR VEZ, por necessidade e não por elegância: os três .mlpackage
# somam ~900 MB e o device não tem espaço para instalá-los juntos
# (IXUserPresentableErrorDomain 11, "Insufficient storage"). O script gera um
# project.yml com um único modelo, instala, roda e DESINSTALA antes do próximo.
# Efeito colateral bom: se um candidato derrubar o processo, os outros já
# rodaram — é a mesma lição do Spike 2 (.all crashou o NLI e levou o run junto).
#
# Requer conta Apple logada no Xcode (Settings > Accounts) para assinatura
# automática.
#
# Uso:
#   ./run_gate_device.sh                          # todos, um por vez
#   ./run_gate_device.sh inferbr                  # só um candidato
set -uo pipefail

DEVICE_ID="EFEE75FC-18B6-5948-BC37-9F9A6AA0C0F8"   # br-NKHFRW9FDY (iPhone 16)
TEAM="2DK23BZ7KB"
BUNDLE="com.spike.coremlbench7"
HERE="$(cd "$(dirname "$0")" && pwd)"
BENCH_ROOT="$HERE/xcode-bench"
SCRATCH="${SCRATCH_DIR:-/private/tmp/spike07}"
DD="$SCRATCH/dd-dev-auto"
OUT="$HERE/device_results_iphone.log"

mkdir -p "$SCRATCH"

MODELOS=("$@")
[ ${#MODELOS[@]} -eq 0 ] && MODELOS=(inferbr plue_bertimbau plue_xlmr)

: > "$OUT"

for MODELO in "${MODELOS[@]}"; do
  echo ""
  echo "############ $MODELO ############"
  LOG="$SCRATCH/device_run_$MODELO.log"

  # project.yml com UM .mlpackage — é o que cabe no device.
  cat > "$BENCH_ROOT/project.yml" <<EOF
# GERADO POR run_gate_device.sh — não editar à mão.
# Um modelo por projeto: os três .mlpackage juntos não cabem no device.
name: CoreMLBench7
options:
  bundleIdPrefix: com.spike.coremlbench7
targets:
  CoreMLBench7:
    type: application
    platform: iOS
    deploymentTarget: "16.0"
    sources:
      - path: Sources
      - path: ../build/manifest.json
        buildPhase: resources
      - path: ../build/${MODELO}_int8.mlpackage
        buildPhase: resources
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.spike.coremlbench7
        GENERATE_INFOPLIST_FILE: YES
        INFOPLIST_KEY_UILaunchScreen_Generation: YES
        SWIFT_VERSION: "5.0"
        TARGETED_DEVICE_FAMILY: "1"
EOF

  echo "=== [0/4] xcodegen ($MODELO) ==="
  (cd "$BENCH_ROOT" && xcodegen generate) >/dev/null || { echo "xcodegen falhou"; continue; }

  echo "=== [1/4] build ==="
  rm -rf "$DD/Build/Products"
  xcodebuild -project "$BENCH_ROOT/CoreMLBench7.xcodeproj" -scheme CoreMLBench7 \
    -sdk iphoneos -configuration Release \
    -destination "platform=iOS,id=$DEVICE_ID" -derivedDataPath "$DD" \
    DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_STYLE=Automatic \
    -allowProvisioningUpdates build 2>&1 | tail -3
  APP=$(find "$DD/Build/Products" -name '*.app' -maxdepth 3 2>/dev/null | head -1)
  [ -z "$APP" ] && { echo "BUILD FALHOU (sem .app)"; continue; }

  echo "=== [2/4] install ==="
  xcrun devicectl device install app --device "$DEVICE_ID" "$APP" 2>&1 | tail -3

  echo "=== [3/4] launch (.cpuOnly e .all) ==="
  : > "$LOG"
  for UNITS in cpuOnly all; do
    xcrun devicectl device process launch --console --terminate-existing \
      --device "$DEVICE_ID" \
      -e "{\"BENCH_UNITS\":\"$UNITS\",\"BENCH_MODEL\":\"$MODELO\"}" \
      "$BUNDLE" >> "$LOG" 2>&1
    echo "  $UNITS -> exit $?"
  done
  grep 'BENCHLINE' "$LOG" | tee -a "$OUT"

  echo "=== [4/4] uninstall (libera espaço para o próximo) ==="
  xcrun devicectl device uninstall app --device "$DEVICE_ID" "$BUNDLE" 2>&1 | tail -1
done

echo ""
echo "=== TODOS OS BENCHLINEs ==="
cat "$OUT"
echo "(resultados em $OUT)"
