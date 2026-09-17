<#
.SYNOPSIS
    Builds a version of libgit2 and copies it to the nuget packaging directory.
.PARAMETER vs
    Version of Visual Studio project files to generate. Cmake supports "10" (default), "11" and "12".
.PARAMETER test
    If set, run the libgit2 tests on the desired version.
.PARAMETER debug
    If set, build the "Debug" configuration of libgit2, rather than "RelWithDebInfo" (default).
#>

Param(
    [string]$vs = '16 2019',
    [string]$libgit2Name = '',
    [string]$Platform = 'win-x64',
    [switch]$test,
    [switch]$debug
)

Set-StrictMode -Version Latest

$projectDirectory = Split-Path $MyInvocation.MyCommand.Path
$libgit2Directory = Join-Path $projectDirectory "libgit2"

# $Platform is a RID (win-x64 / win-arm64); derive the cmake target arch and packaging locations.
$arch = ($Platform -split '-')[-1]                                  # x64 | arm64
$cmakeArch = if ($arch -eq 'arm64') { 'ARM64' } else { 'x64' }     # cmake -A value
# OpenSSL's runtime DLL carries an arch suffix: libcrypto-3-x64.dll / libcrypto-3-arm64.dll.
$opensslDllSuffix = "-$arch"
$nativeDirectory = Join-Path $projectDirectory "nuget.package\runtimes\$Platform\native"
$hashFile = Join-Path $projectDirectory "nuget.package\libgit2\libgit2_hash.txt"
# Prebuilt OpenSSL + libssh2, fetched & SHA256-verified by fetch.deps.ps1 (we no longer build them here).
# Use forward slashes: these paths are passed to cmake, which treats backslashes as escape sequences.
$depsDirectory = (Join-Path $projectDirectory "deps\$Platform").Replace('\', '/')

if (![string]::IsNullOrEmpty($libgit2Name)) {
    $binaryFilename = $libgit2Name
} else {
    $binaryFilename = "libgit2"
}

$build_clar = 'OFF'
if ($test.IsPresent) { $build_clar = 'ON' }

$configuration = "RelWithDebInfo"
if ($debug.IsPresent) { $configuration = "Debug" }

function Run-Command([scriptblock]$Command, [switch]$Fatal, [switch]$Quiet) {
    $output = ""
    if ($Quiet) {
        $output = & $Command 2>&1
    } else {
        & $Command
    }

    if (!$Fatal) {
        return
    }

    $exitCode = 0
    if ($LastExitCode -ne 0) {
        $exitCode = $LastExitCode
    } elseif (!$?) {
        $exitCode = 1
    } else {
        return
    }

    $error = "``$Command`` failed"
    if ($output) {
        Write-Host -ForegroundColor yellow $output
        $error += ". See output above."
    }
    Throw $error
}

function Find-CMake {
    # Look for cmake.exe in $Env:PATH.
    $cmake = @(Get-Command cmake.exe)[0] 2>$null
    if ($cmake) {
        $cmake = $cmake.Definition
    } else {
        # Look for the highest-versioned cmake.exe in its default location.
        $cmake = @(Resolve-Path (Join-Path ${Env:ProgramFiles(x86)} "CMake *\bin\cmake.exe"))
        if ($cmake) {
            $cmake = $cmake[-1].Path
        }
    }
    if (!$cmake) {
        throw "Error: Can't find cmake.exe"
    }
    $cmake
}

function Ensure-Property($expected, $propertyValue, $propertyName, $path) {
    if ($propertyValue -eq $expected) {
        return
    }

    throw "Error: Invalid '$propertyName' property in generated '$path' (Expected: $expected - Actual: $propertyValue)"
}

function Build-LibGit($generator, $platform, $nugetDir, $useSchannel, $useSshExe) {
	$depsBinDir = Join-Path $depsDirectory "bin"
	$sshMethod = "libssh2"
	if ($useSshExe) {
		$sshMethod = "exec"
	}

	$buildDir = [IO.Path]::Combine( $libgit2Directory, "build", $platform)
	Run-Command -Quiet { & remove-item $buildDir -recurse -force }
	[IO.Directory]::CreateDirectory($buildDir)
    cd $buildDir
    $variantFilename = $binaryFileName
    if ($useSchannel) {
        $variantFilename = -join ($variantFilename, "_schannel")
    }
	if ($useSshExe) {
        $variantFilename = -join ($variantFilename, "_ssh")
    }
	Write-Output "CONFIGURE LIBGIT... Schannel: $useSchannel"
    $httpsBackend = "WinHTTP"
    if ($useSchannel) {
        $httpsBackend = "Schannel"
    }
    $httpsArgs = @("-D", "USE_HTTPS=$httpsBackend")
	Run-Command -Fatal { & $cmake -G $generator -A $platform -D ENABLE_TRACE=ON -D "BUILD_CLAR=$build_clar" -D "BUILD_TESTS=OFF" -D "BUILD_CLI=OFF" @httpsArgs -D "LIBGIT2_FILENAME=$variantFilename" -D "USE_SSH=$sshMethod" -D "USE_BUNDLED_ZLIB=ON" -D "LIBSSH2_INCLUDE_DIRS=$depsDirectory/include" -D "LIBSSH2_LIBRARIES=$depsDirectory/lib/libssh2.lib" -D "LIBSSH2_FOUND=TRUE" -D "OPENSSL_ROOT_DIR=$depsDirectory" $libgit2Directory }
	Write-Output "BUILD LIBGIT..."
	Run-Command -Quiet -Fatal { & $cmake --build . --config $configuration }
    if ($test.IsPresent) { Run-Command -Quiet -Fatal { & $ctest -V . } }
    cd $configuration

<#
    Assert-Consistent-Naming "$binaryFilename.dll" "*.dll"
#>
    Assert-HttpsBackend (Join-Path (Get-Location) "$variantFilename.dll") $useSchannel

    Run-Command -Quiet { & rm *.exp }
    Run-Command -Quiet { & rm $nugetDir\* }
    Run-Command -Quiet { & mkdir -fo $nugetDir }
    Run-Command -Quiet -Fatal { & copy -fo * $nugetDir -Exclude *.lib }
	
	Copy-Item "$depsBinDir/libssh2.dll" -Destination $nugetDir -Force
	Copy-Item "$depsBinDir/libcrypto-3$opensslDllSuffix.dll" -Destination $nugetDir -Force
}

function Get-PeImportedDlls([string]$Path) {
    $bytes = [IO.File]::ReadAllBytes($Path)

    $peOffset = [BitConverter]::ToInt32($bytes, 0x3C)
    if ([BitConverter]::ToUInt32($bytes, $peOffset) -ne 0x00004550) {
        throw "'$Path' is not a PE image"
    }

    $fileHeader = $peOffset + 4
    $numSections = [BitConverter]::ToUInt16($bytes, $fileHeader + 2)
    $optHeaderSize = [BitConverter]::ToUInt16($bytes, $fileHeader + 16)
    $optHeader = $fileHeader + 20

    $magic = [BitConverter]::ToUInt16($bytes, $optHeader)
    $dataDirectories = if ($magic -eq 0x20B) { $optHeader + 112 } else { $optHeader + 96 }
    $importRva = [BitConverter]::ToUInt32($bytes, $dataDirectories + 8)
    if ($importRva -eq 0) {
        return @()
    }

    $sectionTable = $optHeader + $optHeaderSize
    $sections = @(for ($i = 0; $i -lt $numSections; $i++) {
        $s = $sectionTable + $i * 40
        [pscustomobject]@{
            VirtualSize    = [BitConverter]::ToUInt32($bytes, $s + 8)
            VirtualAddress = [BitConverter]::ToUInt32($bytes, $s + 12)
            RawSize        = [BitConverter]::ToUInt32($bytes, $s + 16)
            RawPointer     = [BitConverter]::ToUInt32($bytes, $s + 20)
        }
    })

    $rvaToOffset = {
        param([uint32]$rva)
        foreach ($section in $sections) {
            $size = [Math]::Max($section.VirtualSize, $section.RawSize)
            if ($rva -ge $section.VirtualAddress -and $rva -lt ($section.VirtualAddress + $size)) {
                return [int]($rva - $section.VirtualAddress + $section.RawPointer)
            }
        }
        throw "RVA 0x$($rva.ToString('X')) is not mapped by any section of '$Path'"
    }

    $readCString = {
        param([int]$offset)
        $end = [Array]::IndexOf($bytes, [byte]0, $offset)
        [Text.Encoding]::ASCII.GetString($bytes, $offset, $end - $offset)
    }

    $names = @()
    $descriptor = & $rvaToOffset $importRva
    while ($true) {
        $nameRva = [BitConverter]::ToUInt32($bytes, $descriptor + 12)
        if ($nameRva -eq 0) { break }
        $names += & $readCString (& $rvaToOffset $nameRva)
        $descriptor += 20
    }
    $names
}

function Assert-HttpsBackend([string]$dllPath, [bool]$useSchannel) {
    $imports = @(Get-PeImportedDlls $dllPath)
    $importsWinHttp = [bool]($imports | Where-Object { $_ -ieq "winhttp.dll" })
    $expected = if ($useSchannel) { "Schannel" } else { "WinHTTP" }
    $actual = if ($importsWinHttp) { "WinHTTP" } else { "Schannel" }
    if ($actual -ne $expected) {
        throw "Error: '$dllPath' was built with the $actual HTTPS backend, expected $expected. Imports: $($imports -join ', ')"
    }
    Write-Output "VERIFIED $(Split-Path -Leaf $dllPath) uses the $expected HTTPS backend"
}

function Assert-Consistent-Naming($expected, $path) {
    $dll = get-item $path

    Ensure-Property $expected $dll.Name "Name" $dll.Fullname
    Ensure-Property $expected $dll.VersionInfo.InternalName "VersionInfo.InternalName" $dll.Fullname
    Ensure-Property $expected $dll.VersionInfo.OriginalFilename "VersionInfo.OriginalFilename" $dll.Fullname
}

try {
    Push-Location $libgit2Directory

    $cmake = Find-CMake
    $ctest = Join-Path (Split-Path -Parent $cmake) "ctest.exe"

    # Fetch & hash-verify prebuilt OpenSSL + libssh2 (replaces compiling them from the submodules here).
    & (Join-Path $projectDirectory "fetch.deps.ps1") -Platform $Platform

	Build-LibGit "Visual Studio $vs" $cmakeArch $nativeDirectory $false $false
	Build-LibGit "Visual Studio $vs" $cmakeArch $nativeDirectory $true $false
	Build-LibGit "Visual Studio $vs" $cmakeArch $nativeDirectory $false $true
	Build-LibGit "Visual Studio $vs" $cmakeArch $nativeDirectory $true $true

    Write-Output "Done!"
}
finally {
    Pop-Location
}
