@echo off

REM --- Wrapper script to call remux.ps1 ---
REM Parses original batch arguments and maps them to PowerShell parameters.

set "SCRIPT_DIR=%~dp0"
set "POWERSHELL_SCRIPT_PATH=%SCRIPT_DIR%remux.ps1"

REM Check if the PowerShell script exists
if not exist "%POWERSHELL_SCRIPT_PATH%" (
    echo ERROR: PowerShell script not found at "%POWERSHELL_SCRIPT_PATH%"
    exit /b 1
)

set "PS_ARGS="
set "PATHS_ARRAY_ELEMENTS="

:arg_loop
if "%~1"=="" goto :args_done

REM --- Handle Flags (Switches) first ---
if /i "%~1"=="-r"                ( set "PS_ARGS=%PS_ARGS% -Recurse" & shift & goto :arg_loop )
if /i "%~1"=="-f"                ( set "PS_ARGS=%PS_ARGS% -Force" & shift & goto :arg_loop )
if /i "%~1"=="-delete"           ( set "PS_ARGS=%PS_ARGS% -Delete" & shift & goto :arg_loop )
if /i "%~1"=="-concise"          ( set "PS_ARGS=%PS_ARGS% -Concise" & shift & goto :arg_loop )
if /i "%~1"=="-v"                ( set "PS_ARGS=%PS_ARGS% -Verbose" & shift & goto :arg_loop )
REM --- Handle Arguments with values ---
REM Escape %~2 single quotes, then wrap in 'value'
set "ARG_VAL=%~2"
set "ARG_VAL=%ARG_VAL:'=''%"
if /i "%~1"=="-container"        ( set "PS_ARGS=%PS_ARGS% -Container '%ARG_VAL%'" & shift & shift & goto :arg_loop )

:handle_path
REM --- Assume it's a path ---
REM Build PowerShell array elements: 'path'
set "ARG_PATH=%~1%"
set "ARG_PATH=%ARG_PATH:'=''%"
if defined PATHS_ARRAY_ELEMENTS (
    set "PATHS_ARRAY_ELEMENTS=%PATHS_ARRAY_ELEMENTS%, '%ARG_PATH%'"
) else (
    set "PATHS_ARRAY_ELEMENTS='%ARG_PATH%'"
)
shift
goto :arg_loop

:args_done

REM Check if paths were provided
if not defined PATHS_ARRAY_ELEMENTS (
    echo ERROR: No input file or directory paths provided.
    exit /b 1
)

REM Escape script path for PowerShell single quotes and brackets
set "PS_ESCAPED_SCRIPT_PATH=%POWERSHELL_SCRIPT_PATH:'=''%"
set "PS_ESCAPED_SCRIPT_PATH=%PS_ESCAPED_SCRIPT_PATH:[=`[%"
set "PS_ESCAPED_SCRIPT_PATH=%PS_ESCAPED_SCRIPT_PATH:]=`]%"

REM Construct and execute the full PowerShell command string
echo Executing PowerShell command: '%PS_ESCAPED_SCRIPT_PATH%'%PS_ARGS% -Path @^(%PATHS_ARRAY_ELEMENTS%^)
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& '%PS_ESCAPED_SCRIPT_PATH%'%PS_ARGS% -Path @(%PATHS_ARRAY_ELEMENTS%)"

REM Capture the exit code from PowerShell
set "EXIT_CODE=%ERRORLEVEL%"

endlocal
exit /b %EXIT_CODE%
