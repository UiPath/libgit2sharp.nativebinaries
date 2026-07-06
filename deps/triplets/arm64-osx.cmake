# Dynamic arm64 macOS triplet: the stock arm64-osx triplet is static, but we ship shared libraries
# (libcrypto.dylib / libssh2.dylib) in the NuGet to be loaded at runtime, matching the other RIDs.
set(VCPKG_TARGET_ARCHITECTURE arm64)
set(VCPKG_CRT_LINKAGE dynamic)
set(VCPKG_LIBRARY_LINKAGE dynamic)
set(VCPKG_CMAKE_SYSTEM_NAME Darwin)
set(VCPKG_OSX_ARCHITECTURES arm64)
