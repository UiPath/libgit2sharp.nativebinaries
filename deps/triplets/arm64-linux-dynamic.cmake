# Dynamic arm64 Linux triplet: the stock `arm64-linux` triplet is static, but we need shared
# libraries (libcrypto.so / libssh2.so) to ship in the NuGet and be loaded at runtime.
set(VCPKG_TARGET_ARCHITECTURE arm64)
set(VCPKG_CRT_LINKAGE dynamic)
set(VCPKG_LIBRARY_LINKAGE dynamic)
set(VCPKG_CMAKE_SYSTEM_NAME Linux)
