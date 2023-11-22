Param(
    [Parameter(Mandatory=$true)]
    [string]$version,
    [switch]$pre
)

$buildDate = (Get-Date).ToUniversalTime().ToString("yyyyMMddHHmmss")
$versionSuffix = ""
if ($pre.IsPresent) { $versionSuffix = "-pre$BuildDate" }

Get-ChildItem -Path "nuget.package\runtimes" -Recurse -Filter *.pdb | ForEach-Object {
    Remove-Item $_.FullName -Force
}
.\nuget.exe Pack nuget.package\NativeBinaries.nuspec -Version $version$versionSuffix -NoPackageAnalysis
