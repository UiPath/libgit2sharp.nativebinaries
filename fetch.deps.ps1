<#
.SYNOPSIS
    Downloads the prebuilt native-deps archives (OpenSSL + libssh2) for the current platform,
    verifies each against its SHA256 in deps.lock.json, and extracts them (merged) into
    deps/<platform>/.

    The libgit2 build calls this instead of compiling OpenSSL/libssh2 from source. Verification is
    mandatory: if a component's lockfile SHA256 is empty or does not match the download, this fails
    hard.
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
        $proxyUri = $proxy.GetProxy($url)
        if ("$proxyUri" -ne "$url") {
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
$targetDir = Join-Path $depsDirectory $Platform

if ((Test-Path $targetDir) -and -not $Force) {
    Write-Host "==> Deps already present at '$targetDir' (use -Force to refresh). Skipping."
    return $targetDir
}

New-Item -ItemType Directory -Path $cacheDirectory -Force | Out-Null
if (Test-Path $targetDir) { Remove-Item $targetDir -Recurse -Force }
New-Item -ItemType Directory -Path $targetDir | Out-Null

foreach ($componentName in $lock.components.PSObject.Properties.Name) {
    $component = $lock.components.$componentName
    if (-not $component.platforms.PSObject.Properties.Name.Contains($Platform)) {
        throw "Component '$componentName' has no entry for platform '$Platform' in deps.lock.json."
    }
    $entry = $component.platforms.$Platform

    $expectedSha = "$($entry.sha256)".Trim().ToLower()
    if (-not $expectedSha) {
        throw "deps.lock.json has no sha256 for '$componentName'/'$Platform'. Run the build-$componentName " +
              "workflow to publish the archive, then populate the sha256 (and url/tag). Refusing to fetch without hash verification."
    }

    $archive = Join-Path $cacheDirectory $entry.filename
    Invoke-Download $entry.url $archive

    $actualSha = (Get-FileHash -Algorithm SHA256 -Path $archive).Hash.ToLower()
    if ($actualSha -ne $expectedSha) {
        Remove-Item $archive -Force
        throw "SHA256 mismatch for '$($entry.filename)'.`n  expected: $expectedSha`n  actual:   $actualSha`nAborting."
    }
    Write-Host "==> $componentName SHA256 verified: $actualSha"

    # Components contribute non-overlapping files; extract all into the merged deps/<platform>/ tree.
    Expand-Archive -Path $archive -DestinationPath $targetDir -Force
}

Write-Host "==> Extracted deps to '$targetDir'"
return $targetDir
