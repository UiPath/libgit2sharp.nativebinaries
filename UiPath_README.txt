Prerequisites for building LibGit:
- Build Tools for Visual Studio 2019, C++ Desktop package
-	Perl – Any version of ActivePerl or Strawberry Perl. For my installation I used ActivePerl 5.28, x-64). 
If Perl is installed in a custom folder, be sure that the path to Perl folder is set in PATH environment variable. 
If not, manually add the path to Perl folder to PATH environment variable.
-	CMake  - For my installation I used CMake 3.16.4, x64. 
If CMake is installed in a custom folder, be sure that the path to CMake folder is set in PATH environment variable. 
If not, manually add the path to CMake folder to PATH environment variable.
-	NASM – For my installation I used NASM 2.14.02, x64. 
If NASM is installed in a custom folder, be sure that the path to NASM folder is set in PATH environment variable. 
If not, manually add the path to NASM folder to PATH environment variable.
-	Visual Studio (Developer Command Prompt will be necessary); Any modifications done to PATH environment variable will require a restart of Developer Command Prompt.
-	Verify that all submodules were updated. Use TortoiseGit/Submodule Update for libgit2, libssh2, openssl with “Recursive” and “Force” checked
-	Open Developer Command Prompt and run uipath-build.ps1 with PowerShell
-	Open libgit2sharp.nativebinaries\libgit2\build\x86\libgit2.sln with Visual Studio and set the output path for the containing projects to Studio\Output\bin\Debug\net461\lib\win32\x86

Tips & Tricks: 
- Building OpenSSL usually takes a lot of time, and on each build the previous output is cleaned so there is always a fresh install. 
If you manage to build OpenSSL but have some other errors later in the build, before retrying the `uipath-build.ps1`, consider commenting out the line that starts the OpenSSL build to skip rebuilding install
(in build.libgit2.ps1, cmd.exe /c build.openssl.cmd $configuration $platform, line 100)

Versioning: 
The version of the package is determined by the `libgit2` version, so for example if we are using libgit2 v1.7.1, this package will be libgit2 v1.7.1-v1, where v1 is our own version number. 

Using WinGet to install dependencies:

winget install -e --id Microsoft.VisualStudio.2019.BuildTools --override "--passive --wait --add Microsoft.VisualStudio.Workload.VCTools;includeRecommended"
winget install --id=StrawberryPerl.StrawberryPerl  -e
winget install --id=Kitware.CMake  -e
winget install --id=NASM.NASM  -e

You can check that the c++ build tools were installed in the Visual Studio Installer, check Visual Studio Build Tools 2019 -> modify -> c++ desktop development should be checked