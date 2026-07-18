#!/usr/bin/env sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BUILD_DIR="${TMPDIR:-/tmp}/flutter_mimc_native_test"
mkdir -p "$BUILD_DIR"

case "$(uname -s)" in
  Darwin)
    SDK_LIBRARY="$BUILD_DIR/libmimc_sdk.dylib"
    SHARED_FLAGS="-dynamiclib"
    PLATFORM_LDFLAGS=""
    ;;
  Linux)
    SDK_LIBRARY="$BUILD_DIR/libmimc_sdk.so"
    SHARED_FLAGS="-shared -fPIC"
    PLATFORM_LDFLAGS="-ldl"
    ;;
  *)
    echo "Use the equivalent MSVC build for test/native on Windows." >&2
    exit 2
    ;;
esac

${CXX:-c++} -std=c++17 -Wall -Wextra -Wpedantic -Werror \
  "$ROOT/test/native/portable_crypto_test.cpp" \
  "$ROOT/tool/desktop_sdk/portable_crypto.cpp" \
  -o "$BUILD_DIR/portable_crypto_test"
"$BUILD_DIR/portable_crypto_test"

${CXX:-c++} -std=c++17 -Wall -Wextra -Wpedantic -Werror $SHARED_FLAGS \
  "$ROOT/test/native/mock_mimc_sdk.cpp" -o "$SDK_LIBRARY"
${CXX:-c++} -std=c++17 -Wall -Wextra -Wpedantic -Werror \
  "$ROOT/test/native/bridge_test.cpp" \
  "$ROOT/src/flutter_mimc_bridge.cpp" \
  -o "$BUILD_DIR/bridge_test" $PLATFORM_LDFLAGS ${LDFLAGS:-}

FLUTTER_MIMC_CPP_SDK_LIBRARY="$SDK_LIBRARY" "$BUILD_DIR/bridge_test"

OFFICIAL_SDK_LIBRARY=${FLUTTER_MIMC_OFFICIAL_SDK_LIBRARY:-}
if [ -z "$OFFICIAL_SDK_LIBRARY" ]; then
  case "$(uname -s)" in
    Darwin)
      [ ! -f "$ROOT/macos/Vendor/libmimc_sdk.dylib" ] || \
        OFFICIAL_SDK_LIBRARY="$ROOT/macos/Vendor/libmimc_sdk.dylib"
      ;;
    Linux)
      [ ! -f "$ROOT/linux/vendor/libmimc_sdk.so" ] || \
        OFFICIAL_SDK_LIBRARY="$ROOT/linux/vendor/libmimc_sdk.so"
      ;;
  esac
fi

if [ -n "$OFFICIAL_SDK_LIBRARY" ]; then
  ${CXX:-c++} -std=c++17 -Wall -Wextra -Wpedantic -Werror \
    "$ROOT/test/native/sdk_smoke_test.cpp" \
    "$ROOT/src/flutter_mimc_bridge.cpp" \
    -o "$BUILD_DIR/sdk_smoke_test" $PLATFORM_LDFLAGS ${LDFLAGS:-}
  FLUTTER_MIMC_CPP_SDK_LIBRARY="$OFFICIAL_SDK_LIBRARY" \
    "$BUILD_DIR/sdk_smoke_test"
fi
