#!/bin/sh
# Builds a standalone PPSSPP (PSP) libretro core for romm-app as a single
# self-contained .dylib, then wraps it as a .framework following romm-app's
# Vendor/Libretro/ naming convention.
#
#   Output: Vendor/Libretro/ppsspp_libretro_ios.dylib   (+ .framework)
#           Vendor/Libretro/ppsspp_libretro_tvos.dylib  (+ .framework)
#
# Usage: build-ppsspp.sh [ios|tvos]   (default: ios)
#
# ---------------------------------------------------------------------------
# WHY THIS DIFFERS FROM CABINET
#
# Same as build-flycast.sh: Cabinet static-links every core into one binary
# and therefore renames retro_* -> psp_retro_* via a C wrapper + ld -r to
# avoid symbol collisions. romm-app dlopen()s each core as its own dylib with
# RTLD_LOCAL, so there is no collision and the prefix trick is dropped. We
# ship CMake's own ppsspp_libretro.dylib (plain retro_* exports).
#
# The prebuilt ffmpeg static archives that PPSSPP vendors get linked INTO the
# dylib by CMake's own link step automatically (USE_SYSTEM_FFMPEG=OFF), so we
# do NOT need Cabinet's manual ffmpeg ld -r step either. The shared library is
# self-contained.
#
# INTERPRETER NOTE (runtime, not build-time): PPSSPP picks its CPU backend at
# runtime from the ppsspp_cpu_core libretro option. On a platform where
# SYSPROP_CAN_JIT is false (no JIT entitlement), "IR JIT" resolves to the IR
# INTERPRETER. romm-app must force ppsspp_cpu_core = "IR interpreter" (or
# "IR JIT" which falls back) via its core-options mechanism. The ARM64 JIT
# backend still compiles in but is never asked to run. See BUILD-NOTES.md.
# ---------------------------------------------------------------------------
set -e

PLATFORM=${1:-ios}

# --- Locate romm-app repo (edit ROMM_APP if this script lives elsewhere) ---
ROMM_APP="${ROMM_APP:-/Users/ilyashallak/Privat/Projects/romm-app}"
WORK="${WORK:-$ROMM_APP/Vendor/Libretro/.build/ppsspp}"
SRC="$WORK/src"
BUILD="$WORK/build-$PLATFORM"
OUT="$ROMM_APP/Vendor/Libretro"
JOBS=$(sysctl -n hw.ncpu)

# Optional pin for GPL reproducibility. Cabinet's docs/licenses.md lists no
# PPSSPP commit (PPSSPP was not part of Cabinet's shipped core set), so this
# defaults to master. Set PPSSPP_COMMIT to pin once you choose one.
PPSSPP_COMMIT="${PPSSPP_COMMIT:-}"

case "$PLATFORM" in
ios)
    SDK=$(xcrun -sdk iphoneos --show-sdk-path)
    IOS_PLATFORM=OS
    DEPLOYMENT_TARGET=13.0
    FFMPEG_ARCH=ios/universal
    CORE_NAME=ppsspp_libretro_ios
    BUNDLE_PLATFORM=iPhoneOS ;;
tvos)
    SDK=$(xcrun -sdk appletvos --show-sdk-path)
    IOS_PLATFORM=TVOS
    DEPLOYMENT_TARGET=13.0
    FFMPEG_ARCH=tvos/arm64
    CORE_NAME=ppsspp_libretro_tvos
    BUNDLE_PLATFORM=AppleTVOS ;;
*)
    echo "unknown platform: $PLATFORM (expected ios or tvos)" >&2; exit 1 ;;
esac

command -v cmake >/dev/null || { echo "cmake not found. brew install cmake" >&2; exit 1; }

# --- Fetch sources --------------------------------------------------------
if [ ! -d "$SRC" ]; then
    mkdir -p "$WORK"
    if [ -n "$PPSSPP_COMMIT" ]; then
        git clone --recurse-submodules https://github.com/hrydgard/ppsspp.git "$SRC"
        git -C "$SRC" checkout "$PPSSPP_COMMIT"
        git -C "$SRC" submodule update --init --recursive
    else
        git clone --recurse-submodules --depth 1 https://github.com/hrydgard/ppsspp.git "$SRC"
    fi
fi

# Sanity-check that the prebuilt ffmpeg archives exist for this platform.
FFMPEG_LIBS="$SRC/ffmpeg/$FFMPEG_ARCH/lib"
if [ ! -f "$FFMPEG_LIBS/libavcodec.a" ]; then
    echo "WARNING: prebuilt ffmpeg not found at $FFMPEG_LIBS" >&2
    echo "         PPSSPP's ffmpeg lives in a submodule; make sure submodules" >&2
    echo "         were fetched, or run ffmpeg/ios-build.sh per upstream." >&2
fi

# --- Configure ------------------------------------------------------------
# PPSSPP ships its own iOS/tvOS toolchain (cmake/Toolchains/ios.cmake). It
# sets USING_GLES2, MOBILE_DEVICE, and for IOS_PLATFORM=TVOS points the
# ffmpeg lookup at ffmpeg/tvos/arm64. LIBRETRO + IOS is a combination the
# upstream CMakeLists supports by name, so no masquerade is needed here.
#
# No -DTARGET_NO_REC equivalent: the interpreter is selected at runtime (see
# header). -fno-common kept for parity with Cabinet.
cmake -S "$SRC" -B "$BUILD" -G "Unix Makefiles" \
    -DCMAKE_TOOLCHAIN_FILE="$SRC/cmake/Toolchains/ios.cmake" \
    -DIOS_PLATFORM=$IOS_PLATFORM \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=$DEPLOYMENT_TARGET \
    -DCMAKE_BUILD_TYPE=Release \
    -DLIBRETRO=ON \
    -DUSE_SYSTEM_FFMPEG=OFF \
    -DUSE_DISCORD=OFF \
    -DCMAKE_C_FLAGS=-fno-common \
    -DCMAKE_CXX_FLAGS=-fno-common

cmake --build "$BUILD" -j"$JOBS" --target ppsspp_libretro

# --- Collect the standalone dylib -----------------------------------------
DYLIB=$(find "$BUILD" -name 'ppsspp_libretro.dylib' | head -1)
[ -n "$DYLIB" ] || { echo "ppsspp_libretro.dylib not found in $BUILD" >&2; exit 1; }

mkdir -p "$OUT"

DEST_DYLIB="$OUT/$CORE_NAME.dylib"
cp "$DYLIB" "$DEST_DYLIB"
install_name_tool -id "@rpath/$CORE_NAME.dylib" "$DEST_DYLIB"

# --- Wrap as a .framework -------------------------------------------------
FW="$OUT/$CORE_NAME.framework"
rm -rf "$FW"
mkdir -p "$FW"
cp "$DYLIB" "$FW/$CORE_NAME"
install_name_tool -id "@rpath/$CORE_NAME.framework/$CORE_NAME" "$FW/$CORE_NAME"
cat > "$FW/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key><string>en</string>
	<key>CFBundleExecutable</key><string>$CORE_NAME</string>
	<key>CFBundleIdentifier</key><string>org.libretro.ppsspp</string>
	<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
	<key>CFBundleName</key><string>$CORE_NAME</string>
	<key>CFBundlePackageType</key><string>FMWK</string>
	<key>CFBundleShortVersionString</key><string>1.0</string>
	<key>CFBundleSupportedPlatforms</key><array><string>$BUNDLE_PLATFORM</string></array>
	<key>CFBundleVersion</key><string>1</string>
	<key>MinimumOSVersion</key><string>$DEPLOYMENT_TARGET</string>
</dict>
</plist>
PLIST

echo "Wrote $DEST_DYLIB"
echo "Wrote $FW"
echo "Exports (should be plain _retro_*, no prefix):"
nm -g "$DEST_DYLIB" 2>/dev/null | grep ' T _retro_' | head
echo
echo "REMINDER: force ppsspp_cpu_core = 'IR interpreter' via romm-app core options."
