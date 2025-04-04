:: --- Anime4K-GUI Batch Transcoder ---
:: Replicates the core ffmpeg GLSL transcoding logic of the Anime4K-GUI project, as well as subtitle extraction.
:: Append your desired options before the %* parameter.
::
:: --- Settings ---
:: glsl-transcode.bat options (place BEFORE file/folder paths):
::   -w <width>         : Target output width (default: %TARGET_RESOLUTION_W%)
::   -h <height>        : Target output height (default: %TARGET_RESOLUTION_H%)
::   -shader <file>     : Shader filename (default: %SHADER_FILE%)
::   -shaderpath <path> : Path to shaders folder (default: %SHADER_BASE_PATH%)
::   -codec-prof <type> : Encoder profile (e.g., nvidia_h265, cpu_av1; default: %ENCODER_PROFILE%)
::   -cqp <value>       : Constant Quantization Parameter (0-51, lower is better; default: %CQP%) (24 is virtually lossless for double the file size)
::   -container <type>  : Output container format (avi, mkv, mp4; default: %OUTPUT_FORMAT%)
:: glsl-transcode.bat flags (place BEFORE file/folder paths):
::   -r                 : Recursive search in folders
::   -f                 : Force overwrite existing output files
::   -delete            : Delete original file after successful transcode (USE WITH CAUTION! You can just delete the original files yourself, grouping by "Type" and sorting by "Date modified")
::   -no-where          : Disable auto-detection of ffmpeg/ffprobe via 'where' command (binaries in the same folder as this script will be used regardless)
:: 
:: extract-subs.bat options (place BEFORE file/folder paths):
::   -format <string>   : Output filename format (FILE, lang, title; default: %OUTPUT_FILENAME_FORMAT% = "FILE.lang.title" for Jellyfin compatibility)
:: extract-subs.bat flags (place BEFORE file/folder paths):
::   -r                 : Recursive search in folders
::   -f                 : Force overwrite existing subtitle files
::   -no-where          : Disable auto-detection of ffmpeg/ffprobe via 'where' command (binaries in the same folder as this script will be used regardless)
::
:: See the individual scripts for advanced settings and information. You can also edit the code in any way you'd like!
::
:: --- Examples ---
:: Config:
::    - %~dp0\extract-subs.bat -r %*   &&   %~dp0\glsl-transcode.bat -w 3840 -h 2160 -container mp4 -r %*
::    - %~dp0\glsl-transcode.bat -w 1920 -h 1080 -r %*
::
:: --- More Examples ---
:: Upscale everything in a folder recursively to 4K using ModeA_A HQ shader in MPV's config, force overwrite, and extract subs:
::    - %~dp0\extract-subs.bat -r -f %*   &&   %~dp0\glsl-transcode.bat -w 3840 -h 2160 -shaderpath "%appdata%\mpv\shaders" -shader Anime4K_ModeA_A.glsl -r -f %*
::
:: Upscale to 1080p, use a lower quality setting (higher CQP for smaller files), output as MP4, and specify a custom shader folder:
::    - %~dp0\extract-subs.bat -r %*   &&   %~dp0\glsl-transcode.bat -w 1920 -h 1080 -cqp 28 -container mp4 -shaderpath "C:\MyCustomShaders" -r %*
::
:: Only extract subtitles recursively, forcing overwrite of existing .ass/.srt files:
::    - %~dp0\extract-subs.bat -r -f %*
::
:: Upscale a specific file to 4K with CQP 24, assuming ffmpeg/ffprobe are in PATH (disable 'where' check):
::    - %~dp0\extract-subs.bat -no-where %*   &&   %~dp0\glsl-transcode.bat -w 3840 -h 2160 -cqp 24 -no-where %*
::
:: Use default settings from glsl-transcode.bat/extract-subs.bat but process folders recursively:
::    - %~dp0\extract-subs.bat -r %*   &&   %~dp0\glsl-transcode.bat -r %*
::
:: Extract subtitles before upscaling recursively, deleting original files after successful transcode (USE WITH CAUTION!)
::    - %~dp0\extract-subs.bat %*   &&   %~dp0\glsl-transcode.bat -r -delete %*
::
:: --- Usage ---
:: CLI (check the README for better usage recommendations):
::    - C:\path\to\Anime4K-Batch.bat "C:\path\to\folder" "C:\path\to\file1" "C:\path\to\file2" ...
::    - C:\path\to\Anime4K-Batch.bat "%userprofile%\Anime\Season 1" "%userprofile%\Anime\Movie.mkv"
:: or - C:\path\to\Anime4K-Batch.bat -r "%userprofile%\Anime"

:: Append your desired flags and options before the %* parameter.
:: Comment this line (put "::" at the start), or delete it, if you wish to also extract subtitles (best for transcoding MKV to MP4).
%~dp0\glsl-transcode.bat %*

:: Uncomment the line below (omit "::") to enable subtitle extraction. This will extract subtitles from the input files and save them in the same folder as the output files, defaulting to Jellyfin's naming convention.
:: Common flags (i.e., -r -f -no-where) don't need to be shared between both scripts, but I would recommend it.
::%~dp0\extract-subs.bat -r %*   &&   %~dp0\glsl-transcode.bat %*
