@echo off

set POWERSHELL_SCRIPT_PATH=
set PS_ARGS=
set PATHS_ARRAY_ELEMENTS=

:collect_args

if not defined POWERSHELL_SCRIPT_PATH (
    set "POWERSHELL_SCRIPT_PATH=%~1" & goto :escape_1
    :escape_1
    set "POWERSHELL_SCRIPT_PATH=%POWERSHELL_SCRIPT_PATH:'=''%" & goto :escape_2
    :escape_2
    set "POWERSHELL_SCRIPT_PATH=%POWERSHELL_SCRIPT_PATH:[=`[%" & goto :escape_3
    :escape_3
    set "POWERSHELL_SCRIPT_PATH=%POWERSHELL_SCRIPT_PATH:]=`]%"
    shift
    goto :collect_args
)

if /i "%~1"=="-Path" (
    set "PATHS_ARRAY_ELEMENTS=%~2"
    shift
    goto :args_done
)

if not defined PS_ARGS (
    if "%~1"=="" goto :no_paths
    set "PS_ARGS=%~1"
    shift
    goto :collect_args
) else (
    if "%~1"=="" goto :no_paths
    set "PS_ARGS=%PS_ARGS% %~1"
    shift
    goto :collect_args
)

:no_paths
if not defined PATHS_ARRAY_ELEMENTS (
    echo ERROR: No input file or directory paths provided.
    echo Usage: %~nx0 <PowerShellScriptPath> [<PSArg1> [<PSArg2> ...]] -Path "<Path1> [<Path2> ...]"
    exit /b 1
)

:args_done
echo "Executing PowerShell command: '%POWERSHELL_SCRIPT_PATH%' %PS_ARGS% -Path @(%PATHS_ARRAY_ELEMENTS%)"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& '%POWERSHELL_SCRIPT_PATH%' %PS_ARGS% -Path @(%PATHS_ARRAY_ELEMENTS%)"
