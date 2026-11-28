#!/usr/bin/env bash
set -euo pipefail

if [[ $# != 2 ]]; then
    printf 'Uso: %s /ruta/chromaprint-1.6.0.tar.gz /ruta/directorio-de-salida\n' "$0" >&2
    exit 2
fi

archive="$(cd -- "$(dirname -- "$1")" && pwd)/$(basename -- "$1")"
output="$2"
expected=65bfce4a35b2e673dbcda917b6aa577e2f145cf805243d19e6a50fea2a520c2a
actual="$(LC_ALL=C shasum -a 256 "$archive" | awk '{print $1}')"
[[ "$actual" == "$expected" ]] || { printf 'El archivo fuente no coincide con Chromaprint 1.6.0.\n' >&2; exit 1; }
command -v cmake >/dev/null
work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT
LC_ALL=C tar -xf "$archive" -C "$work"
source="$work/chromaprint-1.6.0"
cmake -S "$source" -B "$work/build" \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES="$(uname -m)" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=12.0 -DCMAKE_INSTALL_NAME_DIR=@rpath \
    -DCMAKE_CXX_COMPILER=clang++ -DCMAKE_C_COMPILER=clang \
    -DCMAKE_DISABLE_FIND_PACKAGE_FFmpeg=TRUE -DFFT_LIB=vdsp \
    -DUSE_INTERNAL_AVRESAMPLE=ON -DBUILD_SHARED_LIBS=ON -DBUILD_TESTS=OFF -DBUILD_TOOLS=OFF
cmake --build "$work/build" --config Release --parallel 2
cmake --install "$work/build" --prefix "$work/install"
mkdir -p -- "$output"
cp -L -- "$work/install/lib/libchromaprint.dylib" "$output/libchromaprint.dylib"
cp -- "$source/LICENSE.md" "$output/LICENSE.md"
cp -- "$archive" "$output/chromaprint-1.6.0.tar.gz"
