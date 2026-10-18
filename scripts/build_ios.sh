#!/usr/bin/env bash
# Compila o app "Controle PS5" para iPhone: gera o ícone, o projeto do Xcode (XcodeGen), compila e, se pedido,
# instala no iPhone pela rede ou pelo cabo.
#
# Uso: scripts/build_ios.sh simulator   compila para o Simulador (sem assinatura)
#      scripts/build_ios.sh device      compila e assina para o iPhone
#      scripts/build_ios.sh install     device + instala (e abre o app com --launch)
#
# Precisa de ios_app/Local.xcconfig (modelo em ios_app/Local.xcconfig.example): Team ID e bundle id próprios,
# que ficam fora do Git. O iPhone vem de IOS_DEVICE_UDID ou de ~/.config/ps5_remote_control/ios_device.json.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
IOS_DIR="$PROJECT_DIR/ios_app"
OUT_DIR="$PROJECT_DIR/build/ios"
MODE="${1:-simulator}"
LAUNCH=0; [[ "${2:-}" == "--launch" ]] && LAUNCH=1

[[ -f "$IOS_DIR/Local.xcconfig" ]] || { echo "Falta ios_app/Local.xcconfig (veja ios_app/Local.xcconfig.example)." >&2; exit 1; }
command -v xcodegen >/dev/null || { echo "Falta o XcodeGen: brew install xcodegen" >&2; exit 1; }
[[ -d "$OUT_DIR/ChiakiLib.xcframework" ]] || "$SCRIPT_DIR/build_chiaki_ios.sh" all

# Ícone: desenhado em código (o repositório não guarda imagens); o catálogo gerado fica fora do Git.
CATALOG="$IOS_DIR/Assets.xcassets"
ICON_SET="$CATALOG/AppIcon.appiconset"
if [[ ! "$ICON_SET/icon-1024.png" -nt "$PROJECT_DIR/mac_app/Icon/make_icon.swift" ]]; then
  echo "==> Desenhando o ícone do iPhone..."
  mkdir -p "$ICON_SET"
  swift "$PROJECT_DIR/mac_app/Icon/make_icon.swift" --ios "$ICON_SET/icon-1024.png" > /dev/null
  printf '%s\n' '{"images":[{"filename":"icon-1024.png","idiom":"universal","platform":"ios","size":"1024x1024"}],"info":{"author":"xcode","version":1}}' > "$ICON_SET/Contents.json"
  printf '%s\n' '{"info":{"author":"xcode","version":1}}' > "$CATALOG/Contents.json"
fi

echo "==> Gerando o projeto do Xcode..."
(cd "$IOS_DIR" && xcodegen generate --spec project.yml > /dev/null)

case "$MODE" in
  simulator)
    echo "==> Compilando para o Simulador..."
    xcodebuild -project "$IOS_DIR/ControlePS5.xcodeproj" -scheme ControlePS5 -sdk iphonesimulator \
      -destination 'generic/platform=iOS Simulator' -configuration Debug -derivedDataPath "$OUT_DIR/DerivedData" \
      CODE_SIGNING_ALLOWED=NO build > "$OUT_DIR/xcodebuild-sim.log" 2>&1 \
      || { echo "Falhou; veja $OUT_DIR/xcodebuild-sim.log" >&2; exit 1; }
    echo "==> Pronto: $OUT_DIR/DerivedData/Build/Products/Debug-iphonesimulator/ControlePS5.app"
    ;;
  device|install)
    UDID="${IOS_DEVICE_UDID:-$(python3 -I -c 'import json,os;print(json.load(open(os.path.expanduser("~/.config/ps5_remote_control/ios_device.json")))["udid"])' 2>/dev/null || true)}"
    [[ -n "$UDID" ]] || { echo "Defina IOS_DEVICE_UDID (xcrun devicectl list devices)." >&2; exit 1; }
    echo "==> Compilando e assinando para o iPhone..."
    xcodebuild -project "$IOS_DIR/ControlePS5.xcodeproj" -scheme ControlePS5 -destination "id=$UDID" \
      -configuration Debug -derivedDataPath "$OUT_DIR/DerivedData" -allowProvisioningUpdates build \
      > "$OUT_DIR/xcodebuild-device.log" 2>&1 || { echo "Falhou; veja $OUT_DIR/xcodebuild-device.log" >&2; exit 1; }
    APP="$OUT_DIR/DerivedData/Build/Products/Debug-iphoneos/ControlePS5.app"
    echo "==> Pronto: $APP"
    if [[ "$MODE" == "install" ]]; then
      echo "==> Instalando no iPhone (desbloqueado e na mesma rede)..."
      xcrun devicectl device install app --device "$UDID" "$APP"
      if (( LAUNCH )); then
        BUNDLE_ID="$(sed -n 's/^PS5_BUNDLE_ID *= *//p' "$IOS_DIR/Local.xcconfig")"
        xcrun devicectl device process launch --device "$UDID" "$BUNDLE_ID"
      fi
    fi
    ;;
  *) echo "Uso: $0 [simulator|device|install] [--launch]" >&2; exit 2 ;;
esac
