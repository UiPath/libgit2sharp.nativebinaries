<#
.SYNOPSIS
    Builds openssl. Requires: Perl (in path), nmake (14.16.27023).
    'x86' (default), 'x64'.
.PARAMETER configuration
	'RelWithDebInfo' (default), 'Debug.
#>
Param(
    [string]$configuration = 'RelWithDebInfo',
	[string]$platform = 'x86'
)

$projectDirectory = Split-Path $MyInvocation.MyCommand.Path
$libopensslDirectory = ([System.Uri](Join-Path $projectDirectory "openssl")).AbsolutePath
$buildPath = [IO.Path]::Combine( $libopensslDirectory, "build", $configuration, $platform)
[IO.Directory]::CreateDirectory($buildPath)

$vcflags = "VC-WIN32"
if ($configuration -eq "RelWithDebInfo")
{
	if ($platform -eq "x64")
	{
		$vcflags = "VC-WIN64A"
	}
}
elseif ($configuration -eq "Debug")
{
	if ($platform -eq "x86")
	{
		$vcflags = "debug-VC-WIN32"
	}
	else
	{
		$vcflags = "debug-VC-WIN64A"
	}
}

pushd
cd $libopensslDirectory
perl Configure $vcflags --prefix=$buildPath
nmake clean
nmake
nmake install
popd