function Test-Command($cmdname)
{
    return [bool](Get-Command -Name $cmdname -ErrorAction SilentlyContinue)
}

if (!(Test-Command -cmdname 'gitversion'))
{
	Import-Module ./Get-Version.ps1
	Get-Version 
}

$verinfo = gitversion  /output json /nofetch | out-string
$jsonver = try { ConvertFrom-Json $verinfo } catch {}
$version = $jsonver.NuGetVersion	

$version

.\build.libgit2.ps1
.\buildpackage.ps1 "$version-ssh"

