@echo off
setlocal enabledelayedexpansion

REM --- Batch Default Audio Setter ---
REM Probes audio tracks using ffprobe and sets the default track based on language priority.
REM Options (place BEFORE file/folder paths):
REM   -lang "<list>"     : Comma-separated language priority list (default: %LANG_PRIORITY% = "jpn,chi,kor,eng"). MUST be quoted if contains commas.
REM   -suffix <string>   : Suffix for the output filename (default: %OUTPUT_SUFFIX% = "_reordered")
REM Flags (place BEFORE file/folder paths):
REM   -r                 : Recursive search in folders
REM   -f                 : Force overwrite existing output files
REM   -delete            : Delete original file after successful processing (mutually exclusive with -replace)
REM   -replace           : Replace original file with the processed version (mutually exclusive with -delete)

REM --- Base Directory (do not touch) ---
set "SCRIPT_NAME=%~nx0"
set "BASE_DIR=%~dp0"
if "%BASE_DIR:~-1%"=="\" set "BASE_DIR=%BASE_DIR:~0,-1%"
for %%A in ("%BASE_DIR%") do set "BASE_DIR=%%~dpA"

REM --- SETTINGS ---

REM -- Output Suffix --
set OUTPUT_SUFFIX=_reordered

REM -- Paths (relative to script location) --
set FFMPEG_PATH=
set FFPROBE_PATH=

REM -- Flags --
set DISABLE_WHERE_SEARCH=0
set DO_RECURSE=0
set DO_FORCE=0

REM 0=None, 1=Delete Original, 2=Replace Original
set FILE_ACTION=0

REM -- Language Priority --
set LANG_PRIORITY=jpn,chi,kor,eng

REM --- END OF SETTINGS ---

set PROCESSED_ANY_PATH=0
set STOP_PROCESSING=0

REM --- Locate FFMPEG and FFPROBE ---
REM Priority: 1. Path specified in script config (%FFMPEG_PATH% and %FFPROBE_PATH%)
REM           2. Local executables in script directory (%BASE_DIR%)
REM           3. Path found via 'where' command (unless DISABLE_WHERE_SEARCH is set to 1)
REM           4. Empty path (will cause error later if not found)
echo.

REM Check for local executables
if not exist "%FFMPEG_PATH%" if exist "%BASE_DIR%\ffmpeg.exe" (
    echo Found ffmpeg.exe in script directory.
    set "FFMPEG_PATH=%BASE_DIR%\ffmpeg.exe"
    goto :ffmpeg_path_set
)

if not exist "%FFPROBE_PATH%" if exist "%BASE_DIR%\ffprobe.exe" (
    echo Found ffprobe.exe in script directory.
    set "FFPROBE_PATH=%BASE_DIR%\ffprobe.exe"
    goto :ffprobe_path_set
)

if "%DISABLE_WHERE_SEARCH%"=="1" (
    echo Using configured/default paths due to DISABLE_WHERE_SEARCH flag ^(local executables not found^).
    goto :paths_finalized
)

REM Auto-detect FFMPEG/FFPROBE using 'where'
echo Searching for executables using 'where' command...

if defined FFMPEG_PATH goto :check_ffprobe_where
set FFMPEG_FOUND_BY_WHERE=0
for /f "delims=" %%G in ('where ffmpeg.exe 2^>nul') do (
    echo   Found ffmpeg.exe: %%G
    set "FFMPEG_PATH=%%G"
    set FFMPEG_FOUND_BY_WHERE=1
    goto :check_ffprobe_where
)
if %FFMPEG_FOUND_BY_WHERE% == 0 echo ffmpeg.exe not found via 'where'. Will rely on default/empty path.

:check_ffprobe_where
if defined FFPROBE_PATH goto :paths_finalized
set FFPROBE_FOUND_BY_WHERE=0
for /f "delims=" %%G in ('where ffprobe.exe 2^>nul') do (
    echo   Found ffprobe.exe: %%G
    set "FFPROBE_PATH=%%G"
    set FFPROBE_FOUND_BY_WHERE=1
    goto :paths_finalized
)
if %FFPROBE_FOUND_BY_WHERE% == 0 echo ffprobe.exe not found via 'where'. Will rely on default/empty path.

:paths_finalized
echo Final FFMPEG Path: %FFMPEG_PATH%
echo Final FFPROBE Path: %FFPROBE_PATH%
echo.

REM --- Basic Checks ---
if not exist "%FFMPEG_PATH%" (
    echo ERROR: Cannot find ffmpeg.exe at "%FFMPEG_PATH%"
    goto :eof
)
if not exist "%FFPROBE_PATH%" (
    echo ERROR: Cannot find ffprobe.exe at "%FFPROBE_PATH%"
    goto :eof
)

REM --- Argument Parsing Loop ---
:parse_args_loop
if "%~1"=="" goto :parse_args_done

if /i "%~1"=="-lang" (
    if "%~2"=="" ( echo ERROR: Missing value for -lang flag. & goto :eof )
    set "LANG_PRIORITY=%~2"
    echo Setting Language Priority: !LANG_PRIORITY!
    shift
    shift
    goto :parse_args_loop
)
if /i "%~1"=="-suffix" (
    if "%~2"=="" ( echo ERROR: Missing value for -suffix flag. & goto :eof )
    set "temp_suffix=%~2"
    REM Handle the case where the user explicitly provides "" for a blank suffix
    if "!temp_suffix!"=="" (
        set OUTPUT_SUFFIX=
        echo Setting blank Output Suffix.
    ) else (
        set "OUTPUT_SUFFIX=!temp_suffix!"
        echo Overriding Output Suffix: !OUTPUT_SUFFIX!
    )
    shift
    shift
    goto :parse_args_loop
)

if /i "%~1"=="-delete" (
    if "%FILE_ACTION%"=="2" ( echo ERROR: -delete and -replace flags are mutually exclusive. & goto :eof )
    set FILE_ACTION=1
    echo Set to delete original files on success.
    shift
    goto :parse_args_loop
)
if /i "%~1"=="-replace" (
    if "%FILE_ACTION%"=="1" ( echo ERROR: -delete and -replace flags are mutually exclusive. & goto :eof )
    set FILE_ACTION=2
    echo Set to replace original files on success.
    shift
    goto :parse_args_loop
)

if /i "%~1"=="-r" (
    set DO_RECURSE=1
    echo Recursive flag set.
    shift
    goto :parse_args_loop
)
if /i "%~1"=="-f" (
    set DO_FORCE=1
    echo Force flag set.
    shift
    goto :parse_args_loop
)

REM If it's not a recognized flag, assume it's a path/file
set "CURRENT_ARG=%~1"
echo.

REM Check if argument is a directory
if exist "!CURRENT_ARG!\" (
    echo Found directory: "!CURRENT_ARG!" ^(Recursive: %DO_RECURSE%, Force: %DO_FORCE%^)
    set "PROCESSED_ANY_PATH=1"
    REM Pass quoted arguments to handle potential spaces/commas within them
    call :process_directory "!CURRENT_ARG!" %DO_RECURSE% %DO_FORCE% %FILE_ACTION% "!LANG_PRIORITY!" "!OUTPUT_SUFFIX!"
) else if exist "!CURRENT_ARG!" (
    REM Assume argument is a file
    echo Found file: "!CURRENT_ARG!" ^(Force: %DO_FORCE%^)
    set "PROCESSED_ANY_PATH=1"
    REM Pass quoted arguments to handle potential spaces/commas within them
    call :process_single_file "!CURRENT_ARG!" %DO_FORCE% %FILE_ACTION% "!LANG_PRIORITY!" "!OUTPUT_SUFFIX!"
) else (
    echo WARNING: Argument "!CURRENT_ARG!" is not a recognized flag, file, or directory. Skipping.
)

shift
goto :parse_args_loop

:parse_args_done
echo.

REM --- Check if language priority was set ---
if not defined LANG_PRIORITY (
    echo ERROR: Language priority must be specified using -lang flag ^(e.g., -lang jpn,eng^).
    goto :eof
)

REM --- Check if any valid input path was processed ---
if "%PROCESSED_ANY_PATH%"=="0" (
    echo ERROR: No valid input files or folders were provided or found.
    echo Usage: Drag and drop video files onto this script or run from cmd:
    echo %SCRIPT_NAME% -lang jpn,eng [options] [-r] [-f] "path\to\folder" "path\to\video1.mkv" ...
    goto :eof
)

echo Argument parsing complete.

goto :finished

REM =============================================
REM == Subroutine to process a single file ==
REM =============================================
:process_single_file
REM Parameters: %1=Input File, %2=Force Flag, %3=File Action, %4=Lang Priority, %5=Output Suffix
set "INPUT_FILE=%~1"
set "FORCE_PROCESSING=%2"
set "CURRENT_FILE_ACTION=%3"
set "CURRENT_LANG_PRIORITY=%~4"
set "CURRENT_OUTPUT_SUFFIX=%~5"

if not defined CURRENT_LANG_PRIORITY (
    echo ERROR: Language priority ^(-lang^) was not passed correctly to process_single_file for "!INPUT_FILE!". Skipping.
    goto :eof
)

call :set_default_audio_logic "%INPUT_FILE%" %FORCE_PROCESSING% %CURRENT_FILE_ACTION% "%CURRENT_LANG_PRIORITY%" "%CURRENT_OUTPUT_SUFFIX%"

goto :eof


REM =============================================
REM == Subroutine Logic to set default audio ==
REM =============================================
:set_default_audio_logic
REM Parameters: %1=Input File, %2=Force Flag, %3=File Action, %4=Lang Priority, %5=Output Suffix
set "AUDIO_INPUT_FILE=%~1"
set "AUDIO_INPUT_PATH=%~dp1"
set "AUDIO_INPUT_NAME=%~n1"
set "AUDIO_INPUT_EXT=%~x1"
set "FORCE_PROCESSING=%2"
set "CURRENT_FILE_ACTION=%3"
set "CURRENT_LANG_PRIORITY=%~4"
set "CURRENT_OUTPUT_SUFFIX=%~5"

echo.
echo -----------------------------------------------------
echo Processing Audio for: "!AUDIO_INPUT_FILE!"
echo   Language Priority: %CURRENT_LANG_PRIORITY%
echo   File Action: %CURRENT_FILE_ACTION% (0=None, 1=Delete, 2=Replace)
echo   Output Suffix: %CURRENT_OUTPUT_SUFFIX%
echo   Force Overwrite: %FORCE_PROCESSING%

REM --- Determine Output Filename(s) ---
set FINAL_OUTPUT_FILE=
set FFMPEG_TARGET_FILE=
set "TEMP_SUFFIX=.tmp_reorder"

if "%CURRENT_FILE_ACTION%"=="2" (
    REM Replace Action: Output to temp file first, final target is original file
    set "FFMPEG_TARGET_FILE=%AUDIO_INPUT_PATH%%AUDIO_INPUT_NAME%%TEMP_SUFFIX%%AUDIO_INPUT_EXT%"
    set "FINAL_OUTPUT_FILE=%AUDIO_INPUT_FILE%"
    echo   Action: Replace original. Writing temporary file to: "!FFMPEG_TARGET_FILE!"
) else (
    REM None or Delete Action: Output to file with suffix
    set "FFMPEG_TARGET_FILE=%AUDIO_INPUT_PATH%%AUDIO_INPUT_NAME%%CURRENT_OUTPUT_SUFFIX%%AUDIO_INPUT_EXT%"
    set "FINAL_OUTPUT_FILE=%FFMPEG_TARGET_FILE%"
    echo   Action: Create new file ^(Delete=%CURRENT_FILE_ACTION%^). Target Output File: "!FFMPEG_TARGET_FILE!"
)
echo -----------------------------------------------------

REM --- Check if FINAL target exists (respect -f flag) ---
if not "%CURRENT_FILE_ACTION%"=="2" if exist "%FINAL_OUTPUT_FILE%" (
    if not "%FORCE_PROCESSING%"=="1" (
        echo Skipping reorder, output file "!FINAL_OUTPUT_FILE!" already exists. Use -f to force.
        goto :eof
    ) else (
        echo Forcing reorder, will overwrite existing file "!FINAL_OUTPUT_FILE!".
    )
)

REM --- Get audio stream indices and languages using temp file ---
set "AUDIO_STREAMS_INFO="
set "FIRST_AUDIO_INDEX="
set TOTAL_AUDIO_STREAMS=0
set "TEMP_FFPROBE_AUDIO=%TEMP%\ffprobe_audio_%RANDOM%.txt"

REM Get index and language tag for all audio streams
"%FFPROBE_PATH%" -v error -select_streams a -show_entries stream=index:stream_tags=language -of csv=p=0:nk=1 "%AUDIO_INPUT_FILE%" > "%TEMP_FFPROBE_AUDIO%"
if not !ERRORLEVEL!==0 (
    echo WARNING: ffprobe failed to get audio stream info for "!AUDIO_INPUT_FILE!". Skipping.
    if exist "%TEMP_FFPROBE_AUDIO%" del "%TEMP_FFPROBE_AUDIO%"
    goto :eof
)

REM Read the ffprobe output
if exist "%TEMP_FFPROBE_AUDIO%" (
    for /f "usebackq tokens=1,2 delims=," %%I in ("%TEMP_FFPROBE_AUDIO%") do (
        set "STREAM_INDEX=%%I"
        set "STREAM_LANG=%%J"
        if not defined STREAM_LANG set STREAM_LANG=und
        REM Store as "index:lang " pairs
        set "AUDIO_STREAMS_INFO=!AUDIO_STREAMS_INFO!!STREAM_INDEX!:!STREAM_LANG! "
        if not defined FIRST_AUDIO_INDEX set "FIRST_AUDIO_INDEX=!STREAM_INDEX!"
        set /a TOTAL_AUDIO_STREAMS+=1
    )
    del "%TEMP_FFPROBE_AUDIO%"
)

if "%TOTAL_AUDIO_STREAMS%"=="0" (
    echo No audio streams found in "!AUDIO_INPUT_FILE!". Skipping.
    goto :eof
)
if "%TOTAL_AUDIO_STREAMS%"=="1" (
    echo Only one audio stream found ^(%FIRST_AUDIO_INDEX%^). No reordering needed. Skipping.
    goto :eof
)

echo.
echo Found %TOTAL_AUDIO_STREAMS% audio streams: %AUDIO_STREAMS_INFO%
echo First audio stream index: %FIRST_AUDIO_INDEX%

REM --- Find preferred audio stream based on language priority ---
set DEFAULT_AUDIO_INDEX=
set PRIORITY_LANG_FOUND=0

REM Iterate through the comma-separated language list
REM Remove potential surrounding quotes before iterating
set "CLEAN_LANG_PRIORITY=!CURRENT_LANG_PRIORITY:"=!"
for %%L in (!CLEAN_LANG_PRIORITY!) do (
    if "!PRIORITY_LANG_FOUND!"=="0" (
        set "TARGET_LANG=%%L"
        echo   Checking for language: !TARGET_LANG!
        REM Iterate through the found streams info
        for %%S in (%AUDIO_STREAMS_INFO%) do (
            REM Split "index:lang" pair
            for /f "tokens=1,2 delims=:" %%A in ("%%S") do (
                set "CURRENT_INDEX=%%A"
                set "CURRENT_LANG=%%B"
                echo     Comparing index !CURRENT_INDEX! ^(!CURRENT_LANG!^)...
                if /i "!CURRENT_LANG!"=="!TARGET_LANG!" (
                    echo         Match found.
                    echo Found matching stream: !CURRENT_INDEX! !CURRENT_LANG!
                    set "DEFAULT_AUDIO_INDEX=!CURRENT_INDEX!"
                    set "PRIORITY_LANG_FOUND=1"
                    goto :found_priority_lang
                )
            )
        )
    )
)
:found_priority_lang

REM If no priority language found, default to the first audio stream
if not defined DEFAULT_AUDIO_INDEX (
    echo No priority language match found. Defaulting to first audio stream index: %FIRST_AUDIO_INDEX%
    set "DEFAULT_AUDIO_INDEX=%FIRST_AUDIO_INDEX%"
)

REM --- Construct ffmpeg map arguments ---
set "MAP_ARGS=-map 0:v -map 0:s?"
set "MAP_ARGS=!MAP_ARGS! -map 0:%DEFAULT_AUDIO_INDEX%"

REM Map remaining audio streams
for %%S in (%AUDIO_STREAMS_INFO%) do (
    for /f "tokens=1 delims=:" %%A in ("%%S") do (
        set "CURRENT_INDEX=%%A"
        if not "!CURRENT_INDEX!"=="!DEFAULT_AUDIO_INDEX!" (
            set "MAP_ARGS=!MAP_ARGS! -map 0:!CURRENT_INDEX!"
        )
    )
)

REM --- Execute ffmpeg command ---

echo.
echo Executing: %FFMPEG_PATH% -hide_banner -y ^
    -i "!AUDIO_INPUT_FILE!" ^
    %MAP_ARGS% -c copy ^
    -disposition:a:0 default ^
    "!FFMPEG_TARGET_FILE!"
echo.
call %FFMPEG_PATH% -hide_banner -y ^
    -i "!AUDIO_INPUT_FILE!" ^
    %MAP_ARGS% -c copy ^
    -disposition:a:0 default ^
    "!FFMPEG_TARGET_FILE!"
echo.

if not !ERRORLEVEL!==0 (
    echo ERROR: ffmpeg failed to process audio for "!AUDIO_INPUT_FILE!". Errorlevel: !ERRORLEVEL!
    echo Output file "!FFMPEG_TARGET_FILE!" may be incomplete or corrupted.
    if "%CURRENT_FILE_ACTION%"=="2" if exist "%FFMPEG_TARGET_FILE%" (
        echo Deleting incomplete temporary file "!FFMPEG_TARGET_FILE!".
        del "%FFMPEG_TARGET_FILE%"
    )
    set STOP_PROCESSING=1
    goto :eof
)

echo.
echo Successfully processed audio for "!AUDIO_INPUT_FILE!". Intermediate output: "!FFMPEG_TARGET_FILE!"

REM --- Post-processing File Actions ---
if "%CURRENT_FILE_ACTION%"=="1" (
    REM Delete Original
    echo Deleting original file: "!AUDIO_INPUT_FILE!"
    del "%AUDIO_INPUT_FILE%"
    if not !ERRORLEVEL!==0 (
        echo WARNING: Failed to delete original file "!AUDIO_INPUT_FILE!". It might be in use or permissions denied.
    ) else (
        echo Successfully deleted original file.
    )
) else if "%CURRENT_FILE_ACTION%"=="2" (
    REM Replace Original (Delete original, then rename temp)
    echo Replacing original file "!AUDIO_INPUT_FILE!" with "!FFMPEG_TARGET_FILE!"
    move /y "!FFMPEG_TARGET_FILE!" "!AUDIO_INPUT_FILE!" >nul
    if not !ERRORLEVEL!==0 (
        echo ERROR: Failed to replace original file "!AUDIO_INPUT_FILE!".
        echo Temporary file left at: "!AUDIO_INPUT_FILE!"
        goto :eof
    )
    echo Successfully replaced original file. Final output: "!AUDIO_INPUT_FILE!"
)

goto :eof


REM =============================================
REM == Subroutine to process a directory ==
REM =============================================
:process_directory
REM Parameters: %1=Dir Path, %2=Recursive Flag, %3=Force Flag, %4=File Action, %5=Lang Priority, %6=Output Suffix
set "DIR_PATH=%~1"
set "IS_RECURSIVE=%2"
set "FORCE_PROCESSING_DIR=%3"
set "CURRENT_FILE_ACTION=%4"
set "CURRENT_LANG_PRIORITY=%~5"
set "CURRENT_OUTPUT_SUFFIX=%~6"

echo Searching for video files in "%DIR_PATH%" ^(Recursive: %IS_RECURSIVE%, Force: %FORCE_PROCESSING_DIR%, Action: %CURRENT_FILE_ACTION%^)...

if "%IS_RECURSIVE%"=="1" (
    for /r "%DIR_PATH%" %%F in (*.mkv *.mp4 *.avi *.mov *.wmv *.flv *.ts *.webm) do (
        echo Found recursive: "%%F"
        call :process_single_file "%%F" %FORCE_PROCESSING_DIR% %CURRENT_FILE_ACTION% "%CURRENT_LANG_PRIORITY%" "%CURRENT_OUTPUT_SUFFIX%"
        if "!STOP_PROCESSING!"=="1" goto :eof
    )
) else (
    for %%F in ("%DIR_PATH%\*.mkv" "%DIR_PATH%\*.mp4" "%DIR_PATH%\*.avi" "%DIR_PATH%\*.mov" "%DIR_PATH%\*.wmv" "%DIR_PATH%\*.flv" "%DIR_PATH%\*.ts" "%DIR_PATH%\*.webm") do (
        echo Found: "%%F"
        call :process_single_file "%%F" %FORCE_PROCESSING_DIR% %CURRENT_FILE_ACTION% "%CURRENT_LANG_PRIORITY%" "%CURRENT_OUTPUT_SUFFIX%"
        if "!STOP_PROCESSING!"=="1" goto :eof
    )
)

goto :eof


:finished
echo.
echo All arguments processed.
endlocal
