#!/usr/bin/env bash
# Compila a biblioteca do chiaki-ng (libchiaki) para iOS e junta tudo num XCFramework:
# build/ios/ChiakiLib.xcframework, com uma fatia para o iPhone (arm64) e outra para o Simulador (arm64).
#
# Mesma biblioteca e mesmo commit do app do Mac (vendor/chiaki-ng); o que muda é só o alvo. O OpenSSL e a
# libevent são compilados aqui, a partir dos fontes que o Homebrew já confere pelo hash da fórmula; json-c e
# miniupnpc vêm das opções *_EXTERNAL_PROJECT do próprio chiaki-ng (as mesmas do build Android); o curl é o do
# submódulo. O modo pela internet do chiaki-ng não é usado pelo app, mas a biblioteca liga essas dependências.
#
# Uso: scripts/build_chiaki_ios.sh [device|simulator|all]   (padrão: all)
#      IOS_MIN=18.0 muda o iOS mínimo.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SRC_DIR="${CHIAKI_SRC_DIR:-$PROJECT_DIR/vendor/chiaki-ng}"
OUT_DIR="${CHIAKI_IOS_BUILD_DIR:-$PROJECT_DIR/build/ios}"
VENV_DIR="$PROJECT_DIR/build/venv"
IOS_MIN="${IOS_MIN:-18.0}"
JOBS="$(sysctl -n hw.ncpu)"
BREW_PREFIX="$(brew --prefix)"
WHICH="${1:-all}"

for pkg in cmake ninja pkgconf protobuf@29 openssl@3 libevent; do
  brew list --versions "$pkg" >/dev/null 2>&1 || { echo "Falta o pacote do Homebrew: $pkg (brew install $pkg)" >&2; exit 1; }
done

# Fontes do OpenSSL e da libevent: os mesmos que o Homebrew usa, com o hash conferido por ele.
mkdir -p "$OUT_DIR/src"
brew fetch --build-from-source openssl@3 libevent >/dev/null
for formula in openssl@3 libevent; do
  tarball="$(brew --cache -s "$formula")"
  dir="$OUT_DIR/src/$(basename "$tarball" | sed -E 's/^[0-9a-f]+--//; s/\.tar\.gz$//')"
  [[ -d "$dir" ]] || tar xzf "$tarball" -C "$OUT_DIR/src"
done
OPENSSL_SRC="$(find "$OUT_DIR/src" -maxdepth 1 -type d -name 'openssl-*' | head -1)"
LIBEVENT_SRC="$(find "$OUT_DIR/src" -maxdepth 1 -type d -name 'libevent-*' | head -1)"

echo "==> Conferindo submódulos..."
[[ -n "${CHIAKI_SRC_DIR:-}" ]] || git -C "$PROJECT_DIR" submodule update --init vendor/chiaki-ng
git -C "$SRC_DIR" submodule update --init --depth 1 \
  third-party/nanopb third-party/jerasure third-party/gf-complete third-party/curl

if [[ ! -x "$VENV_DIR/bin/python" ]]; then
  echo "==> Criando venv do Python para o gerador do nanopb..."
  /usr/bin/python3 -m venv "$VENV_DIR"
  "$VENV_DIR/bin/pip" install -q --upgrade pip 'protobuf>=5,<6'
fi
export PATH="$BREW_PREFIX/opt/protobuf@29/bin:$PATH"   # protoc roda no Mac, não no iPhone

build_slice() { # nome da fatia: device ou simulator
  local slice="$1" sdk openssl_target min_flag
  case "$slice" in
    device)    sdk=iphoneos;        openssl_target=ios64-xcrun;             min_flag="-mios-version-min=$IOS_MIN" ;;
    simulator) sdk=iphonesimulator; openssl_target=iossimulator-arm64-xcrun; min_flag="-mios-simulator-version-min=$IOS_MIN" ;;
  esac
  local base="$OUT_DIR/$slice" prefix="$OUT_DIR/$slice/prefix"
  local cmake_ios=(-DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT="$sdk" -DCMAKE_OSX_ARCHITECTURES=arm64
                   -DCMAKE_OSX_DEPLOYMENT_TARGET="$IOS_MIN"
                   -DCMAKE_BUILD_TYPE=Release -DCMAKE_POLICY_VERSION_MINIMUM=3.5)
  mkdir -p "$base"

  if [[ ! -f "$prefix/lib/libcrypto.a" ]]; then
    echo "==> [$slice] OpenSSL ($openssl_target)..."
    rm -rf "$base/openssl-build"; mkdir -p "$base/openssl-build"
    (cd "$base/openssl-build" \
      && "$OPENSSL_SRC/Configure" "$openssl_target" no-shared no-tests no-apps no-docs no-dso no-ui-console \
           --prefix="$prefix" "$min_flag" > configure.log 2>&1 \
      && make -j"$JOBS" build_libs > build.log 2>&1 \
      && make install_dev > install.log 2>&1) || { echo "OpenSSL falhou; veja $base/openssl-build/*.log" >&2; exit 1; }
  fi

  if [[ ! -f "$prefix/lib/libevent.a" ]]; then
    echo "==> [$slice] libevent..."
    cmake -S "$LIBEVENT_SRC" -B "$base/libevent-build" -G Ninja "${cmake_ios[@]}" \
      -DCMAKE_INSTALL_PREFIX="$prefix" -DEVENT__LIBRARY_TYPE=STATIC \
      -DEVENT__DISABLE_OPENSSL=ON -DEVENT__DISABLE_MBEDTLS=ON -DEVENT__DISABLE_TESTS=ON \
      -DEVENT__DISABLE_SAMPLES=ON -DEVENT__DISABLE_BENCHMARK=ON -DEVENT__DISABLE_REGRESS=ON > "$base/libevent-configure.log" 2>&1 \
      && cmake --build "$base/libevent-build" -j"$JOBS" > "$base/libevent-build.log" 2>&1 \
      && cmake --install "$base/libevent-build" > "$base/libevent-install.log" 2>&1 \
      || { echo "libevent falhou; veja $base/libevent-*.log" >&2; exit 1; }
  fi

  echo "==> [$slice] libchiaki (CMake + Ninja)..."
  # pkg-config só enxerga a libevent desta fatia, nunca a do Homebrew (que é de macOS)
  PKG_CONFIG_LIBDIR="$prefix/lib/pkgconfig" PKG_CONFIG_PATH="" \
  cmake -S "$SRC_DIR" -B "$base/chiaki" -G Ninja "${cmake_ios[@]}" \
    -DPYTHON_EXECUTABLE="$VENV_DIR/bin/python" \
    -DCMAKE_PROJECT_TOP_LEVEL_INCLUDES="$SCRIPT_DIR/cmake/ios-top-level.cmake" \
    -DCMAKE_FIND_ROOT_PATH="$prefix" \
    -DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER \
    -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=BOTH \
    -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=BOTH \
    -DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=BOTH \
    -DOPENSSL_ROOT_DIR="$prefix" -DOPENSSL_USE_STATIC_LIBS=ON \
    -DCHIAKI_LIB_JSONC_EXTERNAL_PROJECT=ON \
    -DCHIAKI_LIB_MINIUPNPC_EXTERNAL_PROJECT=ON \
    -DCHIAKI_ENABLE_GUI=OFF -DCHIAKI_ENABLE_CLI=OFF -DCHIAKI_ENABLE_TESTS=OFF \
    -DCHIAKI_ENABLE_STEAMDECK_NATIVE=OFF -DCHIAKI_ENABLE_STEAM_SHORTCUT=OFF -DCHIAKI_ENABLE_SETSU=OFF \
    -DCHIAKI_ENABLE_SPEEX=OFF -DCHIAKI_ENABLE_FFMPEG_DECODER=OFF -DCHIAKI_ENABLE_PI_DECODER=OFF \
    -DCHIAKI_LIB_ENABLE_OPUS=OFF \
    -DCURL_USE_OPENSSL=ON -DCURL_USE_LIBPSL=OFF -DCURL_USE_LIBSSH2=OFF -DCURL_USE_GSSAPI=OFF \
    -DCURL_BROTLI=OFF -DCURL_ZSTD=OFF -DUSE_NGHTTP2=OFF -DUSE_LIBIDN2=OFF -DCURL_ZLIB=OFF \
    -DBUILD_CURL_EXE=OFF -DBUILD_TESTING=OFF > "$base/chiaki-configure.log" 2>&1 \
    || { echo "CMake falhou; veja $base/chiaki-configure.log" >&2; exit 1; }
  cmake --build "$base/chiaki" -j"$JOBS" --target chiaki-lib > "$base/chiaki-build.log" 2>&1 \
    || { echo "Compilação falhou; veja $base/chiaki-build.log" >&2; exit 1; }

  echo "==> [$slice] juntando os arquivos estáticos em libchiaki_all.a..."
  local libs=()
  while IFS= read -r lib; do libs+=("$lib"); done < <(find "$base/chiaki" -name '*.a' -not -name 'libchiaki_all.a' | sort)
  libs+=("$prefix/lib/libcrypto.a" "$prefix/lib/libssl.a" "$prefix/lib/libevent.a" "$prefix/lib/libevent_pthreads.a")
  for lib in "${libs[@]}"; do [[ -f "$lib" ]] || { echo "Biblioteca não encontrada: $lib" >&2; exit 1; }; done
  libtool -static -o "$base/libchiaki_all.a" "${libs[@]}" 2> >(grep -v 'has no symbols' >&2 || true)
  echo "    $base/libchiaki_all.a ($(du -h "$base/libchiaki_all.a" | cut -f1))"
}

case "$WHICH" in
  device)    build_slice device ;;
  simulator) build_slice simulator ;;
  all)       build_slice simulator; build_slice device ;;
  *) echo "Uso: $0 [device|simulator|all]" >&2; exit 2 ;;
esac

if [[ "$WHICH" == "all" ]]; then
  echo "==> Criando o XCFramework..."
  # Cabeçalhos: os públicos da biblioteca e o config.h gerado (iguais nas duas fatias).
  rm -rf "$OUT_DIR/include" "$OUT_DIR/ChiakiLib.xcframework"
  mkdir -p "$OUT_DIR/include"
  cp -R "$SRC_DIR/lib/include/chiaki" "$OUT_DIR/include/"
  cp "$OUT_DIR/device/chiaki/lib/include/chiaki/config.h" "$OUT_DIR/include/chiaki/config.h"
  xcodebuild -create-xcframework \
    -library "$OUT_DIR/device/libchiaki_all.a" -headers "$OUT_DIR/include" \
    -library "$OUT_DIR/simulator/libchiaki_all.a" -headers "$OUT_DIR/include" \
    -output "$OUT_DIR/ChiakiLib.xcframework" > /dev/null
  echo "==> Pronto: $OUT_DIR/ChiakiLib.xcframework"
fi
