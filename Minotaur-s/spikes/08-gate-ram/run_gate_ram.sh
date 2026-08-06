#!/bin/bash
# SPIKE 8 — GATE DA FASE 6 (item aberto 27): build + install + run no iPhone FÍSICO.
#
# Mede o pico de RAM com os DOIS modelos vivos ao mesmo tempo (embeddings 113 MB +
# plue_bertimbau 320 MB), rodando a carga de uma verificação real. Teto: 1 GB (NF-06).
#
# Não é medível em simulador: lá a memória é a do Mac, com outro alocador e sem jetsam.
#
# Requer conta Apple logada no Xcode (Settings > Accounts) para assinatura automática.
#
# Uso:  ./run_gate_ram.sh
set -uo pipefail

DEVICE_ID="EFEE75FC-18B6-5948-BC37-9F9A6AA0C0F8"   # br-NKHFRW9FDY (iPhone 16)
TEAM="2DK23BZ7KB"
BUNDLE="com.spike.ramgate8"
HERE="$(cd "$(dirname "$0")" && pwd)"
BENCH_ROOT="$HERE/xcode-bench"
SCRATCH="${SCRATCH_DIR:-/private/tmp/spike08}"
DD="$SCRATCH/dd-dev-auto"
OUT="$HERE/device_results_iphone.log"

mkdir -p "$SCRATCH"

if [ ! -f "$HERE/build/fixture.json" ]; then
  echo "ERRO: build/fixture.json não existe. Rode antes:" >&2
  echo "  ../03-extracao-texto/.venv/bin/python make_fixture.py --extract" >&2
  echo "  ../02-coreml-latencia/.venv/bin/python make_fixture.py" >&2
  exit 1
fi

echo "=== [0/5] xcodegen ==="
(cd "$BENCH_ROOT" && xcodegen generate) >/dev/null || { echo "xcodegen falhou"; exit 1; }

echo "=== [1/5] build ==="
rm -rf "$DD/Build/Products"
xcodebuild -project "$BENCH_ROOT/RAMGate8.xcodeproj" -scheme RAMGate8 \
  -sdk iphoneos -configuration Release \
  -destination "platform=iOS,id=$DEVICE_ID" -derivedDataPath "$DD" \
  DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_STYLE=Automatic \
  -allowProvisioningUpdates build 2>&1 | tail -3
APP=$(find "$DD/Build/Products" -name '*.app' -maxdepth 3 2>/dev/null | head -1)
[ -z "$APP" ] && { echo "BUILD FALHOU (sem .app)"; exit 1; }
echo "  .app = $(du -sh "$APP" | cut -f1)"

echo "=== [2/5] install ==="
# Falha por espaço aqui (IXUserPresentableErrorDomain 11) é RESULTADO, não acidente:
# foi a ressalva do FILTRO 2 do Spike 7, e é para ser reportada, não contornada.
xcrun devicectl device install app --device "$DEVICE_ID" "$APP" 2>&1 | tail -5

echo "=== [3/5] launch ==="
# Um cenário por lançamento, em processo NOVO: memória de Core ML é pegajosa e o que
# uma fase aloca contamina a leitura da seguinte.
CENARIOS=("$@")
[ ${#CENARIOS[@]} -eq 0 ] && CENARIOS=(real fixed release worst)

: > "$OUT"
for CENARIO in "${CENARIOS[@]}"; do
  echo "---- cenário: $CENARIO ----" | tee -a "$OUT"
  xcrun devicectl device process launch --console --terminate-existing \
    --device "$DEVICE_ID" -e "{\"GATE_SCENARIO\":\"$CENARIO\"}" \
    "$BUNDLE" 2>&1 | tee -a "$OUT"
done

echo "=== [4/5] linhas do gate ==="
grep -E 'RAMLINE|---- cenário' "$OUT"

echo "=== [5/5] uninstall ==="
xcrun devicectl device uninstall app --device "$DEVICE_ID" "$BUNDLE" 2>&1 | tail -1

echo "(log completo em $OUT)"
