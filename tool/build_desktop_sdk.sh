#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
REVISION=218265cadc26b00f89b8e689f093954f265752df
WORK_ROOT=${FLUTTER_MIMC_SDK_BUILD_ROOT:-"${TMPDIR:-/tmp}/flutter_mimc_cpp_sdk"}
SOURCE_DIR="$WORK_ROOT/source"
BUILD_DIR="$WORK_ROOT/build"

case "${1:-$(uname -s | tr '[:upper:]' '[:lower:]')}" in
  darwin|macos)
    PLATFORM=macos
    VENDOR_DIR="$ROOT/macos/Vendor"
    ;;
  linux)
    PLATFORM=linux
    VENDOR_DIR="$ROOT/linux/vendor"
    ;;
  windows|mingw*|msys*)
    PLATFORM=windows
    VENDOR_DIR="$ROOT/windows/vendor"
    ;;
  *)
    echo "Usage: $0 [macos|linux|windows]" >&2
    exit 2
    ;;
esac

mkdir -p "$WORK_ROOT" "$VENDOR_DIR"
if [[ ! -d "$SOURCE_DIR/.git" ]]; then
  git clone https://github.com/Xiaomi-mimc/mimc-cpp-sdk.git "$SOURCE_DIR"
fi
git -C "$SOURCE_DIR" fetch --depth 1 origin "$REVISION"
git -C "$SOURCE_DIR" checkout --detach "$REVISION"
git -C "$SOURCE_DIR" reset --hard "$REVISION"
git -C "$SOURCE_DIR" clean -ffd
git -C "$SOURCE_DIR" apply "$ROOT/tool/desktop_sdk/mimc-portable-crypto.patch"

if ! command -v cmake >/dev/null 2>&1; then
  ANDROID_CMAKE="$HOME/Library/Android/sdk/cmake/3.22.1/bin/cmake"
  if [[ -x "$ANDROID_CMAKE" ]]; then
    CMAKE="$ANDROID_CMAKE"
  else
    echo "cmake 3.16 or newer is required" >&2
    exit 1
  fi
else
  CMAKE=cmake
fi

configure=(
  -S "$ROOT/tool/desktop_sdk"
  -B "$BUILD_DIR/$PLATFORM"
  -DMIMC_SDK_SOURCE="$SOURCE_DIR"
  -DCMAKE_BUILD_TYPE=Release
)
if [[ "$PLATFORM" == macos ]]; then
  configure+=(
    -DCMAKE_OSX_DEPLOYMENT_TARGET=10.14
    -DCMAKE_OSX_ARCHITECTURES="${CMAKE_OSX_ARCHITECTURES:-x86_64;arm64}"
  )
fi
if [[ "$PLATFORM" == windows ]]; then
  VCPKG_ROOT=${VCPKG_ROOT:-${VCPKG_INSTALLATION_ROOT:-}}
  if [[ -z "$VCPKG_ROOT" || ! -f "$VCPKG_ROOT/scripts/buildsystems/vcpkg.cmake" ]]; then
    echo "Set VCPKG_ROOT to a vcpkg checkout with curl and pthreads support" >&2
    exit 1
  fi
  configure+=(
    -DCMAKE_TOOLCHAIN_FILE="$VCPKG_ROOT/scripts/buildsystems/vcpkg.cmake"
    -DVCPKG_TARGET_TRIPLET=x64-windows
    -DVCPKG_INSTALLED_DIR="$WORK_ROOT/vcpkg_installed"
    -A x64
  )
fi

"$CMAKE" "${configure[@]}"
"$CMAKE" --build "$BUILD_DIR/$PLATFORM" --config Release --parallel

case "$PLATFORM" in
  macos)
    output="$BUILD_DIR/$PLATFORM/libmimc_sdk.dylib"
    ;;
  linux)
    output="$BUILD_DIR/$PLATFORM/libmimc_sdk.so"
    ;;
  windows)
    output=$(find "$BUILD_DIR/$PLATFORM" -type f -name 'mimc_sdk.dll' -print -quit)
    ;;
esac

if [[ ! -f "$output" ]]; then
  echo "Expected SDK output was not produced: $output" >&2
  exit 1
fi
cp "$output" "$VENDOR_DIR/"
if [[ "$PLATFORM" == windows ]]; then
  find "$WORK_ROOT/vcpkg_installed/x64-windows/bin" -maxdepth 1 \
    -type f -name '*.dll' -exec cp {} "$VENDOR_DIR/" \;
fi
echo "Bundled $output into $VENDOR_DIR"
