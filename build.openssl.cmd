where /q perl
IF ERRORLEVEL 1 (
    ECHO Perl cannot be found. Please ensure it is installed and placed in your PATH.
	PAUSE
    EXIT /B
) 

set configuration=%1
set platform=%2
set VS2015="c:\Program Files (x86)\Microsoft Visual Studio\2017\Professional\VC\Auxiliary\Build\vcvars32.bat"
set VS2015_AMD64="c:\Program Files (x86)\Microsoft Visual Studio\2017\Professional\VC\Auxiliary\Build\vcvars64.bat"

if %platform% EQU x64 (
	echo "register 64 bit env"
	CALL %VS2015_AMD64%
) else (
	echo "register 32 bit env"
	CALL %VS2015%
)

powershell ./build.openssl.ps1 %1 %2
