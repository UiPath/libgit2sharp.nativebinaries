Building the UiPath LibGit2Sharp native binaries
================================================

The native dependencies (OpenSSL + libssh2) are NO LONGER built here. Each is compiled
independently by its own GitHub Actions workflow (`build-openssl.yml` / `build-libssh2.yml`, via
vcpkg from the `openssl` / `libssh2` submodules), published as a SHA256-verified per-component
archive on a GitHub Release, and fetched by `fetch.deps.ps1` during the libgit2 build. This removes
the old Perl / NASM / nmake / OpenSSL build toolchain from this build and is what lets us target
additional platforms. They are split so a frequent OpenSSL bump never rebuilds libssh2.

Prerequisites for building libgit2 (this repo):
- Build Tools for Visual Studio 2019, "Desktop development with C++" workload
- CMake (in PATH)
- The `libgit2` submodule updated (recursive). OpenSSL / libssh2 no longer need to be built.

Building:
- From a Developer Command Prompt, run `uipath-build.ps1` with PowerShell. It calls
  `build.libgit2.ps1` (which first runs `fetch.deps.ps1` to download + hash-verify the prebuilt
  OpenSSL/libssh2 archive) and then `buildpackage.ps1`.

The prebuilt native dependencies
--------------------------------
- `deps/openssl/vcpkg.json`, `deps/libssh2/vcpkg.json`
                      - per-component vcpkg manifests pinning each version (kept in lock-step with
                        the submodule tags; libssh2 uses the OpenSSL backend, zlib disabled).
- `build.deps.ps1`    - run by the build workflows on a GitHub runner: `-Component openssl|libssh2`
                        builds that dep with vcpkg, asserts submodule == manifest override == built
                        version, stages a per-platform archive (include/ lib/ bin/, no .pdb) and
                        prints its SHA256 + release tag.
- `deps.lock.json`    - per-component, per-platform archive URL + REQUIRED SHA256. `fetch.deps.ps1`
                        fails hard if a SHA256 is empty or does not match the download.
- `fetch.deps.ps1`    - downloads + verifies + extracts both components (merged) to `deps/<platform>/`.

To change the OpenSSL or libssh2 version:
1. Move the submodule to the desired release tag (e.g. `git -C openssl checkout openssl-3.6.3`).
2. Update the `overrides` in `deps/<component>/vcpkg.json` to a version that exists in vcpkg's
   registry (see https://github.com/microsoft/vcpkg/tree/master/versions).
3. Run the matching workflow (`build-openssl` / `build-libssh2`). Copy the SHA256 and release tag
   it prints into `deps.lock.json`. An OpenSSL major bump (e.g. 3.x -> 4.x) also requires re-running
   `build-libssh2` (libssh2's linked crypto DLL name changes).

Versioning:
The version of the package is determined by the `libgit2` version. For example, when using
libgit2 v1.7.1 the package is v1.7.1-v1, where `-v1` is our own revision number.

Using WinGet to install the build dependencies:

winget install -e --id Microsoft.VisualStudio.2019.BuildTools --override "--passive --wait --add Microsoft.VisualStudio.Workload.VCTools;includeRecommended"
winget install --id=Kitware.CMake -e
