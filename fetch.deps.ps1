<#
.SYNOPSIS
    Downloads the prebuilt native-deps archive (OpenSSL + libssh2) for the current platform,
    verifies its SHA256 against deps.lock.json, and extracts it to deps/<platform>/.

    The libgit2 build calls this instead of compiling OpenSSL/libssh2 from source. Verification is
    mandatory: if the lockfile SHA256 is empty or does not match the download, this fails hard.
.PARAMETER Platform
    Platform key into deps.lock.json (e.g. 'win-x64'). Defaults to auto-detecting the host.
.PARAMETER Force
    Re-download and re-extract even if the target directory already exists.
#>

Param(
    [string]$Platform = '',
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
# tar extraction below checks $LASTEXITCODE itself; don't let a non-zero exit auto-throw first
# (PowerShell 7.4+ defaults this to $true). Harmless no-op on Windows PowerShell 5.1.
$PSNativeCommandUseErrorActionPreference = $false

$projectDirectory = Split-Path $MyInvocation.MyCommand.Path
$lockPath = Join-Path $projectDirectory 'deps.lock.json'
$depsDirectory = Join-Path $projectDirectory 'deps'
$cacheDirectory = Join-Path $depsDirectory '_cache'

function Get-CurrentPlatform {
    $arch = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString().ToLower()
    $archKey = switch ($arch) {
        'x64'   { 'x64' }
        'arm64' { 'arm64' }
        default { throw "Unsupported OS architecture '$arch'." }
    }
    if ($IsWindows -or ($null -eq $IsWindows)) { return "win-$archKey" }   # $IsWindows is $null on Windows PowerShell 5.1
    if ($IsLinux) { return "linux-$archKey" }
    if ($IsMacOS) { return "osx-$archKey" }
    throw "Could not determine current platform."
}

# Proxy-aware download, mirroring download.build.artifacts.and.package.ps1.
function Invoke-Download($url, $outFile) {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $params = @{ Uri = $url; OutFile = $outFile; UseBasicParsing = $true }
    $proxy = [System.Net.WebRequest]::GetSystemWebProxy()
    if ($proxy) {
        $proxy.Credentials = [System.Net.CredentialCache]::DefaultCredentials
        $proxyUri = $proxy.GetProxy([uri]$url)
        # GetProxy returns an empty value (or the url itself) for a direct connection; only route
        # through a proxy when it names a genuinely different endpoint.
        if ($proxyUri -and "$proxyUri" -ne "$url") {
            $params.Proxy = "$proxyUri"
            $params.ProxyUseDefaultCredentials = $true
        }
    }
    Write-Host "-> Downloading $url"
    Invoke-WebRequest @params
}

if (-not $Platform) { $Platform = Get-CurrentPlatform }
Write-Host "==> Fetching native deps for platform '$Platform'"

$lock = Get-Content $lockPath -Raw | ConvertFrom-Json
if (-not $lock.platforms.PSObject.Properties.Name.Contains($Platform)) {
    throw "Platform '$Platform' is not present in deps.lock.json. Available: $($lock.platforms.PSObject.Properties.Name -join ', ')."
}
$entry = $lock.platforms.$Platform

$expectedSha = "$($entry.sha256)".Trim().ToLower()
if (-not $expectedSha) {
    throw "deps.lock.json has no sha256 for '$Platform'. Run the build-deps workflow to publish the archive, " +
          "then populate the sha256 (and url/tag) in deps.lock.json. Refusing to fetch without hash verification."
}

$targetDir = Join-Path $depsDirectory $Platform
if ((Test-Path $targetDir) -and -not $Force) {
    Write-Host "==> Deps already present at '$targetDir' (use -Force to refresh). Skipping."
    return $targetDir
}

New-Item -ItemType Directory -Path $cacheDirectory -Force | Out-Null
$archive = Join-Path $cacheDirectory $entry.filename
Invoke-Download $entry.url $archive

$actualSha = (Get-FileHash -Algorithm SHA256 -Path $archive).Hash.ToLower()
if ($actualSha -ne $expectedSha) {
    Remove-Item $archive -Force
    throw "SHA256 mismatch for '$($entry.filename)'.`n  expected: $expectedSha`n  actual:   $actualSha`nAborting."
}
Write-Host "==> SHA256 verified: $actualSha"

if (Test-Path $targetDir) { Remove-Item $targetDir -Recurse -Force }
New-Item -ItemType Directory -Path $targetDir | Out-Null
if ($entry.filename -match '\.(tar\.gz|tgz)$') {
    # posix archives are tar.gz so shared-lib symlinks + exec bits survive; tar is present on all
    # posix hosts and on modern Windows.
    & tar -xzf $archive -C $targetDir
    if ($LASTEXITCODE -ne 0) { throw "tar extraction failed ($LASTEXITCODE) for '$archive'." }
} else {
    Expand-Archive -Path $archive -DestinationPath $targetDir -Force
}
Write-Host "==> Extracted to '$targetDir'"

return $targetDir
