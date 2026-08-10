#!/bin/bash
# Spike 9 / Etapa 2 — build, instalação e medição no iPhone 16 físico.
# Cada variante é instalada separadamente para não recriar pressão de disco.
set -uo pipefail

DEVICE_ID="EFEE75FC-18B6-5948-BC37-9F9A6AA0C0F8"
TEAM="2DK23BZ7KB"
BUNDLE="com.spike.architecturegate9"
HERE="$(cd "$(dirname "$0")" && pwd)"
BENCH="$HERE/xcode-bench"
BUILD="$HERE/build"
SCRATCH="${SPIKE9_SCRATCH:-/private/tmp/spike09-architecture-gate}"
OUT="$HERE/device_results_iphone.log"

VARIANTS=("$@")
[ ${#VARIANTS[@]} -eq 0 ] && VARIANTS=(dynamic512 fixed256 fixed384 fixed512)

mkdir -p "$SCRATCH"
: > "$OUT"

if [ ! -f "$BUILD/device_fixture.json" ]; then
  echo "ERRO: rode make_device_fixture.py antes" >&2
  exit 1
fi

for SHORT in "${VARIANTS[@]}"; do
  case "$SHORT" in
    dynamic512)
      VARIANT="bertimbau_base_dynamic512"
      FIXED=""
      LENGTHS=(77 128 256 384 512)
      ;;
    fixed256|fixed384|fixed512)
      FIXED="${SHORT#fixed}"
      VARIANT="bertimbau_base_$SHORT"
      LENGTHS=("$FIXED")
      ;;
    *)
      echo "variante desconhecida: $SHORT" >&2
      exit 1
      ;;
  esac

  MODEL="$BUILD/${VARIANT}_int8.mlpackage"
  [ ! -d "$MODEL" ] && { echo "modelo ausente: $MODEL" >&2; exit 1; }

  rm -f "$BUILD/NLI_Selected.mlpackage"
  ln -s "$MODEL" "$BUILD/NLI_Selected.mlpackage"

  echo "===== BUILD $VARIANT =====" | tee -a "$OUT"
  (cd "$BENCH" && xcodegen generate) >/dev/null || exit 1
  DD="$SCRATCH/dd-$SHORT"
  rm -rf "$DD/Build/Products"
  xcodebuild -project "$BENCH/ArchitectureGate9.xcodeproj" -scheme ArchitectureGate9 \
    -sdk iphoneos -configuration Release \
    -destination "platform=iOS,id=$DEVICE_ID" -derivedDataPath "$DD" \
    DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_STYLE=Automatic \
    -allowProvisioningUpdates build 2>&1 | tail -4 | tee -a "$OUT"
  APP=$(find "$DD/Build/Products" -maxdepth 3 -name '*.app' 2>/dev/null | head -1)
  [ -z "$APP" ] && { echo "BUILD FALHOU" >&2; exit 1; }
  echo "APPSIZE $VARIANT $(du -sm "$APP" | cut -f1) MB" | tee -a "$OUT"

  # Só o bundle deste próprio spike; garante container/cache novo entre variantes.
  xcrun devicectl device uninstall app --device "$DEVICE_ID" "$BUNDLE" >/dev/null 2>&1 || true
  xcrun devicectl device install app --device "$DEVICE_ID" "$APP" 2>&1 | tail -4 | tee -a "$OUT"

  launch() {
    local SCENARIO="$1"
    echo "---- $VARIANT / $SCENARIO ----" | tee -a "$OUT"
    xcrun devicectl device process launch --console --terminate-existing \
      --device "$DEVICE_ID" \
      -e "{\"GATE_SCENARIO\":\"$SCENARIO\",\"GATE_VARIANT\":\"$VARIANT\",\"GATE_FIXED_LENGTH\":\"$FIXED\"}" \
      "$BUNDLE" 2>&1 | tee -a "$OUT"
  }

  # A primeira execução não carrega modelos: mede disco depois da instalação.
  launch preflight
  FREE=$(tail -80 "$OUT" | grep 'GATELINE' | tail -1 | sed -E 's/.*"free_disk_mb":([0-9-]+).*/\1/')
  if [ -z "$FREE" ] || [ "$FREE" -lt 800 ]; then
    echo "ABORT disco livre insuficiente para comparação: ${FREE:-desconhecido} MB" | tee -a "$OUT"
    xcrun devicectl device uninstall app --device "$DEVICE_ID" "$BUNDLE" >/dev/null 2>&1 || true
    exit 2
  fi

  launch parity
  launch real
  for LENGTH in "${LENGTHS[@]}"; do
    launch "len-$LENGTH"
  done

  xcrun devicectl device uninstall app --device "$DEVICE_ID" "$BUNDLE" >/dev/null 2>&1 || true
done

rm -f "$BUILD/NLI_Selected.mlpackage"
echo "log -> $OUT"
