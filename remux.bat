@echo off
setlocal enabledelayedexpansion

REM --- Batch Remuxer ---
REM Remuxes video files, copying video and audio streams to a new container.
REM Options (place BEFORE file/folder paths):
REM   -container <string> : Output container format (default: %OUTPUT_FORMAT% = "mp4")
REM Flags (place BEFORE file/folder paths):
REM   -r                  : Recursive search in folders
REM   -f                  : Force overwrite existing output files
REM   -no-where           : Disable auto-detection of ffmpeg/ffprobe via 'where' command
REM   -delete             : Delete original file after successful remux (USE WITH CAUTION!)

REM --- Paths (relative to script location) ---
set FFMPEG_PATH=
set FFPROBE_PATH=
set DISABLE_WHERE_SEARCH=0
REM Set to 1 to auto-enable recursion
set DO_RECURSE=0
set DO_FORCE=0
set DO_DELETE=0
set PROCESSED_ANY_PATH=0
set OUTPUT_FORMAT=mp4
set OUTPUT_EXT=.%OUTPUT_FORMAT%

REM --- END OF SETTINGS ---

REM --- Locate FFMPEG and FFPROBE ---
REM Check for local executables first
if exist "%~dp0\ffmpeg.exe" (
    echo Found ffmpeg.exe in script directory.
    set "FFMPEG_PATH=%~dp0\ffmpeg.exe"
    goto :ffmpeg_path_set
)

if exist "%~dp0\ffprobe.exe" (
    echo Found ffprobe.exe in script directory.
    set "FFPROBE_PATH=%~dp0\ffprobe.exe"
    goto :ffprobe_path_set
)

if "%DISABLE_WHERE_SEARCH%"=="1" (
    echo Using configured/default paths due to -no-where flag ^(local executables not found^).
    goto :paths_finalized
)

REM --- Auto-detect FFMPEG/FFPROBE using 'where' command ---
echo Searching for executables using 'where' command...

:check_ffmpeg_where
if defined FFMPEG_PATH goto :ffmpeg_path_set
set FFMPEG_FOUND_BY_WHERE=0
for /f "delims=" %%G in ('where ffmpeg.exe 2^>nul') do (
    echo Found ffmpeg.exe via 'where': %%G
    set "FFMPEG_PATH=%%G"
    set FFMPEG_FOUND_BY_WHERE=1
    goto :ffmpeg_path_set
)
if %FFMPEG_FOUND_BY_WHERE% == 0 echo ffmpeg.exe not found via 'where'. Will rely on default/empty path.
:ffmpeg_path_set

:check_ffprobe_where
if defined FFPROBE_PATH goto :ffprobe_path_set
set FFPROBE_FOUND_BY_WHERE=0
for /f "delims=" %%G in ('where ffprobe.exe 2^>nul') do (
    echo Found ffprobe.exe via 'where': %%G
    set "FFPROBE_PATH=%%G"
    set FFPROBE_FOUND_BY_WHERE=1
    goto :ffprobe_path_set
)
if %FFPROBE_FOUND_BY_WHERE% == 0 echo ffprobe.exe not found via 'where'. Will rely on default/empty path.
:ffprobe_path_set

:paths_finalized
echo Final FFMPEG Path: %FFMPEG_PATH%
echo Final FFPROBE Path: %FFPROBE_PATH%

REM --- Basic Checks ---
if not exist "%FFMPEG_PATH%" (
    echo ERROR: Cannot find ffmpeg.exe at %FFMPEG_PATH%
    goto :eof
)
REM ffprobe is not strictly needed for remuxing, but we check if found for consistency
if not exist "%FFPROBE_PATH%" (
    echo WARNING: Cannot find ffprobe.exe at %FFPROBE_PATH%. Path detection might be limited.
)

REM Save the original script name for later use
set "SCRIPT_NAME=%~nx0"

REM --- Argument Parsing Loop ---
:parse_args_loop
if "%~1"=="" goto :parse_args_done

if /i "%~1"=="-container" (
    if "%~2"=="" ( echo ERROR: Missing value for -ext flag. & goto :eof )
    set "OUTPUT_EXT=.%~2"
    echo Setting Output Extension: !OUTPUT_EXT!
    shift
    shift
    goto :parse_args_loop
)

if /i "%~1"=="-no-where" (
    set DISABLE_WHERE_SEARCH=1
    echo Disabling 'where' search for executables.
    shift
    goto :parse_args_loop
)
if /i "%~1"=="-r" (
    set DO_RECURSE=1
    echo Recursive flag set for next path.
    shift
    goto :parse_args_loop
)
if /i "%~1"=="-f" (
    set DO_FORCE=1
    echo Force flag set for next path.
    shift
    goto :parse_args_loop
)
if /i "%~1"=="-delete" (
    set DO_DELETE=1
    echo Set to delete original files on successful remux...
    shift
    goto :parse_args_loop
)

REM If it's not a recognized flag, assume it's a path/file
set "CURRENT_ARG=%~1"
echo Processing argument: "!CURRENT_ARG!" (Recursive: %DO_RECURSE%, Force: %DO_FORCE%, Delete: %DO_DELETE%)

REM Check if argument is a directory
if exist "!CURRENT_ARG!\" (
    echo Processing directory: "!CURRENT_ARG!"
    set "PROCESSED_ANY_PATH=1"
    call :process_directory "!CURRENT_ARG!" %DO_RECURSE% %DO_FORCE% %DO_DELETE%
) else if exist "!CURRENT_ARG!" (
    REM Assume argument is a file
    echo Processing file: "!CURRENT_ARG!"
    set "PROCESSED_ANY_PATH=1"
    call :process_single_file "!CURRENT_ARG!" %DO_FORCE% %DO_DELETE%
) else (
    echo WARNING: Argument "!CURRENT_ARG!" is not a recognized flag, file, or directory. Skipping.
)

shift
goto :parse_args_loop

:parse_args_done
echo Argument parsing complete.

REM --- Check if any valid input path was processed ---
if "%PROCESSED_ANY_PATH%"=="0" (
    echo ERROR: No valid input files or folders were provided or found.
    echo Usage: Drag and drop video files onto this script or run from cmd:
    echo %SCRIPT_NAME% [-container mp4] [-no-where] [-r] [-f] [-delete] "path\to\folder" "path\to\video1.mkv" ...
)

goto :eof

REM =============================================
REM == Subroutine to process a single file ==
REM =============================================
:process_single_file
REM --- Check if input argument is empty ---
if "%~1"=="" (
    echo Processed all files in this batch.
    goto :eof
)
set "INPUT_FILE=%~1"
set "FORCE_PROCESSING=%2"
set "DELETE_ORIGINAL_FLAG=%3"

call :remux_file_logic "!INPUT_FILE!" %FORCE_PROCESSING% %DELETE_ORIGINAL_FLAG%

goto :eof


REM =============================================
REM == Subroutine Logic to remux a file ==
REM =============================================
:remux_file_logic
REM Parameters: %1 = Input File Path, %2 = Force Flag (0 or 1), %3 = Delete Flag (0 or 1)
set "INPUT_FILE=%~1"
set "INPUT_PATH=%~dp1"
set "INPUT_NAME=%~n1"
set "FORCE_PROCESSING=%2"
set "DELETE_ORIGINAL_FLAG=%3"

set "OUTPUT_FILE=!INPUT_PATH!!INPUT_NAME!!OUTPUT_EXT!"

REM Check if input and output are the same
if /i "!INPUT_FILE!"=="!OUTPUT_FILE!" (
    echo Skipping remux, input and output file are the same: "!INPUT_FILE!"
    goto :eof
)

REM Check if output exists (respect -f flag)
set DO_REMUX=1
if exist "!OUTPUT_FILE!" (
    if not "%FORCE_PROCESSING%"=="1" (
        echo Skipping remux, output file "!OUTPUT_FILE!" already exists. Use -f to force.
        set DO_REMUX=0
    ) else (
        echo Forcing remux, will overwrite existing file "!OUTPUT_FILE!".
    )
)

REM Determine appropriate map arguments based on output container
set "MAP_ARGS=-map 0:v? -map 0:a?"

if /i "!OUTPUT_EXT!"==".mkv" (
    set "MAP_ARGS=!MAP_ARGS! -map 0:s?"
) else if /i "!OUTPUT_EXT!"==".mov" (
    set "MAP_ARGS=!MAP_ARGS! -map 0:s?"
) else if /i "!OUTPUT_EXT!"==".avi" (
    set "MAP_ARGS=!MAP_ARGS! -map 0:s?"
) else if /i "!OUTPUT_EXT!"==".webm" (
    set "MAP_ARGS=!MAP_ARGS! -map 0:s?"
) else if /i "!OUTPUT_EXT!"==".ts" (
    set "MAP_ARGS=!MAP_ARGS! -map 0:s? -map 0:d?"
)
REM Add more 'else if' blocks here for other containers if needed

REM Execute ffmpeg remux command
if "!DO_REMUX!"=="1" (
    set "REMUX_CMD="%FFMPEG_PATH%" -hide_banner"
    if "%FORCE_PROCESSING%"=="1" set "REMUX_CMD=!REMUX_CMD! -y"
    set "REMUX_CMD=!REMUX_CMD! -i "!INPUT_FILE!" -c copy !MAP_ARGS! "!OUTPUT_FILE!""

    echo Executing: !REMUX_CMD!
    call !REMUX_CMD!
    if not errorlevel 0 (
        echo ERROR: ffmpeg failed to remux file "!INPUT_FILE!". Errorlevel: %ERRORLEVEL%
        if exist "!OUTPUT_FILE!" del "!OUTPUT_FILE!"
    ) else (
        echo Successfully remuxed "!INPUT_FILE!" to "!OUTPUT_FILE!".
        REM --- Delete Original File if Flag is Set and Remux Succeeded ---
        if "%DELETE_ORIGINAL_FLAG%"=="1" if exist "!OUTPUT_FILE!" (
            echo Deleting original file: "!INPUT_FILE!"
            del "!INPUT_FILE!"
            if not errorlevel 0 (
                echo WARNING: Failed to delete original file "!INPUT_FILE!". It might be in use or permissions are denied.
            ) else (
                echo Successfully deleted original file: "!INPUT_FILE!"
            )
        )
    )
)

goto :eof


REM =============================================
REM == Subroutine to process a directory ==
REM =============================================
:process_directory
set "DIR_PATH=%~1"
set "IS_RECURSIVE=%2"
set "FORCE_PROCESSING_DIR=%3"
set "DELETE_ORIGINAL_FILES=%4"

echo Searching for video files in "%DIR_PATH%" ^(Recursive: %IS_RECURSIVE%, Force: %FORCE_PROCESSING_DIR%, Delete: %DELETE_ORIGINAL_FILES%^)...

REM Define common video extensions
set "VIDEO_EXTENSIONS=*.mkv *.mp4 *.avi *.mov *.wmv *.flv *.ts *.webm *.mpg *.mpeg"

if "%IS_RECURSIVE%"=="1" (
    for /r "%DIR_PATH%" %%F in (%VIDEO_EXTENSIONS%) do (
        echo Found recursive: "%%F"
        call :process_single_file "%%F" %FORCE_PROCESSING_DIR% %DELETE_ORIGINAL_FILES%
        if "!STOP_PROCESSING!"=="1" goto :eof
    )
) else (
    for %%F in ("%DIR_PATH%\*.mkv" "%DIR_PATH%\*.mp4" "%DIR_PATH%\*.avi" "%DIR_PATH%\*.mov" "%DIR_PATH%\*.wmv" "%DIR_PATH%\*.flv" "%DIR_PATH%\*.ts" "%DIR_PATH%\*.webm" "%DIR_PATH%\*.mpg" "%DIR_PATH%\*.mpeg") do (
        echo Found: "%%F"
        call :process_single_file "%%F" %FORCE_PROCESSING_DIR% %DELETE_ORIGINAL_FILES%
        if "!STOP_PROCESSING!"=="1" goto :eof
    )
)

goto :eof


:finished
echo.
echo All arguments processed.
endlocal
