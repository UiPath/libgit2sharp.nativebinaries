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
    [switch]$test,
    [switch]$debug
)

Set-StrictMode -Version Latest

$projectDirectory = Split-Path $MyInvocation.MyCommand.Path
$libgit2Directory = Join-Path $projectDirectory "libgit2"
$x86Directory = Join-Path $projectDirectory "nuget.package\runtimes\win-x86\native"
$x64Directory = Join-Path $projectDirectory "nuget.package\runtimes\win-x64\native"
$hashFile = Join-Path $projectDirectory "nuget.package\libgit2\libgit2_hash.txt"
# Prebuilt OpenSSL + libssh2, fetched & SHA256-verified by fetch.deps.ps1 (we no longer build them here).
# Use forward slashes: these paths are passed to cmake, which treats backslashes as escape sequences.
$depsDirectory = (Join-Path $projectDirectory "deps\win-x64").Replace('\', '/')

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
    $httpsConfig = "WinHTTP"
    if ($useSchannel) {
        $httpsConfig = "-D `"USE_HTTPS=Schannel`""
    }
	Run-Command -Fatal { & $cmake -G $generator -A $platform -D ENABLE_TRACE=ON -D "BUILD_CLAR=$build_clar" -D "BUILD_TESTS=OFF" -D "BUILD_CLI=OFF" $httpsConfig -D "LIBGIT2_FILENAME=$variantFilename" -D "USE_SSH=$sshMethod" -D "USE_BUNDLED_ZLIB=ON" -D "LIBSSH2_INCLUDE_DIRS=$depsDirectory/include" -D "LIBSSH2_LIBRARIES=$depsDirectory/lib/libssh2.lib" -D "LIBSSH2_FOUND=TRUE" -D "OPENSSL_ROOT_DIR=$depsDirectory" $libgit2Directory }
	Write-Output "BUILD LIBGIT..."
	Run-Command -Quiet -Fatal { & $cmake --build . --config $configuration }
    if ($test.IsPresent) { Run-Command -Quiet -Fatal { & $ctest -V . } }
    cd $configuration

<#
    Assert-Consistent-Naming "$binaryFilename.dll" "*.dll"
#>

    Run-Command -Quiet { & rm *.exp }
    Run-Command -Quiet { & rm $nugetDir\* }
    Run-Command -Quiet { & mkdir -fo $nugetDir }
    Run-Command -Quiet -Fatal { & copy -fo * $nugetDir -Exclude *.lib }
	
	$opensslPlatformPostfix = ""
	if ($platform -eq "x64") {
		$opensslPlatformPostfix = "-x64"
	}
	Copy-Item "$depsBinDir/libssh2.dll" -Destination $nugetDir -Force
	Copy-Item "$depsBinDir/libcrypto-3$opensslPlatformPostfix.dll" -Destination $nugetDir -Force
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
    & (Join-Path $projectDirectory "fetch.deps.ps1") -Platform "win-x64"

	Build-LibGit "Visual Studio $vs" "x64" $x64Directory $false $false
	Build-LibGit "Visual Studio $vs" "x64" $x64Directory $true $false
	Build-LibGit "Visual Studio $vs" "x64" $x64Directory $false $true
	Build-LibGit "Visual Studio $vs" "x64" $x64Directory $true $true

    Write-Output "Done!"
}
finally {
    Pop-Location
}
