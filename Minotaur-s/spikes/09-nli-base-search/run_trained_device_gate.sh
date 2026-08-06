#!/bin/bash
# Final physical-device measurement for the selected and trained checkpoint.
set -uo pipefail

DEVICE_ID="EFEE75FC-18B6-5948-BC37-9F9A6AA0C0F8"
TEAM="2DK23BZ7KB"
BUNDLE="com.spike.architecturegate9"
HERE="$(cd "$(dirname "$0")" && pwd)"
BENCH="$HERE/xcode-bench"
BUILD="$HERE/build"
SCRATCH="${SPIKE9_TRAINED_SCRATCH:-/private/tmp/spike09-trained-gate}"
OUT="$HERE/trained_device_results_iphone.log"
VARIANT="bertimbau_base_plue_dynamic512"
MODEL="$BUILD/trained/${VARIANT}_int8.mlpackage"

[ ! -d "$MODEL" ] && { echo "modelo treinado ausente: $MODEL" >&2; exit 1; }
[ ! -f "$BUILD/trained_device_fixture.json" ] && { echo "fixture treinado ausente" >&2; exit 1; }
mkdir -p "$SCRATCH"
if [ -s "$OUT" ]; then
  ATTEMPT_STAMP=$(date +%Y%m%dT%H%M%S)
  cp "$OUT" "$BUILD/trained_device_attempt_${ATTEMPT_STAMP}.log"
fi
: > "$OUT"
rm -f "$BUILD/NLI_Selected.mlpackage"
ln -s "$MODEL" "$BUILD/NLI_Selected.mlpackage"

echo "===== BUILD $VARIANT =====" | tee -a "$OUT"
(cd "$BENCH" && xcodegen generate) >/dev/null || exit 1
DD="$SCRATCH/dd-dynamic512"
rm -rf "$DD/Build/Products"
xcodebuild -project "$BENCH/ArchitectureGate9.xcodeproj" -scheme ArchitectureGate9 \
  -sdk iphoneos -configuration Release \
  -destination "platform=iOS,id=$DEVICE_ID" -derivedDataPath "$DD" \
  DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_STYLE=Automatic \
  -allowProvisioningUpdates build 2>&1 | tee -a "$OUT"
if [ ${PIPESTATUS[0]} -ne 0 ]; then
  echo "BUILD FALHOU" | tee -a "$OUT"
  exit 1
fi
APP=$(find "$DD/Build/Products" -maxdepth 3 -name '*.app' 2>/dev/null | head -1)
[ -z "$APP" ] && { echo "BUILD FALHOU" >&2; exit 1; }
echo "APPSIZE $VARIANT $(du -sm "$APP" | cut -f1) MB" | tee -a "$OUT"

xcrun devicectl device uninstall app --device "$DEVICE_ID" "$BUNDLE" >/dev/null 2>&1 || true
install_app() {
  xcrun devicectl device install app --device "$DEVICE_ID" "$APP" 2>&1 | tee -a "$OUT"
  return ${PIPESTATUS[0]}
}
if ! install_app; then
  echo "RETRY instalação após falha transitória" | tee -a "$OUT"
  sleep 5
  if ! install_app; then
    echo "ABORT instalação do harness falhou em duas tentativas" | tee -a "$OUT"
    exit 3
  fi
fi

launch() {
  local SCENARIO="$1"
  echo "---- $VARIANT / $SCENARIO ----" | tee -a "$OUT"
  xcrun devicectl device process launch --console --terminate-existing \
    --device "$DEVICE_ID" \
    -e "{\"GATE_SCENARIO\":\"$SCENARIO\",\"GATE_VARIANT\":\"$VARIANT\",\"GATE_FIXED_LENGTH\":\"\",\"GATE_FIXTURE\":\"trained_device_fixture\"}" \
    "$BUNDLE" 2>&1 | tee -a "$OUT"
}

launch preflight
FREE=$(tail -80 "$OUT" | grep 'GATELINE' | tail -1 | sed -E 's/.*"free_disk_mb":([0-9-]+).*/\1/')
if [ -z "$FREE" ] || [ "$FREE" -lt 800 ]; then
  echo "ABORT disco livre insuficiente para comparação: ${FREE:-desconhecido} MB" | tee -a "$OUT"
  xcrun devicectl device uninstall app --device "$DEVICE_ID" "$BUNDLE" >/dev/null 2>&1 || true
  exit 2
fi

launch parity
launch real
for LENGTH in 77 128 256 384 512; do
  launch "len-$LENGTH"
done

xcrun devicectl device uninstall app --device "$DEVICE_ID" "$BUNDLE" >/dev/null 2>&1 || true
rm -f "$BUILD/NLI_Selected.mlpackage"
echo "log -> $OUT"
