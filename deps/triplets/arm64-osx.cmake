# Static arm64 macOS deps. macOS code is always PIC, so the static .a link cleanly into the single
# libgit2.dylib we ship. Shadows vcpkg's stock (static) arm64-osx to make the linkage explicit.
set(VCPKG_TARGET_ARCHITECTURE arm64)
set(VCPKG_CRT_LINKAGE dynamic)
set(VCPKG_LIBRARY_LINKAGE static)
set(VCPKG_CMAKE_SYSTEM_NAME Darwin)
set(VCPKG_OSX_ARCHITECTURES arm64)
