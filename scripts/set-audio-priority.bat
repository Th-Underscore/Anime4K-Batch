@echo off

REM --- Wrapper script to call set-audio-priority.ps1 ---
REM Parses original batch arguments and maps them to PowerShell parameters.

set "SCRIPT_DIR=%~dp0"
set "POWERSHELL_SCRIPT_PATH=%SCRIPT_DIR%powershell\set-audio-priority.ps1"

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
if /i "%~1"=="-replace"          ( set "PS_ARGS=%PS_ARGS% -Replace" & shift & goto :arg_loop )
if /i "%~1"=="-concise"          ( set "PS_ARGS=%PS_ARGS% -Concise" & shift & goto :arg_loop )
if /i "%~1"=="-v"                ( set "PS_ARGS=%PS_ARGS% -Verbose" & shift & goto :arg_loop )
REM --- Handle Arguments with values ---
REM Escape %~2 single quotes, then wrap in 'value'
set "ARG_VAL=%~2"
set "ARG_VAL=%ARG_VAL:'=''%"

if /i "%~1"=="-lang"             ( set "PS_ARGS=%PS_ARGS% -Lang '%ARG_VAL%'" & shift & shift & goto :arg_loop )
if /i "%~1"=="-title"            ( set "PS_ARGS=%PS_ARGS% -Title '%ARG_VAL%'" & shift & shift & goto :arg_loop )
if /i "%~1"=="-suffix"           ( set "PS_ARGS=%PS_ARGS% -Suffix '%ARG_VAL%'" & shift & shift & goto :arg_loop )
if /i "%~1"=="-config"              ( set "PS_ARGS=%PS_ARGS% -ConfigPath '%ARG_VAL%'" & shift & shift & goto :arg_loop )

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

call "%SCRIPT_DIR%\utils\exec_pwsh.cmd" "%POWERSHELL_SCRIPT_PATH%" %PS_ARGS% -Path "%PATHS_ARRAY_ELEMENTS%"

REM Capture the exit code from PowerShell
set "EXIT_CODE=%ERRORLEVEL%"

exit /b %EXIT_CODE%
