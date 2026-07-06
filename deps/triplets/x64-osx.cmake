# x64 macOS, cross-compiled on an Apple Silicon runner: Intel (macos-13) runners are scarce, slow
# to schedule, and being retired by GitHub. Force the target arch so vcpkg (and OpenSSL's own
# Configure) emit x86_64 binaries regardless of the arm64 host.
set(VCPKG_TARGET_ARCHITECTURE x64)
set(VCPKG_CRT_LINKAGE dynamic)
set(VCPKG_LIBRARY_LINKAGE dynamic)
set(VCPKG_CMAKE_SYSTEM_NAME Darwin)
set(VCPKG_OSX_ARCHITECTURES x86_64)
