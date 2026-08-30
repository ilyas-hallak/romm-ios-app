#!/bin/sh
# Builds a standalone Flycast (Dreamcast) libretro core for romm-app as a
# single self-contained .dylib, then wraps it as a .framework following
# romm-app's Vendor/Libretro/ naming convention.
#
#   Output: Vendor/Libretro/flycast_libretro_ios.dylib   (+ .framework)
#           Vendor/Libretro/flycast_libretro_tvos.dylib  (+ .framework)
#
# Usage: build-flycast.sh [ios|tvos]   (default: ios)
#
# ---------------------------------------------------------------------------
# WHY THIS DIFFERS FROM CABINET
#
# Cabinet links ~18 libretro cores STATICALLY into one app binary, so it had
# to rename every core's retro_* symbols to a per-core prefix (dc_retro_*)
# via a C wrapper + `ld -r -exported_symbols_list`, otherwise the identically
# named retro_run/retro_init/bundled-zlib symbols of all cores would collide.
#
# romm-app loads each core at RUNTIME via dlopen() with RTLD_LOCAL as a
# SEPARATE .dylib/.framework. Each core lives in its own dylib namespace, so
# there is NO symbol collision and the prefix trick is unnecessary. We simply
# keep CMake's own flycast_libretro.dylib, which already exports the plain
# retro_* symbols that romm-app's LibretroFrontend expects (same as the
# existing pcsx_rearmed_libretro_ios.dylib, which exports 25 plain _retro_*).
#
# What we KEEP from Cabinet: every interpreter-related build flag and the two
# source patches. Those are what make Flycast run without a JIT (iOS/tvOS
# app processes have no JIT entitlement) and what fix the load/unload
# lifecycle. See BUILD-NOTES.md for the full rationale per item.
# ---------------------------------------------------------------------------
set -e

PLATFORM=${1:-ios}

# --- Locate romm-app repo (edit ROMM_APP if this script lives elsewhere) ---
ROMM_APP="${ROMM_APP:-/Users/ilyashallak/Privat/Projects/romm-app}"
WORK="${WORK:-$ROMM_APP/Vendor/Libretro/.build/flycast}"
SRC="$WORK/src"
BUILD="$WORK/build-$PLATFORM"
OUT="$ROMM_APP/Vendor/Libretro"
JOBS=$(sysctl -n hw.ncpu)

# Pin to the commit Cabinet shipped for GPL reproducibility. Set to empty to
# build upstream master instead. Both patch anchors below were verified to
# exist at this commit and on master.
FLYCAST_COMMIT="${FLYCAST_COMMIT:-a172e0001351}"

case "$PLATFORM" in
ios)
    SDK=$(xcrun -sdk iphoneos --show-sdk-path)
    OSX_SYSROOT=iphoneos
    DEPLOYMENT_TARGET=13.0
    SYSTEM_NAME=iOS
    CORE_NAME=flycast_libretro_ios
    BUNDLE_PLATFORM=iPhoneOS
    IOS_FLAG=OFF ;;      # CMake sets its own IOS var for SYSTEM_NAME=iOS
tvos)
    SDK=$(xcrun -sdk appletvos --show-sdk-path)
    OSX_SYSROOT=appletvos
    DEPLOYMENT_TARGET=13.0
    SYSTEM_NAME=tvOS
    CORE_NAME=flycast_libretro_tvos
    BUNDLE_PLATFORM=AppleTVOS
    IOS_FLAG=ON ;;       # tvOS must masquerade as iOS to Flycast's GLES logic
*)
    echo "unknown platform: $PLATFORM (expected ios or tvos)" >&2; exit 1 ;;
esac

command -v cmake >/dev/null || { echo "cmake not found. brew install cmake" >&2; exit 1; }

# --- Fetch sources --------------------------------------------------------
if [ ! -d "$SRC" ]; then
    mkdir -p "$WORK"
    if [ -n "$FLYCAST_COMMIT" ]; then
        git clone --recurse-submodules https://github.com/flyinghead/flycast.git "$SRC"
        git -C "$SRC" checkout "$FLYCAST_COMMIT"
        git -C "$SRC" submodule update --init --recursive
    else
        git clone --recurse-submodules --depth 1 https://github.com/flyinghead/flycast.git "$SRC"
    fi
fi

# --- PATCH 1: interpreter cycle ratio (CPU_RATIO) -------------------------
# Upstream underclocks the SH4 when using the interpreter (CPU_RATIO=8 ->
# effective ~25MHz) so light scenes stay playable but heavy scenes slow down.
# Cabinet measured CPU_RATIO=2 (effective ~100MHz) as the sweet spot on A15.
# Idempotent: matches whatever integer currently sits there.
CPU_RATIO=${CPU_RATIO:-2}
sed -i '' "s/static constexpr int CPU_RATIO = [0-9]*;/static constexpr int CPU_RATIO = $CPU_RATIO;/" \
    "$SRC/core/hw/sh4/sh4_interpreter.h"

# --- PATCH 2: re-arm first_run when a game unloads ------------------------
# Flycast only calls emu.start() when first_run is set, and that flag is only
# set by retro_init/retro_deinit. A frontend that does NOT deinit the core
# between games (romm-app keeps the dlopen'd core loaded) would otherwise
# leave the 2nd game in state Loaded, rendering a black screen. Setting the
# flag on unload states the truth: the next game has not been started yet.
# Anchored on the two-line open of retro_unload_game; no-op if already patched.
perl -0pi -e '
    s/(\temu\.unloadGame\(\);\n)(\tdreampotato::term\(\);)/$1\tfirst_run = true;\n$2/
    unless /first_run = true;\n\tdreampotato::term/;
' "$SRC/shell/libretro/libretro.cpp"
grep -q 'first_run = true;' "$SRC/shell/libretro/libretro.cpp" \
    && grep -A 2 'emu.unloadGame();' "$SRC/shell/libretro/libretro.cpp" | grep -q 'first_run = true;' \
    || { echo "first_run patch did not apply; upstream shape changed" >&2; exit 1; }

# --- Build flags ----------------------------------------------------------
# -DTARGET_NO_REC : force the SH4 interpreter (no dynamic recompiler). App
#                   processes on iOS/tvOS carry no JIT entitlement.
# -DIOS (tvOS)    : makes tvOS take Flycast's GLES3 path and skips the
#                   pthread_jit_write_protect_np helper (unavailable on tvOS).
# -fno-common     : harmless here; kept for parity with Cabinet.
FLAGS="-fno-common -DTARGET_NO_REC -DIOS"

cmake -S "$SRC" -B "$BUILD" -G "Unix Makefiles" \
    -DCMAKE_SYSTEM_NAME=$SYSTEM_NAME \
    -DCMAKE_OSX_SYSROOT=$OSX_SYSROOT \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=$DEPLOYMENT_TARGET \
    -DCMAKE_BUILD_TYPE=Release \
    -DLIBRETRO=ON \
    -DUSE_OPENGL=ON \
    -DUSE_VULKAN=ON \
    -DIOS=$IOS_FLAG \
    -DCMAKE_C_FLAGS="$FLAGS" \
    -DCMAKE_CXX_FLAGS="$FLAGS"

cmake --build "$BUILD" -j"$JOBS"

# --- Collect the standalone dylib -----------------------------------------
# CMake produces flycast_libretro.dylib with plain retro_* exports already.
# No prefix wrapper, no ld -r merge: romm-app dlopen's this directly.
DYLIB=$(find "$BUILD" -name 'flycast_libretro.dylib' | head -1)
[ -n "$DYLIB" ] || { echo "flycast_libretro.dylib not found in $BUILD" >&2; exit 1; }

mkdir -p "$OUT"

# Set the dylib install_name to @rpath so it resolves once embedded.
DEST_DYLIB="$OUT/$CORE_NAME.dylib"
cp "$DYLIB" "$DEST_DYLIB"
install_name_tool -id "@rpath/$CORE_NAME.dylib" "$DEST_DYLIB"

# --- Wrap as a .framework (matches genesis_plus_gx_libretro_ios.framework) -
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
	<key>CFBundleIdentifier</key><string>org.libretro.flycast</string>
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
