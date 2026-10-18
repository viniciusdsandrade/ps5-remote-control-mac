#!/usr/bin/env bash
# Compila só a biblioteca do chiaki-ng (libchiaki) e junta tudo num único arquivo estático,
# build/chiaki/libchiaki_all.a, para o swiftc ligar sem depender de nada do Homebrew em tempo
# de execução. Cabeçalhos ficam em vendor/chiaki-ng/lib/include e build/chiaki/lib/include.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SRC_DIR="${CHIAKI_SRC_DIR:-$PROJECT_DIR/vendor/chiaki-ng}"
BUILD_DIR="${CHIAKI_BUILD_DIR:-$PROJECT_DIR/build/chiaki}"
VENV_DIR="$PROJECT_DIR/build/venv"
BREW_PREFIX="$(brew --prefix)"

# Ferramentas e bibliotecas do Homebrew (compilação; nada disso é necessário para rodar o app)
BREW_PACKAGES=(cmake ninja pkgconf miniupnpc libevent protobuf@29 openssl@3 json-c)
missing=()
for pkg in "${BREW_PACKAGES[@]}"; do
  brew list --versions "$pkg" >/dev/null 2>&1 || missing+=("$pkg")
done
if ((${#missing[@]})); then
  echo "==> Instalando pacotes do Homebrew que faltam: ${missing[*]}"
  brew install "${missing[@]}"
fi

# Submódulos que a biblioteca usa (o resto do chiaki-ng, como GUI e Switch, fica de fora)
echo "==> Conferindo submódulos..."
[[ -n "${CHIAKI_SRC_DIR:-}" ]] || git -C "$PROJECT_DIR" submodule update --init vendor/chiaki-ng
git -C "$SRC_DIR" submodule update --init --depth 1 \
  third-party/nanopb third-party/jerasure third-party/gf-complete third-party/curl

# O gerador do nanopb precisa do pacote Python protobuf 5.x, compatível com o protoc 29
if [[ ! -x "$VENV_DIR/bin/python" ]]; then
  echo "==> Criando venv do Python para o gerador do nanopb..."
  /usr/bin/python3 -m venv "$VENV_DIR"
  "$VENV_DIR/bin/pip" install -q --upgrade pip 'protobuf>=5,<6'
fi

export PATH="$BREW_PREFIX/opt/protobuf@29/bin:$PATH"
export PKG_CONFIG_PATH="$BREW_PREFIX/opt/openssl@3/lib/pkgconfig:${PKG_CONFIG_PATH:-}"

echo "==> Configurando (CMake + Ninja), só a biblioteca..."
cmake -S "$SRC_DIR" -B "$BUILD_DIR" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DPYTHON_EXECUTABLE="$VENV_DIR/bin/python" \
  -DOPENSSL_ROOT_DIR="$BREW_PREFIX/opt/openssl@3" \
  -DCMAKE_PREFIX_PATH="$BREW_PREFIX/opt/openssl@3;$BREW_PREFIX/opt/protobuf@29" \
  -DCHIAKI_ENABLE_GUI=OFF \
  -DCHIAKI_ENABLE_CLI=OFF \
  -DCHIAKI_ENABLE_TESTS=OFF \
  -DCHIAKI_ENABLE_STEAMDECK_NATIVE=OFF \
  -DCHIAKI_ENABLE_STEAM_SHORTCUT=OFF \
  -DCHIAKI_ENABLE_SETSU=OFF \
  -DCHIAKI_ENABLE_SPEEX=OFF \
  -DCHIAKI_ENABLE_FFMPEG_DECODER=OFF \
  -DCHIAKI_ENABLE_PI_DECODER=OFF \
  -DCHIAKI_LIB_ENABLE_OPUS=OFF \
  -DCURL_USE_OPENSSL=ON \
  -DCURL_USE_LIBPSL=OFF \
  -DCURL_USE_LIBSSH2=OFF \
  -DCURL_USE_GSSAPI=OFF \
  -DCURL_BROTLI=OFF \
  -DCURL_ZSTD=OFF \
  -DUSE_NGHTTP2=OFF \
  -DUSE_LIBIDN2=OFF \
  -DCURL_ZLIB=OFF \
  -DCURL_USE_LIBPSL=OFF

echo "==> Compilando libchiaki..."
cmake --build "$BUILD_DIR" --target chiaki-lib

echo "==> Juntando os arquivos estáticos em libchiaki_all.a..."
# (sem mapfile: o bash do macOS é o 3.2)
BUILT_LIBS=()
while IFS= read -r lib; do BUILT_LIBS+=("$lib"); done < <(find "$BUILD_DIR" -name '*.a' -not -name 'libchiaki_all.a' | sort)
BREW_LIBS=(
  "$BREW_PREFIX/opt/openssl@3/lib/libcrypto.a"
  "$BREW_PREFIX/opt/openssl@3/lib/libssl.a"
  "$BREW_PREFIX/opt/json-c/lib/libjson-c.a"
  "$BREW_PREFIX/opt/miniupnpc/lib/libminiupnpc.a"
  "$BREW_PREFIX/opt/libevent/lib/libevent.a"
  "$BREW_PREFIX/opt/libevent/lib/libevent_pthreads.a"
)
for lib in "${BREW_LIBS[@]}"; do
  [[ -f "$lib" ]] || { echo "Biblioteca estática não encontrada: $lib" >&2; exit 1; }
done
printf '    %s\n' "${BUILT_LIBS[@]}" "${BREW_LIBS[@]}"
libtool -static -o "$BUILD_DIR/libchiaki_all.a" "${BUILT_LIBS[@]}" "${BREW_LIBS[@]}" 2> >(grep -v 'has no symbols' >&2 || true)

echo "==> Pronto."
echo "    Biblioteca:  $BUILD_DIR/libchiaki_all.a ($(du -h "$BUILD_DIR/libchiaki_all.a" | cut -f1))"
echo "    Cabeçalhos:  $SRC_DIR/lib/include  e  $BUILD_DIR/lib/include"
echo "    Para ligar:  -framework CoreServices -framework SystemConfiguration -lz"
