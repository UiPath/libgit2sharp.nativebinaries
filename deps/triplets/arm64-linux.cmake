# Static arm64 Linux deps, built with -fPIC so libssh2.a + libcrypto.a can be linked INTO the single
# libgit2.so we ship. Static avoids shipping loose .so files and the $ORIGIN/RPATH resolution dance
# (and the risk of picking up a system libcrypto). Shadows vcpkg's stock (static, non-PIC) arm64-linux.
set(VCPKG_TARGET_ARCHITECTURE arm64)
set(VCPKG_CRT_LINKAGE dynamic)
set(VCPKG_LIBRARY_LINKAGE static)
set(VCPKG_CMAKE_SYSTEM_NAME Linux)
set(VCPKG_C_FLAGS "-fPIC")
set(VCPKG_CXX_FLAGS "-fPIC")
