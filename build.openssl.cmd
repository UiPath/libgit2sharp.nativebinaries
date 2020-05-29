where /q perl
IF ERRORLEVEL 1 (
    ECHO Perl cannot be found. Please ensure it is installed and placed in your PATH.
	PAUSE
    EXIT /B
) 

set configuration=%1
set platform_arg=%2
set VS_WIN32="%VSINSTALLDIR%\VC\Auxiliary\Build\vcvars32.bat"
set VS_WIN64="%VSINSTALLDIR%\VC\Auxiliary\Build\vcvars64.bat"

if %platform_arg% EQU x64 (
	echo "register 64 bit env"
	CALL %VS_WIN64%
) else (
	echo "register 32 bit env"
	CALL %VS_WIN32%
)

powershell ./build.openssl.ps1 %configuration% %platform_arg%
