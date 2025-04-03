@echo off
setlocal enabledelayedexpansion

REM --- Anime4K-GUI Batch Transcoder ---
REM Replicates the core ffmpeg transcoding logic of the Anime4K-GUI project.
REM Edit the SETTINGS section below before running.
REM Usage: drag and drop video files/folders onto this script, or run from cmd:
REM        Anime4K-Batch.bat [options] [-no-where] [-r] [-f] "path\to\folder" "path\to\video1.mkv" ...
REM Options:
REM   -w <width>         : Target output width (default: %TARGET_RESOLUTION_W%)
REM   -h <height>        : Target output height (default: %TARGET_RESOLUTION_H%)
REM   -shader <file>     : Shader filename (default: %SHADER_FILE%)
REM   -shaderpath <path> : Path to shaders folder (default: %SHADER_BASE_PATH%)
REM   -cqp <value>       : Constant Quantization Parameter (default: %CQP%)
REM Flags:
REM   -r        : Recursive search in folders (place BEFORE folder path)
REM   -f        : Force overwrite existing output (place BEFORE file/folder path)
REM   -no-where : Disable auto-detection of ffmpeg/ffprobe via 'where' command

REM --- SETTINGS ---

REM --- Target Resolution ---
REM Options based on Go code: 1024x768, 1440x1080, 1920x1440, 2880x2160 (4:3)
REM                          1280x720, 1920x1080, 2560x1440, 3840x2160 (16:9)
set TARGET_RESOLUTION_W=3840
set TARGET_RESOLUTION_H=2160

REM --- Shader File ---
REM Choose the .glsl file from the 'shaders' directory.
REM Options based on Go code: Anime4K_ModeA.glsl, Anime4K_ModeA_A.glsl, Anime4K_ModeA_A-fast.glsl,
REM                           Anime4K_ModeB.glsl, Anime4K_ModeB_B.glsl, Anime4K_ModeC.glsl,
REM                           Anime4K_ModeC_A.glsl, FSRCNNX_x2_16-0-4-1.glsl
set SHADER_FILE=shaders\Anime4K_ModeA_A-fast.glsl

REM --- Encoder & Hardware Acceleration ---
REM Choose the encoder AND the corresponding hardware acceleration type.
REM Options:
REM   cpu_h264    (libx264, no hwaccel)
REM   cpu_h265    (libx265, no hwaccel)
REM   cpu_av1     (libsvtav1, no hwaccel)
REM   nvidia_h264 (h264_nvenc, cuda hwaccel)
REM   nvidia_h265 (hevc_nvenc, cuda hwaccel)
REM   nvidia_av1  (av1_nvenc, cuda hwaccel) - Requires RTX 4000+
REM   amd_h264    (h264_amf, opencl hwaccel)
REM   amd_h265    (hevc_amf, opencl hwaccel)
REM   amd_av1     (av1_amf, opencl hwaccel) - Requires RX 7000+
set ENCODER_PROFILE=nvidia_h265

REM --- Constant Quantization Parameter (CQP) ---
REM Lower value = better quality, larger file. Range (-1)-51. Recommended ~26-32. 24 more or less doubles the file size from 1080p to 2160p. Less than 24 is virtually lossless for anime.
REM Ignored by some hardware encoders (they might use different quality controls not implemented here).
set CQP=24

REM --- Output Format ---
REM Options: mkv, mp4, avi
REM MKV is recommended, especially if input has subtitles.
set OUTPUT_FORMAT=mkv

REM --- CPU Threads (for CPU encoders only) ---
REM Set the number of threads for libx264, libx265, libsvtav1.
REM Set to 0 to use default (usually all available threads).
set CPU_THREADS=0

REM --- Suffix for Output File ---
set OUTPUT_SUFFIX=_upscaled

REM --- Paths (relative to script location) ---
set FFMPEG_PATH=
set FFPROBE_PATH=
set SHADER_BASE_PATH=%~dp0
set DISABLE_WHERE_SEARCH=0
REM Set to 1 to auto-enable recursion
set RECURSE_NEXT=0
set FORCE_NEXT=0
set PROCESSED_ANY_PATH=0 REM Track if any path was processed

REM Calculate length of suffix for filtering
set OUTPUT_SUFFIX_LEN=0
set "temp_suffix=%OUTPUT_SUFFIX%"
:suffix_len_loop
if defined temp_suffix (
    set /a OUTPUT_SUFFIX_LEN+=1
    set "temp_suffix=!temp_suffix:~1!"
    goto :suffix_len_loop
)

REM --- END OF SETTINGS ---

REM --- Auto-detect FFMPEG/FFPROBE using 'where' command (Conditional) ---
if "%DISABLE_WHERE_SEARCH%"=="1" (
    echo Using configured paths for executables due to -no-where flag.
    goto :skip_where_search
)
echo Searching for executables using 'where'...
set FFMPEG_FOUND_BY_WHERE=0
for /f "delims=" %%G in ('where ffmpeg.exe 2^>nul') do (
    echo Found ffmpeg.exe via 'where': %%G
    set "FFMPEG_PATH=%%G"
    set FFMPEG_FOUND_BY_WHERE=1
    goto :ffmpeg_where_done
)
:ffmpeg_where_done
if %FFMPEG_FOUND_BY_WHERE% == 0 echo ffmpeg.exe not found via 'where', using default path: %FFMPEG_PATH%

set FFPROBE_FOUND_BY_WHERE=0
for /f "delims=" %%G in ('where ffprobe.exe 2^>nul') do (
    echo Found ffprobe.exe via 'where': %%G
    set "FFPROBE_PATH=%%G"
    set FFPROBE_FOUND_BY_WHERE=1
    goto :ffprobe_where_done
)
:ffprobe_where_done
    if %FFPROBE_FOUND_BY_WHERE% == 0 echo ffprobe.exe not found via 'where', using default path: %FFPROBE_PATH%
:skip_where_search


REM --- Basic Checks ---
if not exist "%FFMPEG_PATH%" (
    echo ERROR: Cannot find ffmpeg.exe at %FFMPEG_PATH%
    goto :eof
)
if not exist "%FFPROBE_PATH%" (
    echo ERROR: Cannot find ffprobe.exe at %FFPROBE_PATH%
    goto :eof
)
if not exist "%SHADER_BASE_PATH%%SHADER_FILE%" (
    echo ERROR: Cannot find shader file: %SHADER_BASE_PATH%%SHADER_FILE%
    goto :eof
)


REM --- Determine Encoder and HWAccel Params ---
set VIDEO_CODEC=
set HWACCEL_PARAMS=
set PRESET_PARAM=
set THREAD_PARAM=

if /i "%ENCODER_PROFILE%"=="cpu_h264" (
    set VIDEO_CODEC=libx264
    set PRESET_PARAM=-preset slow
    if not "%CPU_THREADS%"=="0" set THREAD_PARAM=-threads %CPU_THREADS%
) else if /i "%ENCODER_PROFILE%"=="cpu_h265" (
    set VIDEO_CODEC=libx265
    set PRESET_PARAM=-preset slow
    if not "%CPU_THREADS%"=="0" set THREAD_PARAM=-x265-params pools=%CPU_THREADS%
) else if /i "%ENCODER_PROFILE%"=="cpu_av1" (
    set VIDEO_CODEC=libsvtav1
    REM AV1 doesn't use -preset, uses -preset for speed/quality tradeoff differently
    if not "%CPU_THREADS%"=="0" set THREAD_PARAM=-svtav1-params pin=%CPU_THREADS%
) else if /i "%ENCODER_PROFILE%"=="nvidia_h264" (
    set VIDEO_CODEC=h264_nvenc
    set HWACCEL_PARAMS=-hwaccel_device cuda -hwaccel_output_format cuda
    set PRESET_PARAM=-preset p7 -tune hq
) else if /i "%ENCODER_PROFILE%"=="nvidia_h265" (
    set VIDEO_CODEC=hevc_nvenc
    set HWACCEL_PARAMS=-hwaccel_device cuda -hwaccel_output_format cuda
    set PRESET_PARAM=-preset p7 -tune hq -tier high
) else if /i "%ENCODER_PROFILE%"=="nvidia_av1" (
    set VIDEO_CODEC=av1_nvenc
    set HWACCEL_PARAMS=-hwaccel_device cuda -hwaccel_output_format cuda
    set PRESET_PARAM=-preset p7 -tune hq
) else if /i "%ENCODER_PROFILE%"=="amd_h264" (
    set VIDEO_CODEC=h264_amf
    set HWACCEL_PARAMS=-hwaccel_device opencl -hwaccel_output_format opencl
    set PRESET_PARAM=-quality quality
) else if /i "%ENCODER_PROFILE%"=="amd_h265" (
    set VIDEO_CODEC=hevc_amf
    set HWACCEL_PARAMS=-hwaccel_device opencl -hwaccel_output_format opencl
    set PRESET_PARAM=-quality quality
) else if /i "%ENCODER_PROFILE%"=="amd_av1" (
    set VIDEO_CODEC=av1_amf
    set HWACCEL_PARAMS=-hwaccel_device opencl -hwaccel_output_format opencl
    set PRESET_PARAM=-quality quality
) else (
    echo ERROR: Invalid ENCODER_PROFILE selected: %ENCODER_PROFILE%
    goto :eof
)

echo Using Encoder: %VIDEO_CODEC%
if not "%HWACCEL_PARAMS%"=="" echo Using HWAccel: %HWACCEL_PARAMS%


REM --- Argument Parsing Loop ---
:parse_args_loop
if "%~1"=="" goto :parse_args_done

if /i "%~1"=="-no-where" (
    set DISABLE_WHERE_SEARCH=1
    echo Disabling 'where' search for executables.
    shift
    goto :parse_args_loop
)
if /i "%~1"=="-w" (
    if "%~2"=="" ( echo ERROR: Missing value for -w flag. & goto :eof )
    set "TARGET_RESOLUTION_W=%~2"
    echo Overriding Target Width: %TARGET_RESOLUTION_W%
    shift
    shift
    goto :parse_args_loop
)
if /i "%~1"=="-h" (
    if "%~2"=="" ( echo ERROR: Missing value for -h flag. & goto :eof )
    set "TARGET_RESOLUTION_H=%~2"
    echo Overriding Target Height: %TARGET_RESOLUTION_H%
    shift
    shift
    goto :parse_args_loop
)
if /i "%~1"=="-shader" (
    if "%~2"=="" ( echo ERROR: Missing value for -shader flag. & goto :eof )
    set "SHADER_FILE=%~2"
    echo Overriding Shader File: %SHADER_FILE%
    shift
    shift
    goto :parse_args_loop
)
if /i "%~1"=="-shaderpath" (
    if "%~2"=="" ( echo ERROR: Missing value for -shaderpath flag. & goto :eof )
    set "SHADER_BASE_PATH=%~2"
    echo Overriding Shader Base Path: %SHADER_BASE_PATH%
    shift
    shift
    goto :parse_args_loop
)
if /i "%~1"=="-cqp" (
    if "%~2"=="" ( echo ERROR: Missing value for -cqp flag. & goto :eof )
    set "CQP=%~2"
    echo Overriding CQP: %CQP%
    shift
    shift
    goto :parse_args_loop
)
if /i "%~1"=="-r" (
    set RECURSE_NEXT=1
    echo Recursive flag set for next path.
    shift
    goto :parse_args_loop
)
if /i "%~1"=="-f" (
    set FORCE_NEXT=1
    echo Force flag set for next path.
    shift
    goto :parse_args_loop
)

REM If it's not a recognized flag, assume it's a path/file
set "CURRENT_ARG=%~1"
echo Processing argument: "!CURRENT_ARG!" (Recursive: %RECURSE_NEXT%, Force: %FORCE_NEXT%)

REM Check if argument is a directory
if exist "!CURRENT_ARG!\" (
    echo Processing directory: "!CURRENT_ARG!"
    set "PROCESSED_ANY_PATH=1"
    call :process_directory "!CURRENT_ARG!" %RECURSE_NEXT% %FORCE_NEXT%
) else if exist "!CURRENT_ARG!" (
    REM Assume argument is a file
    echo Processing file: "!CURRENT_ARG!"
    set "PROCESSED_ANY_PATH=1"
    call :process_single_file "!CURRENT_ARG!" %FORCE_NEXT%
) else (
    echo WARNING: Argument "!CURRENT_ARG!" is not a recognized flag, file, or directory. Skipping.
)

REM Reset flags for the *next* argument
set RECURSE_NEXT=0
set FORCE_NEXT=0
shift
goto :parse_args_loop

:parse_args_done
echo Argument parsing complete.

REM --- Check if any valid input path was processed ---
if "%PROCESSED_ANY_PATH%"=="0" (
    echo ERROR: No valid input files or folders were provided or found.
    echo Usage: Drag and drop video files onto this script or run from cmd:
    echo %~nx0 [options] [-no-where] [-r] [-f] "path\to\folder" "path\to\video1.mkv" ...
    goto :eof
)
REM --- Input processing is now handled in :parse_args_loop ---
set STOP_PROCESSING=0


REM =============================================
REM == Subroutine to process a single file ==
REM =============================================
:process_single_file
REM --- Check if input argument is empty ---
if "%~1"=="" (
    echo No more files to process in this batch.
    goto :eof
)
set "INPUT_FILE=%~1"
set "FORCE_PROCESSING=%2"
set "INPUT_PATH=%~dp1"
set "INPUT_NAME=%~n1"
set "INPUT_EXT=%~x1"

REM --- Construct Potential Output Path EARLY for check ---
set "OUTPUT_FILE_CHECK=%INPUT_PATH%%INPUT_NAME%%OUTPUT_SUFFIX%.%OUTPUT_FORMAT%"

REM --- Check if Output File Exists and if Force flag is NOT set ---
if exist "%OUTPUT_FILE_CHECK%" (
    if not "%FORCE_PROCESSING%"=="1" (
        echo Skipping "%INPUT_FILE%" because output "%OUTPUT_FILE_CHECK%" already exists. Use -f to force.
        goto :eof
    ) else (
        echo Forcing processing for "%INPUT_FILE%" despite existing output "%OUTPUT_FILE_CHECK%".
    )
)

echo.
echo -----------------------------------------------------
echo Processing: %INPUT_FILE%
echo -----------------------------------------------------

REM --- Input Format Check ---
set SUPPORTED=false
if /i "%INPUT_EXT%"==".mp4" set SUPPORTED=true
if /i "%INPUT_EXT%"==".avi" set SUPPORTED=true
if /i "%INPUT_EXT%"==".mkv" set SUPPORTED=true

if "%SUPPORTED%"=="false" (
    echo WARNING: Input format %INPUT_EXT% may not be fully supported. Skipping.
    goto :eof
)

REM --- Get Input Video Info (Pixel Format, Subtitles) ---
echo Probing file details with ffprobe...
set PIX_FMT=
set HAS_SUBTITLES=false

echo Probing pixel format for "%INPUT_FILE%"...
set "TEMP_FFPROBE_OUT=%TEMP%\ffprobe_pixfmt_%RANDOM%.txt"
"%FFPROBE_PATH%" -v error -select_streams v:0 -show_entries stream=pix_fmt -of csv=p=0 "%INPUT_FILE%" > "%TEMP_FFPROBE_OUT%"

set PIX_FMT=
if exist "%TEMP_FFPROBE_OUT%" (
    for /f "usebackq tokens=*" %%G in ("%TEMP_FFPROBE_OUT%") do (
        set "PIX_FMT=%%G"
    )
    del "%TEMP_FFPROBE_OUT%"
)

if not defined PIX_FMT (
    echo ERROR: ffprobe failed to determine pixel format for "%INPUT_FILE%". Check ffprobe command/output if run manually. Skipping.
    goto :eof
)
echo Detected Pixel Format: %PIX_FMT%

"%FFPROBE_PATH%" -v error -select_streams s -show_entries stream=index -of csv=p=0 "%INPUT_FILE%" | findstr . > nul
if errorlevel 0 (
    set HAS_SUBTITLES=true
    echo Detected Subtitle Stream^(s^).
) else (
    echo No Subtitle Stream^(s^) detected.
)

REM --- Subtitle Compatibility Check ---
if "%HAS_SUBTITLES%"=="true" if /i not "%OUTPUT_FORMAT%"=="mkv" (
    echo ERROR: Input file has subtitles, but output format is set to '%OUTPUT_FORMAT%'. MKV output format is required for subtitles. Skipping.
    goto :eof
)
REM --- HDR Check (Simple AV1 heuristic based on Go code comment) ---
if /i not "%VIDEO_CODEC%"=="libsvtav1" if /i not "%VIDEO_CODEC%"=="av1_nvenc" if /i not "%VIDEO_CODEC%"=="av1_amf" (
    REM Check if pix_fmt contains '10le' or '10be' or '12le' etc. (very basic HDR check)
    echo "%PIX_FMT%" | findstr /r /c:"10^[lb^]e" /c:"12^[lb^]e" /c:"p010" /c:"yuv420p10" > nul
    if errorlevel 0 (
       echo WARNING: Detected potential HDR pixel format ^(%PIX_FMT%^). Only AV1 encoders fully support HDR preservation in this script. Output might not be HDR.
    )
)


REM --- Construct Output Path ---
set "OUTPUT_FILE=%INPUT_PATH%%INPUT_NAME%%OUTPUT_SUFFIX%.%OUTPUT_FORMAT%"
echo Output file will be: %OUTPUT_FILE%

REM --- Construct FFMPEG Command ---

REM ** Escape the shader path for use within the filtergraph **
set "ESCAPED_SHADER_PATH=%SHADER_BASE_PATH%%SHADER_FILE%"
set "ESCAPED_SHADER_PATH=!ESCAPED_SHADER_PATH:\=\\!"
set "ESCAPED_SHADER_PATH=!ESCAPED_SHADER_PATH::=\:!"

REM Base options
set "FFMPEG_CMD="%FFMPEG_PATH%" -hide_banner -y"

REM Hardware acceleration (if selected)
if not "%HWACCEL_PARAMS%"=="" set "FFMPEG_CMD=!FFMPEG_CMD! %HWACCEL_PARAMS%"

REM Input file
set "FFMPEG_CMD=!FFMPEG_CMD! -i "%INPUT_FILE%""

REM Vulkan initialization and libplacebo filter using the ESCAPED path
REM Use single quotes around the escaped path value within libplacebo options
set "VF_STRING=format=%PIX_FMT%,hwupload,libplacebo=w=%TARGET_RESOLUTION_W%:h=%TARGET_RESOLUTION_H%:upscaler=bilinear:custom_shader_path='!ESCAPED_SHADER_PATH!',format=%PIX_FMT%"
set "FFMPEG_CMD=!FFMPEG_CMD! -init_hw_device vulkan -vf "%VF_STRING%""

REM Stream copying and mapping (Simplified: copy all audio, copy all subtitles if present)
set "FFMPEG_CMD=!FFMPEG_CMD! -map 0:v:0 -map 0:a? -map 0:s? -map 0:t?"
set "FFMPEG_CMD=!FFMPEG_CMD! -c:a copy -c:s copy -c:t copy"

REM CQP and Video Codec
set "FFMPEG_CMD=!FFMPEG_CMD! -c:v %VIDEO_CODEC% -qp %CQP%"

REM Preset (if applicable)
if not "%PRESET_PARAM%"=="" set "FFMPEG_CMD=!FFMPEG_CMD! %PRESET_PARAM%"

REM Threads (if applicable)
if not "%THREAD_PARAM%"=="" set "FFMPEG_CMD=!FFMPEG_CMD! %THREAD_PARAM%"

REM Output file
set "FFMPEG_CMD=!FFMPEG_CMD! "%OUTPUT_FILE%""

REM --- Execute FFMPEG ---
echo.
echo Starting ffmpeg command:
echo !FFMPEG_CMD!
echo.

call !FFMPEG_CMD!

if not errorlevel 0 (
    echo ERROR: ffmpeg process failed or was interrupted ^(Errorlevel: %ERRORLEVEL%^) while processing "!INPUT_FILE!".
    set "STOP_PROCESSING=1"
    goto :eof
)

echo Successfully processed "!INPUT_FILE!"

goto :eof


REM =============================================
REM == Subroutine to process a directory ==
REM =============================================
:process_directory
set "DIR_PATH=%~1"
set "IS_RECURSIVE=%2"
set "FORCE_PROCESSING_DIR=%3"

echo Searching for .mkv files in "%DIR_PATH%" (Recursive: %IS_RECURSIVE%)...

if "%IS_RECURSIVE%"=="1" (
    for /r "%DIR_PATH%" %%F in (*.mkv) do (
        REM Check if filename ends with the output suffix using delayed expansion (safer method)
        set "CURRENT_FILENAME=%%~nF"
        set "FILENAME_SUFFIX=!CURRENT_FILENAME:~-%OUTPUT_SUFFIX_LEN%!"

        set "SKIP_FILE=0"
        if /i "!FILENAME_SUFFIX!"=="!OUTPUT_SUFFIX!" set "SKIP_FILE=1"

        if "!SKIP_FILE!"=="1" (
            echo Skipping already processed file: "%%F"
        ) else (
            echo Found recursive: "%%F"
            call :process_single_file "%%F" %FORCE_PROCESSING_DIR%
            if "!STOP_PROCESSING!"=="1" goto :eof
        )
    )
) else (
    for %%F in ("%DIR_PATH%\*.mkv") do (
        REM Check if filename ends with the output suffix using delayed expansion (safer method)
        set "CURRENT_FILENAME=%%~nF"

        set SKIP_FILE=0
        if /i "!FILENAME_SUFFIX!"=="!OUTPUT_SUFFIX!" set "SKIP_FILE=1"

        if "!SKIP_FILE!"=="1" (
            echo Skipping already processed file: "%%F"
        ) else (
            echo Found: "%%F"
            call :process_single_file "%%F" %FORCE_PROCESSING_DIR%
            if "!STOP_PROCESSING!"=="1" goto :eof
        )
    )
)

goto :eof


:finished
echo.
echo All arguments processed.
endlocal

:eof
pause