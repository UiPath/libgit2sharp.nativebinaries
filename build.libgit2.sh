#!/usr/bin/env bash
#
# Builds libgit2 for a posix RID (linux-x64 | linux-arm64 | osx-x64 | osx-arm64) against the
# prebuilt static OpenSSL + libssh2 deps (fetched & SHA256-verified by fetch.deps.ps1), and drops
# the resulting single self-contained shared lib into nuget.package/runtimes/<rid>/native/.
#
# The posix counterpart of build.libgit2.ps1. Differences from Windows:
#   * one build only (no Schannel variants): HTTPS via OpenSSL (Linux) / SecureTransport (macOS),
#     SSH always via libssh2;
#   * the deps are linked STATICALLY into liblibgit2.{so,dylib} (no loose .so/.dylib shipped),
#     so there is nothing to copy alongside and no $ORIGIN/@loader_path RPATH to get right.
#
# The output filename is liblibgit2.{so,dylib}: LibGit2Sharp's DllImport name is "libgit2" and the
# .NET loader (and the fork's explicit Linux fallback) prepends "lib" -> liblibgit2.so.
set -euo pipefail

PLATFORM="${1:?usage: build.libgit2.sh <rid>   e.g. linux-x64|linux-arm64|osx-x64|osx-arm64}"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIBGIT2_DIR="$PROJECT_DIR/libgit2"
DEPS_DIR="$PROJECT_DIR/deps/$PLATFORM"
NATIVE_DIR="$PROJECT_DIR/nuget.package/runtimes/$PLATFORM/native"

os="${PLATFORM%%-*}"     # linux | osx
arch="${PLATFORM##*-}"   # x64   | arm64

# Fetch & hash-verify the prebuilt static deps (reuse the one cross-platform fetch implementation).
pwsh -File "$PROJECT_DIR/fetch.deps.ps1" -Platform "$PLATFORM"

if [ "$os" = "osx" ]; then
    https_backend="SecureTransport"
    ext="dylib"
    # Cross-compile x64 on the Apple Silicon runner (Intel runners are retired); arm64 is native.
    [ "$arch" = "x64" ] && osx_arch="x86_64" || osx_arch="arm64"
    osx_flag="-DCMAKE_OSX_ARCHITECTURES=${osx_arch}"
else
    https_backend="OpenSSL"
    ext="so"
    osx_flag=""
fi

# libssh2.a needs libcrypto for its SSH crypto. On Linux libgit2 already links OpenSSL for HTTPS, but
# on macOS (SecureTransport) it does not, so pass libcrypto.a explicitly. libssh2 before libcrypto:
# GNU ld resolves static archives in link order.
ssh_libs="${DEPS_DIR}/lib/libssh2.a;${DEPS_DIR}/lib/libcrypto.a"

BUILD_DIR="$LIBGIT2_DIR/build/$PLATFORM"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

echo "==> Configuring libgit2 for $PLATFORM (HTTPS=$https_backend, SSH=libssh2, static deps)"
cmake -G "Unix Makefiles" \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DBUILD_SHARED_LIBS=ON \
    -DLIBGIT2_FILENAME=libgit2 \
    -DENABLE_TRACE=ON \
    -DUSE_HTTPS="$https_backend" \
    -DUSE_SSH=libssh2 \
    -DUSE_BUNDLED_ZLIB=ON \
    -DBUILD_TESTS=OFF \
    -DBUILD_CLI=OFF \
    -DBUILD_CLAR=OFF \
    -DOPENSSL_USE_STATIC_LIBS=TRUE \
    -DOPENSSL_ROOT_DIR="$DEPS_DIR" \
    -DLIBSSH2_INCLUDE_DIRS="$DEPS_DIR/include" \
    -DLIBSSH2_LIBRARIES="$ssh_libs" \
    -DLIBSSH2_FOUND=TRUE \
    $osx_flag \
    "$LIBGIT2_DIR"

echo "==> Building libgit2"
cmake --build . --config RelWithDebInfo

# libgit2 emits a versioned lib (liblibgit2.so.1.x + symlinks, or liblibgit2.<ver>.dylib). Copy the
# real file under the canonical name LibGit2Sharp loads. -L dereferences if we matched a symlink.
built="$(find . -maxdepth 3 \( -name "liblibgit2.${ext}" -o -name "liblibgit2.${ext}.*" -o -name "liblibgit2.*.${ext}" \) | head -1)"
if [ -z "$built" ]; then
    echo "ERROR: built liblibgit2.${ext} not found under $BUILD_DIR" >&2
    exit 1
fi

mkdir -p "$NATIVE_DIR"
cp -L "$built" "$NATIVE_DIR/liblibgit2.${ext}"
echo "==> Staged $NATIVE_DIR/liblibgit2.${ext} (from $built)"
