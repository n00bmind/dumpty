:: use this file to run your own startup commands
:: use in front of the command to prevent printing the command

:: uncomment this to have the ssh agent load when cmder starts
:: call "%GIT_INSTALL_ROOT%/cmd/start-ssh-agent.cmd" /k exit

:: uncomment the next two lines to use pageant as the ssh authentication agent
:: SET SSH_AUTH_SOCK=/tmp/.ssh-pageant-auth-sock
:: call "%GIT_INSTALL_ROOT%/cmd/start-ssh-pageant.cmd"

:: you can add your plugins to the cmder path like so
:: set "PATH=%CMDER_ROOT%\vendor\whatever;%PATH%"

:: arguments in this batch are passed from init.bat, you can quickly parse them like so:
:: more useage can be seen by typing "cexec /?"

:: %ccall% "/customOption" "command/program"

@echo off

set CACHED_ENV=W:\env\cached_vcvars.env
set PRE_ENV="%TEMP%\pre.env"
set POST_ENV="%TEMP%\post.env"

:: Look for a cached env
if exist %CACHED_ENV% (
    echo Applying previously cached env in '%CACHED_ENV%'..
    echo (just delete that file if you want to recreate it, ***for example if the system's %%PATH%% must be updated***^)

    FOR /F "tokens=*" %%i in (%CACHED_ENV%) do set %%i
    goto :END
)

echo Couldn't find cached env. Trying to locate vcvars batch file..
echo.

if not defined VCDIR (
    set VCDIR=""
)

if not exist %VCDIR% (
    set VCDIR="C:\Program Files (x86)\Microsoft Visual Studio\2019\Community"
)

if not exist %VCDIR% (
    set VCDIR="C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools"
)

if not exist %VCDIR% (
    set VCDIR="C:\Program Files (x86)\Microsoft Visual Studio\2017\Community"
)

if not exist %VCDIR% (
    set VCDIR="C:\Program Files (x86)\Microsoft Visual Studio\2017\BuildTools"
)

if not exist %VCDIR% (
    if exist "%programfiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe" (
        for /F "tokens=* USEBACKQ" %%F in (`"%programfiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe" -latest -property installationPath`) do set VCDIR="%%F"
    )
)

if not exist %VCDIR% (
	echo Couldn't find Visual Studio folder!
	goto :END
)

:: Store env before running vars command
set | sort /rec 65535 > %PRE_ENV%
REM sort %PRE_ENV%

call %VCDIR%\VC\Auxiliary\Build\vcvars64.bat

:: Store new env and compute diff using 'comm' (included in git-for-windows)
set | sort /rec 65535 > %POST_ENV%
REM sort %POST_ENV%

comm -13 %PRE_ENV% %POST_ENV% > %CACHED_ENV%

goto :END


:END

