#!/usr/bin/env bash
# Compila o ps5ctl (CLI de prova da Fase 1) com o motor Swift e a libchiaki estática.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
MAC_APP="$PROJECT_DIR/mac_app"
CHIAKI_SRC="${CHIAKI_SRC_DIR:-$PROJECT_DIR/vendor/chiaki-ng}"
CHIAKI_BUILD="${CHIAKI_BUILD_DIR:-$PROJECT_DIR/build/chiaki}"
OUT="${PS5CTL_OUT:-$PROJECT_DIR/build/ps5ctl}"

[[ -f "$CHIAKI_BUILD/libchiaki_all.a" ]] || "$SCRIPT_DIR/build_chiaki.sh"

echo "==> Compilando ps5ctl..."
swiftc -O -parse-as-library \
  -import-objc-header "$MAC_APP/CChiaki/chiaki-bridge.h" \
  -I "$CHIAKI_SRC/lib/include" \
  -I "$CHIAKI_BUILD/lib/include" \
  "$PROJECT_DIR"/shared/Engine/*.swift \
  "$MAC_APP"/CLI/*.swift \
  "$CHIAKI_BUILD/libchiaki_all.a" \
  -framework CoreServices -framework SystemConfiguration -lz \
  -o "$OUT"

echo "==> Pronto: $OUT"
echo "    Bibliotecas dinâmicas usadas (nada do Homebrew deve aparecer):"
otool -L "$OUT" | tail -n +2 | sed 's/^/      /'
