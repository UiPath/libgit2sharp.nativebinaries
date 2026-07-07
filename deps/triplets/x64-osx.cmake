# Static x64 macOS deps, cross-compiled on an Apple Silicon runner (Intel macos-13 runners are
# scarce and being retired). macOS code is always PIC, so the static .a link cleanly into the
# single libgit2.dylib we ship. VCPKG_OSX_ARCHITECTURES forces x86_64 output on the arm64 host.
set(VCPKG_TARGET_ARCHITECTURE x64)
set(VCPKG_CRT_LINKAGE dynamic)
set(VCPKG_LIBRARY_LINKAGE static)
set(VCPKG_CMAKE_SYSTEM_NAME Darwin)
set(VCPKG_OSX_ARCHITECTURES x86_64)
