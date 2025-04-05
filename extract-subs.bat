@echo off
setlocal enabledelayedexpansion

REM --- Batch Subtitle Extractor ---
REM Extracts subtitle streams from video files using ffmpeg.
REM Options (place BEFORE file/folder paths):
REM   -format <string>   : Output filename format (FILE, lang, title; default: %OUTPUT_FILENAME_FORMAT% = "FILE.lang.title" for Jellyfin compatibility)
REM   -suffix <string>   : Suffix to append after the base filename (default: %OUTPUT_SUFFIX%)
REM Flags (place BEFORE file/folder paths):
REM   -r                 : Recursive search in folders
REM   -f                 : Force overwrite existing subtitle files
REM   -no-where          : Disable auto-detection of ffmpeg/ffprobe via 'where' command (binaries in the same folder as this script will be used regardless)

REM --- Paths (relative to script location) ---
set FFMPEG_PATH=
set FFPROBE_PATH=
set DISABLE_WHERE_SEARCH=0
REM Set to 1 to auto-enable recursion
set DO_RECURSE=0
set DO_FORCE=0
set PROCESSED_ANY_PATH=0
set OUTPUT_FILENAME_FORMAT=FILE.lang.title
set OUTPUT_SUFFIX=_upscaled
REM Jellyfin format: "FILE.lang.title"

REM --- END OF SETTINGS ---

REM --- Locate FFMPEG and FFPROBE ---
REM Priority: 1. Executable in script directory (%~dp0)
REM           2. Path found via 'where' command (unless -no-where is used)
REM           3. Empty path (will cause error later if not found)

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
if not exist "%FFPROBE_PATH%" (
    echo ERROR: Cannot find ffprobe.exe at %FFPROBE_PATH%
    goto :eof
)

REM --- Argument Parsing Loop ---
:parse_args_loop
if "%~1"=="" goto :parse_args_done

if /i "%~1"=="-format" (
    if "%~2"=="" ( echo ERROR: Missing value for -format flag. & goto :eof )
    set "OUTPUT_FILENAME_FORMAT=%~2"
    echo Overriding Output Filename Format: %OUTPUT_FILENAME_FORMAT%
    shift
    shift
    goto :parse_args_loop
)
if /i "%~1"=="-suffix" (
    if "%~2"=="" ( echo ERROR: Missing value for -suffix flag. & goto :eof )
    set "temp_suffix=%~2"
    REM Handle the case where the user explicitly provides "" for a blank suffix
    if "!temp_suffix!"=="" (
        set "OUTPUT_SUFFIX="
        echo Setting blank Output Suffix.
    ) else (
        set "OUTPUT_SUFFIX=!temp_suffix!"
        echo Overriding Output Suffix: !OUTPUT_SUFFIX!
    )
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

REM If it's not a recognized flag, assume it's a path/file
set "CURRENT_ARG=%~1"
echo Processing argument: "!CURRENT_ARG!" (Recursive: %DO_RECURSE%, Force: %DO_FORCE%)

REM Check if argument is a directory
if exist "!CURRENT_ARG!\" (
    echo Processing directory: "!CURRENT_ARG!"
    set "PROCESSED_ANY_PATH=1"
    call :process_directory "!CURRENT_ARG!" %DO_RECURSE% %DO_FORCE%
) else if exist "!CURRENT_ARG!" (
    REM Assume argument is a file
    echo Processing file: "!CURRENT_ARG!"
    set "PROCESSED_ANY_PATH=1"
    call :process_single_file "!CURRENT_ARG!" %DO_FORCE%
) else (
    echo WARNING: Argument "!CURRENT_ARG!" is not a recognized flag, file, or directory. Skipping.
)

REM Reset flags for the *next* argument
set DO_RECURSE=0
set DO_FORCE=0
shift
goto :parse_args_loop

:parse_args_done
echo Argument parsing complete.

REM --- Check if any valid input path was processed ---
if "%PROCESSED_ANY_PATH%"=="0" (
    echo ERROR: No valid input files or folders were provided or found.
    echo Usage: Drag and drop video files onto this script or run from cmd:
    echo %~nx0 [-no-where] [-r] [-f] "path\to\folder" "path\to\video1.mkv" ...
    goto :eof
)
set STOP_PROCESSING=0


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

call :extract_subtitles_logic "%INPUT_FILE%" %FORCE_PROCESSING%

goto :eof


REM =============================================
REM == Subroutine Logic to extract subtitles ==
REM =============================================
:extract_subtitles_logic
REM Parameters: %1 = Input File Path, %2 = Force Flag (0 or 1)
set "SUB_INPUT_FILE=%~1"
set "SUB_INPUT_PATH=%~dp1"
set "SUB_INPUT_NAME=%~n1"
set "FORCE_PROCESSING=%2"

REM --- Get subtitle stream indices using temp file ---
set SUB_INDICES=
set "TEMP_FFPROBE_IDX=%TEMP%\ffprobe_subidx_%RANDOM%.txt"
"%FFPROBE_PATH%" -v error -select_streams s -show_entries stream=index -of csv=p=0 "%SUB_INPUT_FILE%" > "%TEMP_FFPROBE_IDX%"
if not errorlevel 0 (
    echo WARNING: ffprobe failed to get subtitle indices for "%SUB_INPUT_FILE%". Maybe no subtitles? Skipping extraction for this file.
    if exist "%TEMP_FFPROBE_IDX%" del "%TEMP_FFPROBE_IDX%"
    goto :eof
)

if exist "%TEMP_FFPROBE_IDX%" (
    for /f "usebackq tokens=*" %%I in ("%TEMP_FFPROBE_IDX%") do (
        set SUB_INDICES=!SUB_INDICES! %%I
    )
    del "%TEMP_FFPROBE_IDX%"
)

if not defined SUB_INDICES (
    echo No subtitle streams found to extract in "%SUB_INPUT_FILE%".
    goto :eof
)

echo Found subtitle stream indices:%SUB_INDICES%

set "EXTRACT_CMD="%FFMPEG_PATH%" -hide_banner -y -i "%SUB_INPUT_FILE%""
set "temp_cmd=!EXTRACT_CMD!"
REM --- Collect data for each stream ---
for %%I in (%SUB_INDICES%) do (
    set SUB_INDEX=%%I
    echo Processing subtitle stream index: !SUB_INDEX!

    REM Get codec name using temp file
    set SUB_CODEC=
    set "TEMP_FFPROBE_CODEC=%TEMP%\ffprobe_subcodec_%RANDOM%.txt"
    "%FFPROBE_PATH%" -v error -select_streams !SUB_INDEX! -show_entries stream=codec_name -of csv=p=0 "%SUB_INPUT_FILE%" > "!TEMP_FFPROBE_CODEC!"
    if exist "!TEMP_FFPROBE_CODEC!" (
        for /f "usebackq tokens=*" %%C in ("!TEMP_FFPROBE_CODEC!") do (
            set SUB_CODEC=%%C
        )
        del "!TEMP_FFPROBE_CODEC!"
    )
    if not defined SUB_CODEC set SUB_CODEC=unknown

    REM Determine extension
    set SUB_EXT=
    if /i "!SUB_CODEC!"=="subrip" set SUB_EXT=.srt
    if /i "!SUB_CODEC!"=="srt" set SUB_EXT=.srt
    if /i "!SUB_CODEC!"=="ass" set SUB_EXT=.ass
    if /i "!SUB_CODEC!"=="ssa" set SUB_EXT=.ass
    if /i "!SUB_CODEC!"=="mov_text" set SUB_EXT=.srt
    if /i "!SUB_CODEC!"=="webvtt" set SUB_EXT=.vtt
    REM Add more mappings if needed

    if not defined SUB_EXT (
        echo WARNING: Unknown codec "!SUB_CODEC!" for subtitle stream !SUB_INDEX!. Skipping extraction.
        goto :eof
    )
    echo Detected codec: "!SUB_CODEC!" ^(extension: "!SUB_EXT!"^)

    REM Get Language using temp file
    set SUB_LANG=und
    set "TEMP_FFPROBE_LANG=%TEMP%\ffprobe_sublang_%RANDOM%.txt"
    "%FFPROBE_PATH%" -v error -select_streams !SUB_INDEX! -show_entries stream_tags=language -of csv=p=0 "%SUB_INPUT_FILE%" > "!TEMP_FFPROBE_LANG!"
    if exist "!TEMP_FFPROBE_LANG!" (
        for /f "usebackq tokens=*" %%L in ("!TEMP_FFPROBE_LANG!") do (
             if not "%%L"=="N/A" if not "%%L"=="" set SUB_LANG=%%L
        )
        del "!TEMP_FFPROBE_LANG!"
    )

    REM Get title for filename using temp file (prefer title over index)
    set SUB_TAG=stream!SUB_INDEX!

    REM Get Title
    set SUB_TITLE=
    set "TEMP_FFPROBE_TITLE=%TEMP%\ffprobe_subtitle_%RANDOM%.txt"
    "%FFPROBE_PATH%" -v error -select_streams !SUB_INDEX! -show_entries stream_tags=title -of csv=p=0 "%SUB_INPUT_FILE%" > "!TEMP_FFPROBE_TITLE!"
    if exist "!TEMP_FFPROBE_TITLE!" (
        for /f "usebackq tokens=*" %%T in ("!TEMP_FFPROBE_TITLE!") do (
            if not "%%T"=="N/A" if not "%%T"=="" set SUB_TITLE=%%T
        )
        del "!TEMP_FFPROBE_TITLE!"
    )

    if defined SUB_TITLE (
        set SUB_TAG=!SUB_TITLE!
    ) else (
        REM Use Language if Title not found and language is defined and not 'und'
        if defined SUB_LANG if not "!SUB_LANG!"=="und" set SUB_TAG=!SUB_LANG!
    )

    REM Sanitize SUB_TAG for filename (basic)
    set "SUB_TAG_SAFE=!SUB_TAG::=_!"
    set "SUB_TAG_SAFE=!SUB_TAG_SAFE:/=_!"
    set "SUB_TAG_SAFE=!SUB_TAG_SAFE:\=_!"
    set "SUB_TAG_SAFE=!SUB_TAG_SAFE:?=_!"
    set "SUB_TAG_SAFE=!SUB_TAG_SAFE:"=_!"
    set "SUB_TAG_SAFE=!SUB_TAG_SAFE:<=>_!"
    set "SUB_TAG_SAFE=!SUB_TAG_SAFE:|=_!"
    set "SUB_TAG_SAFE=!SUB_TAG_SAFE:^*=_!"
    REM Remove leading/trailing spaces
    for /f "tokens=* delims= " %%A in ("!SUB_TAG_SAFE!") do set "SUB_TAG_SAFE=%%A"
    REM Replace consecutive underscores with a single one
    :replace_loop
    set "PREV_TAG=!SUB_TAG_SAFE!"
    set "SUB_TAG_SAFE=!SUB_TAG_SAFE:__=_!"
    if not "!PREV_TAG!"=="!SUB_TAG_SAFE!" goto :replace_loop
    REM Remove leading/trailing underscores
    if "!SUB_TAG_SAFE:~0,1!"=="_" set "SUB_TAG_SAFE=!SUB_TAG_SAFE:~1!"
    if "!SUB_TAG_SAFE:~-1!"=="_" set "SUB_TAG_SAFE=!SUB_TAG_SAFE:~0,-1!"
    REM If tag becomes empty after sanitizing, revert to default
    if not defined SUB_TAG_SAFE set "SUB_TAG_SAFE=stream!SUB_INDEX!"

    REM Construct output filename based on format string
    set "FORMATTED_NAME=%OUTPUT_FILENAME_FORMAT%"
    set "FORMATTED_NAME=!FORMATTED_NAME:FILE=%SUB_INPUT_NAME%%OUTPUT_SUFFIX%!"

    REM Replace title placeholder
    set TITLE_PRESENT=0
    echo "!FORMATTED_NAME!" | findstr /C:"title" >nul && set TITLE_PRESENT=1
    if "!TITLE_PRESENT!"=="1" (
        if defined SUB_TAG_SAFE (
            REM Use CALL SET to handle delayed expansion within replacement
            CALL SET "FORMATTED_NAME=%%^FORMATTED_NAME:title=!SUB_TAG_SAFE!%%"
        ) else (
            REM Remove placeholder and preceding dot if title metadata is missing
            set "FORMATTED_NAME=!FORMATTED_NAME:.title=!"
        )
    )

    REM Replace lang placeholder
    set LANG_PRESENT=0
    echo "!FORMATTED_NAME!" | findstr /C:"lang" >nul && set LANG_PRESENT=1
    if "!LANG_PRESENT!"=="1" (
        if defined SUB_LANG if /i not "!SUB_LANG!"=="und" (
            CALL SET "FORMATTED_NAME=%%^FORMATTED_NAME:lang=!SUB_LANG!%%"
        ) else (
            REM Remove placeholder and preceding dot if lang metadata is missing/und
            set "FORMATTED_NAME=!FORMATTED_NAME:.lang=!"
        )
    )

    REM Clean up potential double dots, leading/trailing dots
    :cleanup_dots_loop
    set "PREV_FORMATTED_NAME=!FORMATTED_NAME!"
    set "FORMATTED_NAME=!FORMATTED_NAME:..=.!"
    if not "!PREV_FORMATTED_NAME!"=="!FORMATTED_NAME!" goto :cleanup_dots_loop

    if "!FORMATTED_NAME:~0,1!"=="." set "FORMATTED_NAME=!FORMATTED_NAME:~1!"
    if "!FORMATTED_NAME:~-1!"=="." set "FORMATTED_NAME=!FORMATTED_NAME:~0,-1!"

    REM Final output path
    set "OUTPUT_SUB_FILE=!SUB_INPUT_PATH!!FORMATTED_NAME!!SUB_EXT!"
    echo Outputting to: "!OUTPUT_SUB_FILE!"

    REM Check if output exists (respect -f flag)
    set DO_EXTRACT=1
    if exist "!OUTPUT_SUB_FILE!" (
        if not "%FORCE_PROCESSING%"=="1" (
            echo Skipping extraction, output file "!OUTPUT_SUB_FILE!" already exists. Use -f to force.
            set DO_EXTRACT=0
        ) else (
            echo Forcing extraction, queueing to overwrite existing file "!OUTPUT_SUB_FILE!".
        )
    )

    REM Execute ffmpeg extraction command
    if "!DO_EXTRACT!"=="1" (
        set "EXTRACT_CMD=!EXTRACT_CMD! -map 0:!SUB_INDEX! -c copy "!OUTPUT_SUB_FILE!""
        if errorlevel 1 (
            echo ERROR: ffmpeg failed to extract subtitle stream !SUB_INDEX!. Errorlevel: %ERRORLEVEL%
            REM Decide whether to stop or continue with other streams/files? Currently continues.
        ) else (
            echo Successfully collected stream !SUB_INDEX!.
        )
    )
)

if not "!EXTRACT_CMD!"=="!temp_cmd!" (
    echo Executing: !EXTRACT_CMD!
    call !EXTRACT_CMD!
) else (
    echo No valid subtitle streams found to extract.
    goto :eof
)

echo Finished subtitle extraction for "%SUB_INPUT_FILE%".
goto :eof


REM =============================================
REM == Subroutine to process a directory ==
REM =============================================
:process_directory
set "DIR_PATH=%~1"
set "IS_RECURSIVE=%2"
set "FORCE_PROCESSING_DIR=%3"

echo Searching for video files in "%DIR_PATH%" ^(Recursive: %IS_RECURSIVE%^)...

if "%IS_RECURSIVE%"=="1" (
    for /r "%DIR_PATH%" %%F in (*.mkv *.mp4 *.avi *.mov *.wmv *.flv) do (
        echo Found recursive: "%%F"
        call :process_single_file "%%F" %FORCE_PROCESSING_DIR%
        if "!STOP_PROCESSING!"=="1" goto :eof
    )
) else (
    for %%F in ("%DIR_PATH%\*.mkv" "%DIR_PATH%\*.mp4" "%DIR_PATH%\*.avi" "%DIR_PATH%\*.mov" "%DIR_PATH%\*.wmv" "%DIR_PATH%\*.flv") do (
        echo Found: "%%F"
        call :process_single_file "%%F" %FORCE_PROCESSING_DIR%
        if "!STOP_PROCESSING!"=="1" goto :eof
    )
)

goto :eof


:finished
echo.
echo All arguments processed.
endlocal
