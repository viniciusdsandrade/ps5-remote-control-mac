#!/usr/bin/env bash
# Compila o app "Controle PS5" (SwiftUI + libchiaki estática + código da TV LG), monta o bundle,
# assina ad-hoc e instala em ~/Applications com atalho na Mesa, no mesmo molde do Controle Remoto LG.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
MAC_APP="$PROJECT_DIR/mac_app"
CHIAKI_SRC="$PROJECT_DIR/vendor/chiaki-ng"
CHIAKI_BUILD="$PROJECT_DIR/build/chiaki"
TV_APP="${LG_ROAP_CONTROL_DIR:-$PROJECT_DIR/../lg-roap-control}/mac_app"
APP_NAME="Controle PS5"
APP_DIR="$PROJECT_DIR/build/$APP_NAME.app"
ICON="$PROJECT_DIR/build/AppIcon.icns"
INSTALLED_APP="$HOME/Applications/$APP_NAME.app"
DESKTOP_LINK="$HOME/Desktop/$APP_NAME.app"

[[ -f "$CHIAKI_BUILD/libchiaki_all.a" ]] || "$SCRIPT_DIR/build_chiaki.sh"
# The TV integration comes from the sibling project lg-roap-control (not in this repository). Without it,
# the app is built with a stand-in (mac_app/TVStub) and works with the PS5 only.
TV_SOURCES=("$TV_APP/LGTVClient.swift" "$TV_APP/TVBoxLink.swift" "$TV_APP/AndroidTVRemote.swift")
for f in "${TV_SOURCES[@]}"; do
  if [[ ! -f "$f" ]]; then
    echo "==> Projeto da TV não encontrado em $TV_APP: compilando sem a integração com a TV."
    TV_SOURCES=("$MAC_APP/TVStub/TVStub.swift")
    break
  fi
done

echo "==> Compilando $APP_NAME..."
mkdir -p "$PROJECT_DIR/build"
swiftc -O -parse-as-library \
  -import-objc-header "$MAC_APP/CChiaki/chiaki-bridge.h" \
  -I "$CHIAKI_SRC/lib/include" \
  -I "$CHIAKI_BUILD/lib/include" \
  "$PROJECT_DIR"/shared/Engine/*.swift \
  "$PROJECT_DIR"/shared/Theater/*.swift \
  "$PROJECT_DIR"/shared/UI/*.swift \
  "$MAC_APP"/UI/*.swift \
  "${TV_SOURCES[@]}" \
  "$CHIAKI_BUILD/libchiaki_all.a" \
  -framework CoreServices -framework SystemConfiguration -lz \
  -o "$PROJECT_DIR/build/$APP_NAME"

# The icon is drawn in code (mac_app/Icon/make_icon.swift), so the repository holds no image; it is redrawn only
# when that file changes.
if [[ ! "$ICON" -nt "$MAC_APP/Icon/make_icon.swift" ]]; then
  echo "==> Desenhando o ícone..."
  rm -rf "$PROJECT_DIR/build/AppIcon.iconset"
  swift "$MAC_APP/Icon/make_icon.swift" "$PROJECT_DIR/build/AppIcon.iconset" > /dev/null
  iconutil -c icns "$PROJECT_DIR/build/AppIcon.iconset" -o "$ICON"
fi

echo "==> Montando bundle..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$MAC_APP/Info.plist" "$APP_DIR/Contents/"
cp "$ICON" "$APP_DIR/Contents/Resources/AppIcon.icns"
cp "$PROJECT_DIR/build/$APP_NAME" "$APP_DIR/Contents/MacOS/"
chmod +x "$APP_DIR/Contents/MacOS/$APP_NAME"

# Ad-hoc signature with the bundle id: the "Rede local" permission is tied to it.
echo "==> Assinando (ad-hoc)..."
codesign --force --sign - "$APP_DIR"

# On macOS 26 the Dock puts icons that aren't a "squircle" inside a grey frame; a custom icon (like one pasted in
# Get Info) is shown as is. It must come after codesign, which refuses the bundle once the custom icon is there.
apply_custom_icon() {
  local result
  result=$(osascript -l JavaScript -e '
    ObjC.import("AppKit");
    function run(argv) {
      const img = $.NSImage.alloc.initWithContentsOfFile(argv[0]);
      if (img.isNil()) return "imagem inválida";
      return $.NSWorkspace.sharedWorkspace.setIconForFileOptions(img, argv[1], 0) ? "ok" : "falhou";
    }' "$ICON" "$1" 2>&1) || true
  [[ "$result" == "ok" ]] || echo "    Aviso: ícone não aplicado em $1 ($result)"
}

if [[ -n "${NO_INSTALL:-}" ]]; then
  apply_custom_icon "$APP_DIR"
  echo "==> Pronto (NO_INSTALL: não instalado). Bundle em: $APP_DIR"
  exit 0
fi

echo "==> Instalando em ~/Applications (atalho na Mesa)..."
mkdir -p "$(dirname "$INSTALLED_APP")"
rm -rf "$INSTALLED_APP"
cp -R "$APP_DIR" "$INSTALLED_APP"
if [[ -d "$DESKTOP_LINK" && ! -L "$DESKTOP_LINK" ]]; then rm -rf "$DESKTOP_LINK"; fi
[[ -L "$DESKTOP_LINK" ]] || ln -s "$INSTALLED_APP" "$DESKTOP_LINK"

echo "==> Aplicando o ícone (sem moldura no Dock)..."
apply_custom_icon "$APP_DIR"
apply_custom_icon "$INSTALLED_APP"

echo "==> Pronto."
echo "    Instalado em: $INSTALLED_APP"
echo "    Atalho:       $DESKTOP_LINK"
