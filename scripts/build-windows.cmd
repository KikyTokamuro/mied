@echo off
rem ==========================================================================
rem  Mied - build a standalone Windows binary with tclexecomp.
rem
rem  The editor, its icon, its language files, and the license are copied into
rem  build\wrap\, wrapped with tclexecomp -forcewrap, and the finished binary
rem  is moved to dist\.
rem
rem  See the "Building a standalone binary" section of the README.
rem ==========================================================================

setlocal
set "NAME=mied"
set "COMPILE=1"
set "CLEAN=0"
set "DEPTH=0"
set "TOOL="
if defined TCLEXECOMP set "TOOL=%TCLEXECOMP%"

pushd "%~dp0.." || (
    echo build-windows: cannot enter the repository root
    exit /b 1
)
set /a DEPTH=DEPTH+1 >nul
set "ROOT=%CD%"

if not exist "%ROOT%\mied.tcl" (
    echo build-windows: mied.tcl not found in "%ROOT%"
    goto fail
)
if not exist "%ROOT%\img\icon.png" (
    echo build-windows: img\icon.png not found in "%ROOT%"
    goto fail
)
if not exist "%ROOT%\langs" (
    echo build-windows: langs not found in "%ROOT%"
    goto fail
)

rem --- Options --------------------------------------------------------------

:parse
if "%~1"=="" goto parsed
if /i "%~1"=="--help"       goto usage
if /i "%~1"=="-h"           goto usage
if /i "%~1"=="--no-compile" goto opt_no_compile
if /i "%~1"=="--clean"      goto opt_clean
if /i "%~1"=="--tool"       goto opt_tool
if /i "%~1"=="--name"       goto opt_name
echo build-windows: unknown option "%~1" (try --help)
goto fail

:opt_no_compile
set "COMPILE=0"
shift
goto parse

:opt_clean
set "CLEAN=1"
shift
goto parse

:opt_tool
shift
if "%~1"=="" (
    echo build-windows: --tool needs a path
    goto fail
)
set "TOOL=%~1"
shift
goto parse

:opt_name
shift
if "%~1"=="" (
    echo build-windows: --name needs a value
    goto fail
)
set "NAME=%~1"
shift
goto parse

:parsed

rem --- Locate tclexecomp ----------------------------------------------------

rem The stock Windows binary is both the driver that wraps and the stub that
rem gets copied, so it is what -w points at below.
if not defined TOOL set "TOOL=tclexecomp64.exe"
if exist "%TOOL%" goto tool_ok
for /f "delims=" %%I in ('where "%TOOL%" 2^>nul') do (
    set "TOOL=%%I"
    goto tool_ok
)
echo build-windows: tclexecomp driver not found: "%TOOL%"
echo                download it from https://tclexecomp.sourceforge.net
echo                or pass --tool ^<path to tclexecomp64.exe^>
goto fail

:tool_ok
rem Absolute path, since tclexecomp runs with build\ as the working directory.
for %%I in ("%TOOL%") do set "TOOL=%%~fI"
set "STUB=%TOOL%"

rem --- Collect what goes into the binary ------------------------------------

if "%CLEAN%"=="1" (
    if exist "%ROOT%\build" rmdir /s /q "%ROOT%\build"
    if exist "%ROOT%\dist"  rmdir /s /q "%ROOT%\dist"
)
rem Always rebuild the wrap directory: tclexecomp copies whatever is in it.
if exist "%ROOT%\build" rmdir /s /q "%ROOT%\build"
mkdir "%ROOT%\build\wrap\img"   || goto copyfail
mkdir "%ROOT%\build\wrap\langs" || goto copyfail
if not exist "%ROOT%\dist" mkdir "%ROOT%\dist" || goto copyfail

copy /y "%ROOT%\mied.tcl"     "%ROOT%\build\wrap\mied.tcl"     >nul || goto copyfail
copy /y "%ROOT%\img\icon.png" "%ROOT%\build\wrap\img\icon.png" >nul || goto copyfail
copy /y "%ROOT%\LICENSE"      "%ROOT%\build\wrap\LICENSE"      >nul || goto copyfail
copy /y "%ROOT%\langs\*.lang" "%ROOT%\build\wrap\langs\"       >nul || goto copyfail

rem --- Bytecode -------------------------------------------------------------

rem Bytecode keeps the source out of the binary, at the cost of needing tbcload
rem in the stub. tclexecomp writes mied.tbc next to the script; the howto then
rem renames it to mied.tcl, since the wrapped file is plain "source"d at startup.
rem The driver is started with "call" so that a driver given as a .cmd or .bat
rem hands control back to this script instead of replacing it.
if "%COMPILE%"=="1" (
    echo Compiling mied.tcl to bytecode...
    pushd "%ROOT%\build"
    set /a DEPTH=DEPTH+1 >nul
    call "%TOOL%" -compile wrap/mied.tcl
    if not exist "%ROOT%\build\wrap\mied.tbc" (
        echo build-windows: bytecode was not produced, rerun with --no-compile
        goto fail
    )
    move /y "%ROOT%\build\wrap\mied.tbc" "%ROOT%\build\wrap\mied.tcl" >nul || goto copyfail
    popd
    set /a DEPTH=DEPTH-1 >nul
)

rem --- Wrap ----------------------------------------------------------------

rem Paths stay relative to build\ and use forward slashes: tclexecomp strips
rem the leading "wrap/" from the start file, which is what puts the output
rem binary in build\ instead of build\wrap\.
echo Wrapping for Windows...
set "LANGFILES="
for %%F in ("%ROOT%\build\wrap\langs\*.lang") do call set "LANGFILES=%%LANGFILES%% wrap/langs/%%~nxF"
pushd "%ROOT%\build"
set /a DEPTH=DEPTH+1 >nul
call "%TOOL%" wrap/mied.tcl wrap/img/icon.png wrap/LICENSE%LANGFILES% -forcewrap -w "%STUB%" -appname "%NAME%" -o "%NAME%"
if not exist "%ROOT%\build\%NAME%.exe" (
    echo build-windows: tclexecomp did not produce build\%NAME%.exe
    goto fail
)
rem A failed wrap still leaves the plain stub behind, so an exe that is no
rem bigger than the stub means the payload never made it in.
for %%I in ("%STUB%") do set "STUBSIZE=%%~zI"
for %%I in ("%ROOT%\build\%NAME%.exe") do set "OUTSIZE=%%~zI"
if %OUTSIZE% LEQ %STUBSIZE% (
    echo build-windows: wrap failed, %NAME%.exe is not bigger than the stub, so the
    echo                file tclexecomp left behind holds no payload. See the error above.
    goto fail
)
move /y "%ROOT%\build\%NAME%.exe" "%ROOT%\dist\%NAME%.exe" >nul || goto copyfail
popd
set /a DEPTH=DEPTH-1 >nul

for %%I in ("%ROOT%\dist\%NAME%.exe") do set "SIZE=%%~zI"
echo Built dist\%NAME%.exe (%SIZE% bytes)
goto done

:usage
echo Build a standalone Mied binary for Windows with tclexecomp.
echo.
echo Usage: scripts\build-windows.cmd [options]
echo.
echo   --no-compile    ship readable Tcl instead of bytecode
echo   --clean         remove build\ and dist\ before building
echo   --tool ^<path^>   tclexecomp64.exe to run (default: found on PATH)
echo   --name ^<name^>   name of the output binary (default: mied)
echo   -h, --help      show this help
echo.
echo TCLEXECOMP sets the --tool default.
goto done

:copyfail
echo build-windows: could not write into "%ROOT%\build"
goto fail

:done
call :restore
endlocal
exit /b 0

:fail
call :restore
endlocal
exit /b 1

:restore
if not defined DEPTH goto :eof
if "%DEPTH%"=="0" goto :eof
popd
set /a DEPTH=DEPTH-1 >nul
goto restore
