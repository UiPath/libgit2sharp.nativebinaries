function Get-Version
{
   	    $packageVersion = "4.0.0"
	    Write-Host "Resolving GitVersion.exe..."
		Register-PackageSource -Name "officialNugetV2" -Location "http://www.nuget.org/api/v2/" -ProviderName "NuGet" -ErrorAction SilentlyContinue
		Install-Package GitVersion.CommandLine -RequiredVersion $packageVersion -Source "officialNugetV2" -Force -Scope CurrentUser
		UnRegister-PackageSource -Name "officialNugetV2"
		$gitVersionDir = (Get-Item (Get-Package GitVersion.CommandLine).Source).DirectoryName + "\tools" 
		$Env:Path += ";" + $gitVersionDir
}