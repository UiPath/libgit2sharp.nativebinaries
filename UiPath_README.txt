Prerequisites for building LibGit:
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
