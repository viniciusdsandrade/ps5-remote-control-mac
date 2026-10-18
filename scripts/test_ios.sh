#!/usr/bin/env bash
# Testes do app do iPhone, no Simulador, um de cada vez (duas execuções ao mesmo tempo brigam pelo simulador e
# pelos dados de build):
#   1. autoteste de teclas dentro do app (-ps5-selftest-input): 52 teclas sintéticas pelo mesmo sendEvent;
#   2. teste de toque (XCUITest): toques reais viram comandos, um por toque.
# Tudo em modo de teste: nada vai ao PS5 nem à TV e o pareamento é de mentira, em memória.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
IOS_DIR="$PROJECT_DIR/ios_app"
OUT_DIR="$PROJECT_DIR/build/ios"
SIM_NAME="ps5-controle-teste"

"$SCRIPT_DIR/build_ios.sh" simulator

# Simulador próprio (iPhone 17 no iOS 27.0), para não mexer nos de outros projetos.
SIM="$(xcrun simctl list devices | sed -n "s/.*$SIM_NAME (\([0-9A-F-]*\)).*/\1/p" | head -1)"
if [[ -z "$SIM" ]]; then
  SIM="$(xcrun simctl create "$SIM_NAME" com.apple.CoreSimulator.SimDeviceType.iPhone-17 com.apple.CoreSimulator.SimRuntime.iOS-27-0)"
fi
xcrun simctl bootstatus "$SIM" -b > /dev/null 2>&1

BUNDLE_ID="$(sed -n 's/^PS5_BUNDLE_ID *= *//p' "$IOS_DIR/Local.xcconfig")"
echo "==> Autoteste de teclas (dentro do app)..."
xcrun simctl install "$SIM" "$OUT_DIR/DerivedData/Build/Products/Debug-iphonesimulator/ControlePS5.app"
xcrun simctl launch --console "$SIM" "$BUNDLE_ID" -ps5-selftest-input | grep -E '^(ok|FALHA|RESULTADO)' | tee "$OUT_DIR/selftest-input.txt"
grep -q '^RESULTADO: passou' "$OUT_DIR/selftest-input.txt"

echo "==> Teste de toque (XCUITest)..."
xcodebuild test -project "$IOS_DIR/ControlePS5.xcodeproj" -scheme ControlePS5 -destination "platform=iOS Simulator,id=$SIM" \
  -derivedDataPath "$OUT_DIR/DerivedData" CODE_SIGNING_ALLOWED=NO -only-testing:ControlePS5UITests \
  > "$OUT_DIR/uitest.log" 2>&1 || { grep -E 'error:|failed' "$OUT_DIR/uitest.log" | head -10; exit 1; }
grep -E 'Executed [0-9]+ test' "$OUT_DIR/uitest.log" | tail -1
echo "==> Testes do iPhone: passaram."
