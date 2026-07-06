<#
.SYNOPSIS
    Builds the prebuilt native dependencies (OpenSSL + libssh2) with vcpkg and stages a
    per-platform archive (headers + import libs + shared libs) plus a SHA256 for it.

    Intended to run in the `build-deps` GitHub Actions workflow on a GitHub runner, NOT locally.
    vcpkg builds the deps from its own maintained ports; the versions are pinned by deps/vcpkg.json
    and kept in lock-step with the openssl/libssh2 git submodules. This script asserts that the
    versions vcpkg resolved match the submodule tags (the authoritative version pins).
.PARAMETER Triplet
    vcpkg triplet to build (default 'x64-windows', a dynamic triplet producing DLLs).
.PARAMETER Platform
    Platform key used to name the archive (default 'win-x64'). Must match deps.lock.json keys.
.PARAMETER VcpkgRoot
    Path to a bootstrapped vcpkg checkout. Defaults to $env:VCPKG_ROOT then
    $env:VCPKG_INSTALLATION_ROOT (both are set on GitHub runners).
#>

Param(
    [string]$Triplet = 'x64-windows',
    [string]$Platform = 'win-x64',
    [string]$VcpkgRoot = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectDirectory = Split-Path $MyInvocation.MyCommand.Path
$depsDirectory = Join-Path $projectDirectory 'deps'
$manifestPath = Join-Path $depsDirectory 'vcpkg.json'
$installRoot = Join-Path $depsDirectory 'vcpkg_installed'
$stagingRoot = Join-Path $depsDirectory ('_staging/' + $Platform)
$archivePath = Join-Path $depsDirectory ('_staging/deps-' + $Platform + '.zip')

function Get-OpensslSubmoduleVersion {
    # OpenSSL's exact version lives in VERSION.dat (no git tags needed).
    $verFile = Join-Path $projectDirectory 'openssl/VERSION.dat'
    if (-not (Test-Path $verFile)) { throw "openssl submodule not checked out ($verFile missing)." }
    $data = @{}
    foreach ($line in Get-Content $verFile) {
        if ($line -match '^\s*(\w+)\s*=\s*(.*?)\s*$') { $data[$Matches[1]] = $Matches[2] }
    }
    return "$($data.MAJOR).$($data.MINOR).$($data.PATCH)"
}

function Get-Libssh2SubmoduleVersion {
    # libssh2's header keeps a "_DEV" suffix even on the release tag, so derive from the tag instead.
    # The submodule may be a shallow checkout without tag refs, so fetch its (small) tag set first.
    $dir = Join-Path $projectDirectory 'libssh2'
    if (-not (Test-Path (Join-Path $dir '.git'))) { throw "libssh2 submodule not checked out." }
    & git -C $dir fetch --tags --quiet origin 2>$null
    $describe = (& git -C $dir describe --tags --exact-match 2>$null)
    if (-not $describe) { throw "Could not resolve libssh2 version from git tags." }
    return ($describe -replace '^libssh2-', '').Trim()
}

function Get-SubmoduleSha($submodule) {
    $dir = Join-Path $projectDirectory $submodule
    if (-not (Test-Path (Join-Path $dir '.git'))) { return 'unknown' }
    return (& git -C $dir rev-parse HEAD).Trim()
}

function Get-OverrideVersion($name) {
    $o = $manifest.overrides | Where-Object { $_.name -eq $name } | Select-Object -First 1
    if (-not $o) { throw "deps/vcpkg.json has no override for '$name'." }
    return "$($o.version)"
}

# --- Resolve vcpkg ------------------------------------------------------------
if (-not $VcpkgRoot) {
    if ($env:VCPKG_ROOT) { $VcpkgRoot = $env:VCPKG_ROOT }
    elseif ($env:VCPKG_INSTALLATION_ROOT) { $VcpkgRoot = $env:VCPKG_INSTALLATION_ROOT }
    else { throw "No vcpkg found. Set -VcpkgRoot or the VCPKG_ROOT / VCPKG_INSTALLATION_ROOT env var." }
}
$vcpkg = Join-Path $VcpkgRoot 'vcpkg.exe'
if (-not (Test-Path $vcpkg)) { $vcpkg = Join-Path $VcpkgRoot 'vcpkg' }   # non-Windows
if (-not (Test-Path $vcpkg)) { throw "vcpkg executable not found under '$VcpkgRoot'." }

# The manifest's builtin-baseline commit must be present in the vcpkg git history so vcpkg can
# resolve the pinned versions from its versions database. Fetch it if the runner's vcpkg is older.
$manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
$baseline = $manifest.'builtin-baseline'
& git -C $VcpkgRoot cat-file -e "$baseline^{commit}" 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "vcpkg baseline $baseline not present locally; fetching origin..."
    & git -C $VcpkgRoot fetch --no-tags --quiet origin
    & git -C $VcpkgRoot cat-file -e "$baseline^{commit}" 2>$null
    if ($LASTEXITCODE -ne 0) { throw "vcpkg baseline commit $baseline is not reachable from origin." }
}

# --- Build --------------------------------------------------------------------
Write-Host "==> vcpkg install (triplet=$Triplet) from $manifestPath"
& $vcpkg install `
    --triplet $Triplet `
    --x-manifest-root=$depsDirectory `
    --x-install-root=$installRoot `
    --clean-after-build
if ($LASTEXITCODE -ne 0) { throw "vcpkg install failed with exit code $LASTEXITCODE." }

# --- Assert versions: submodule pin == deps/vcpkg.json override == what vcpkg built -----------
$expectedOpenssl = Get-OpensslSubmoduleVersion
$expectedLibssh2 = Get-Libssh2SubmoduleVersion

$listing = & $vcpkg list --x-install-root=$installRoot
function Get-InstalledVersion($package) {
    # `vcpkg list` prints lines like: "openssl:x64-windows   3.6.3   General purpose ..."
    $line = $listing | Where-Object { $_ -match "^$package(:|\s)" } | Select-Object -First 1
    if (-not $line) { throw "Package '$package' not found in vcpkg install listing." }
    # Second whitespace-delimited column is the version, possibly with a #port-version suffix.
    $version = ($line -split '\s+')[1]
    return ($version -split '#')[0]
}
$installedOpenssl = Get-InstalledVersion 'openssl'
$installedLibssh2 = Get-InstalledVersion 'libssh2'

function Assert-Version($name, $submodule, $override, $installed) {
    Write-Host "${name} : submodule=$submodule  override=$override  vcpkg=$installed"
    if ($submodule -ne $override) {
        throw "${name}: submodule pins $submodule but deps/vcpkg.json override is $override. Keep them in sync."
    }
    if ($installed -ne $submodule) {
        throw "${name}: vcpkg built $installed but the pin is $submodule. " +
              "Update the deps/vcpkg.json override to a version present in vcpkg's registry, and bump the submodule to match."
    }
}
Assert-Version 'openssl' $expectedOpenssl (Get-OverrideVersion 'openssl') $installedOpenssl
Assert-Version 'libssh2' $expectedLibssh2 (Get-OverrideVersion 'libssh2') $installedLibssh2

# --- Stage the archive --------------------------------------------------------
$tripletDir = Join-Path $installRoot $Triplet
if (-not (Test-Path $tripletDir)) { throw "Expected install output at '$tripletDir' was not produced." }

if (Test-Path $stagingRoot) { Remove-Item $stagingRoot -Recurse -Force }
New-Item -ItemType Directory -Path $stagingRoot | Out-Null
foreach ($sub in @('include', 'lib', 'bin')) {
    $src = Join-Path $tripletDir $sub
    if (Test-Path $src) { Copy-Item $src -Destination $stagingRoot -Recurse -Force }
}
# Drop debug symbols: they are large and are stripped from the package downstream anyway.
Get-ChildItem -Path $stagingRoot -Recurse -Filter *.pdb | Remove-Item -Force

$manifestTxt = Join-Path $stagingRoot 'manifest.txt'
@(
    "platform      = $Platform"
    "triplet       = $Triplet"
    "openssl       = $installedOpenssl (submodule $(Get-SubmoduleSha 'openssl'))"
    "libssh2       = $installedLibssh2 (submodule $(Get-SubmoduleSha 'libssh2'))"
    "vcpkg-baseline= $baseline"
) | Set-Content -Path $manifestTxt -Encoding utf8

# --- Zip + hash ---------------------------------------------------------------
if (Test-Path $archivePath) { Remove-Item $archivePath -Force }
Compress-Archive -Path (Join-Path $stagingRoot '*') -DestinationPath $archivePath -CompressionLevel Optimal
$sha256 = (Get-FileHash -Algorithm SHA256 -Path $archivePath).Hash.ToLower()
Set-Content -Path "$archivePath.sha256" -Value $sha256 -Encoding ascii -NoNewline

# Release tag is derived from the built versions so it tracks the submodule pins automatically.
$tag = "deps-openssl-${installedOpenssl}_libssh2-${installedLibssh2}"

Write-Host "==> Archive : $archivePath"
Write-Host "==> SHA256  : $sha256"
Write-Host "==> Tag     : $tag"

# Surface outputs to the GitHub Actions job when running in CI.
if ($env:GITHUB_OUTPUT) {
    Add-Content -Path $env:GITHUB_OUTPUT -Value "archive=$archivePath"
    Add-Content -Path $env:GITHUB_OUTPUT -Value "sha256=$sha256"
    Add-Content -Path $env:GITHUB_OUTPUT -Value "platform=$Platform"
    Add-Content -Path $env:GITHUB_OUTPUT -Value "tag=$tag"
}
