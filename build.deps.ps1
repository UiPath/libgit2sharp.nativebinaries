<#
.SYNOPSIS
    Builds ONE native dependency (OpenSSL or libssh2) with vcpkg and stages a per-platform archive
    (headers + import lib + shared lib, no .pdb) plus its SHA256 and release tag.

    Each dependency is built and published independently so that (for example) frequent OpenSSL
    patch bumps never rebuild or re-publish libssh2. Intended to run in the build-openssl.yml /
    build-libssh2.yml GitHub workflows on a runner, NOT locally.

    vcpkg builds from its own maintained ports; the version is pinned by deps/<component>/vcpkg.json
    and kept in lock-step with the corresponding git submodule tag (the authoritative version pin),
    which this script asserts.
.PARAMETER Component
    Which dependency to build: 'openssl' or 'libssh2'.
.PARAMETER Triplet
    vcpkg triplet (default 'x64-windows', a dynamic triplet producing DLLs).
.PARAMETER Platform
    Platform key used to name the archive (default 'win-x64'). Must match deps.lock.json keys.
.PARAMETER VcpkgRoot
    Path to a bootstrapped vcpkg checkout. Defaults to $env:VCPKG_ROOT then
    $env:VCPKG_INSTALLATION_ROOT (both set on GitHub runners).
#>

Param(
    [Parameter(Mandatory = $true)][ValidateSet('openssl', 'libssh2')][string]$Component,
    [string]$Triplet = 'x64-windows',
    [string]$Platform = 'win-x64',
    [string]$VcpkgRoot = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectDirectory = Split-Path $MyInvocation.MyCommand.Path
$depsDirectory = Join-Path $projectDirectory 'deps'
$manifestDir = Join-Path $depsDirectory $Component
$manifestPath = Join-Path $manifestDir 'vcpkg.json'
$buildRoot = Join-Path $depsDirectory ("_build/" + $Component)
$installRoot = Join-Path $buildRoot 'vcpkg_installed'
$stagingRoot = Join-Path $buildRoot 'stage'
$archivePath = Join-Path $depsDirectory ('_staging/' + $Component + '-' + $Platform + '.zip')

# Which files each component contributes to the merged deps/<platform>/ tree (no .pdb).
$componentSpec = @{
    openssl = @{
        bin         = @('libcrypto-3-x64.dll', 'libssl-3-x64.dll', 'legacy.dll')
        lib         = @('libcrypto.lib', 'libssl.lib')
        includeDirs = @('openssl')
        includeFiles = @()
    }
    libssh2 = @{
        bin         = @('libssh2.dll')
        lib         = @('libssh2.lib')
        includeDirs = @()
        includeFiles = @('libssh2.h', 'libssh2_publickey.h', 'libssh2_sftp.h')
    }
}
$spec = $componentSpec[$Component]

function Get-OpensslSubmoduleVersion {
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

# --- Resolve vcpkg ------------------------------------------------------------
if (-not $VcpkgRoot) {
    if ($env:VCPKG_ROOT) { $VcpkgRoot = $env:VCPKG_ROOT }
    elseif ($env:VCPKG_INSTALLATION_ROOT) { $VcpkgRoot = $env:VCPKG_INSTALLATION_ROOT }
    else { throw "No vcpkg found. Set -VcpkgRoot or the VCPKG_ROOT / VCPKG_INSTALLATION_ROOT env var." }
}
$vcpkg = Join-Path $VcpkgRoot 'vcpkg.exe'
if (-not (Test-Path $vcpkg)) { $vcpkg = Join-Path $VcpkgRoot 'vcpkg' }   # non-Windows
if (-not (Test-Path $vcpkg)) { throw "vcpkg executable not found under '$VcpkgRoot'." }

$manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
$baseline = $manifest.'builtin-baseline'

function Get-OverrideVersion($name) {
    $o = $manifest.overrides | Where-Object { $_.name -eq $name } | Select-Object -First 1
    if (-not $o) { throw "$manifestPath has no override for '$name'." }
    return "$($o.version)"
}

# The manifest's builtin-baseline commit must be present in the vcpkg git history so vcpkg can
# resolve the pinned versions from its versions database. Fetch it if the runner's vcpkg is older.
& git -C $VcpkgRoot cat-file -e "$baseline^{commit}" 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "vcpkg baseline $baseline not present locally; fetching origin..."
    & git -C $VcpkgRoot fetch --no-tags --quiet origin
    & git -C $VcpkgRoot cat-file -e "$baseline^{commit}" 2>$null
    if ($LASTEXITCODE -ne 0) { throw "vcpkg baseline commit $baseline is not reachable from origin." }
}

# --- Build --------------------------------------------------------------------
Write-Host "==> vcpkg install $Component (triplet=$Triplet) from $manifestPath"
& $vcpkg install `
    --triplet $Triplet `
    --x-manifest-root=$manifestDir `
    --x-install-root=$installRoot `
    --clean-after-build
if ($LASTEXITCODE -ne 0) { throw "vcpkg install failed with exit code $LASTEXITCODE." }

# --- Assert version: submodule pin == override == what vcpkg built ------------
$listing = & $vcpkg list --x-install-root=$installRoot
function Get-InstalledVersion($package) {
    $line = $listing | Where-Object { $_ -match "^$package(:|\s)" } | Select-Object -First 1
    if (-not $line) { throw "Package '$package' not found in vcpkg install listing." }
    $version = ($line -split '\s+')[1]
    return ($version -split '#')[0]
}

if ($Component -eq 'openssl') { $submoduleVersion = Get-OpensslSubmoduleVersion }
else { $submoduleVersion = Get-Libssh2SubmoduleVersion }
$overrideVersion = Get-OverrideVersion $Component
$installedVersion = Get-InstalledVersion $Component

Write-Host "${Component} : submodule=$submoduleVersion  override=$overrideVersion  vcpkg=$installedVersion"
if ($submoduleVersion -ne $overrideVersion) {
    throw "${Component}: submodule pins $submoduleVersion but deps/$Component/vcpkg.json override is $overrideVersion. Keep them in sync."
}
if ($installedVersion -ne $submoduleVersion) {
    throw "${Component}: vcpkg built $installedVersion but the pin is $submoduleVersion. " +
          "Update the deps/$Component/vcpkg.json override to a version present in vcpkg's registry, and bump the submodule to match."
}

# --- Stage the component's files ----------------------------------------------
$tripletDir = Join-Path $installRoot $Triplet
if (-not (Test-Path $tripletDir)) { throw "Expected install output at '$tripletDir' was not produced." }

if (Test-Path $stagingRoot) { Remove-Item $stagingRoot -Recurse -Force }
New-Item -ItemType Directory -Path $stagingRoot | Out-Null

function Copy-Required($src, $destDir) {
    if (-not (Test-Path $src)) { throw "Expected file '$src' was not produced by vcpkg." }
    New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    Copy-Item $src -Destination $destDir -Force
}

foreach ($f in $spec.bin) {
    # legacy.dll is optional depending on the OpenSSL build; the rest are required.
    $src = Join-Path $tripletDir "bin/$f"
    if ((Test-Path $src) -or ($f -ne 'legacy.dll')) { Copy-Required $src (Join-Path $stagingRoot 'bin') }
}
foreach ($f in $spec.lib) { Copy-Required (Join-Path $tripletDir "lib/$f") (Join-Path $stagingRoot 'lib') }
foreach ($f in $spec.includeFiles) { Copy-Required (Join-Path $tripletDir "include/$f") (Join-Path $stagingRoot 'include') }
foreach ($d in $spec.includeDirs) {
    $src = Join-Path $tripletDir "include/$d"
    if (-not (Test-Path $src)) { throw "Expected include dir '$src' was not produced by vcpkg." }
    Copy-Item $src -Destination (Join-Path $stagingRoot 'include') -Recurse -Force
}

$manifestTxt = Join-Path $stagingRoot 'manifest.txt'
@(
    "component     = $Component"
    "version       = $installedVersion"
    "platform      = $Platform"
    "triplet       = $Triplet"
    "submodule     = $(Get-SubmoduleSha $Component)"
    "vcpkg-baseline= $baseline"
) | Set-Content -Path $manifestTxt -Encoding utf8

# --- Zip + hash ---------------------------------------------------------------
New-Item -ItemType Directory -Path (Split-Path $archivePath) -Force | Out-Null
if (Test-Path $archivePath) { Remove-Item $archivePath -Force }
Compress-Archive -Path (Join-Path $stagingRoot '*') -DestinationPath $archivePath -CompressionLevel Optimal
$sha256 = (Get-FileHash -Algorithm SHA256 -Path $archivePath).Hash.ToLower()
Set-Content -Path "$archivePath.sha256" -Value $sha256 -Encoding ascii -NoNewline

$tag = "deps-$Component-$installedVersion"
Write-Host "==> Archive : $archivePath"
Write-Host "==> SHA256  : $sha256"
Write-Host "==> Tag     : $tag"

if ($env:GITHUB_OUTPUT) {
    Add-Content -Path $env:GITHUB_OUTPUT -Value "archive=$archivePath"
    Add-Content -Path $env:GITHUB_OUTPUT -Value "sha256=$sha256"
    Add-Content -Path $env:GITHUB_OUTPUT -Value "platform=$Platform"
    Add-Content -Path $env:GITHUB_OUTPUT -Value "component=$Component"
    Add-Content -Path $env:GITHUB_OUTPUT -Value "version=$installedVersion"
    Add-Content -Path $env:GITHUB_OUTPUT -Value "tag=$tag"
}
