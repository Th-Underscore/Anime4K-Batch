:: --- Anime4K-GUI Batch Transcoder ---
:: Replicates the core ffmpeg GLSL transcoding logic of the Anime4K-GUI project, as well as subtitle extraction and multi-track prioritization.
:: Append your desired options before the %* parameter.
::
:: --- Settings ---
:: glsl-transcode.bat options (place BEFORE file/folder paths):
::   -w <width>         : Target output width
::   -h <height>        : Target output height
::   -scale <factor>    : Scale factor multiplier (2 = double resolution i.e. 1080p -> 2160p, 0.5 = half resolution)
::   -shader <file>     : Shader filename
::   -shaderpath <path> : Path to shaders folder
::   -codec-prof <type> : Encoder profile (e.g., nvidia_h265, cpu_av1)
::   -preset <type>     : Encoder preset (e.g., slow, veryfast, p5, p7). Some profiles have different presets
::   -cqp <value>       : Constant Quantization Parameter (0-63, lower is better) (20 = virtually lossless, ~9 Mbps)
::   -crf <value>       : Constant Rate Factor (0-63, lower is better), overrides CQP
::   -pt <value>        : Preserve texture quality (0-5, higher is better) (3 = slowest and greatest file size)
::   -container <type>  : Output container format (avi, mkv, mp4)
::   -suffix <string>   : Suffix to append to output filenames
::   -faststart <value> : MP4 FastStart mode (0 = disabled, 1 = local temp, 2 = direct). Only applies to MP4 output
::   -sformat <string>  : Subtitle filename format for -extract-subs. Placeholders: SOURCE, lang, title, dispo
::   -slang <list>      : Comma-separated subtitle language priority for -sprioritize
::   -stitle <list>     : Comma-separated subtitle title priority for -sprioritize
::   -alang <list>      : Comma-separated audio language priority for -aprioritize. MUST be quoted if contains commas
::   -atitle <list>     : Comma-separated audio title priority for -aprioritize
::   -acodec <type>     : Audio codec for transcoding (e.g., aac, ac3, flac, libopus). If not specified, audio will be copied
::   -abitrate <value>  : Audio bitrate for EACH CHANNEL of each stream during transcoding (e.g., 192k = 382kbps for stereo). Only applies if AudioCodec is specified
::   -achannels <value> : Number of audio channels (e.g., 2 for stereo, 6 for 5.1). Only applies if -acodec is specified
::   -threads <value>   : Limit CPU threads for CPU encoders (0 = auto). Supports NUMA (e.g., 16:16 for 16 threads on each NUMA node)
:: glsl-transcode.bat flags (place BEFORE file/folder paths):
::   -r                 : Recursive search in folders
::   -f                 : Force overwrite existing output
::   -extract-subs      : Extract subtitles from the *input* file using extract-subs.bat
::   -sprioritize       : Set default subtitle track on the *output* file using set-subs-priority.bat
::   -aprioritize       : Set default audio track on the *output* file using set-audio-priority.bat
::   -delete            : Delete original file after successful transcode (USE WITH CAUTION! Mutually exclusive with "-replace")
::   -replace           : Replace original file after successful transcode (USE WITH CAUTION! Mutually exclusive with "-delete")
::
:: See the individual PowerShell scripts for advanced settings and information. You can also edit the code in any way you'd like!
::
:: --- Examples ---
:: Config:
::    - call "%~dp0\scripts\glsl-transcode.bat" -w 3840 -h 2160 -container mp4 -r %* ^
::    - call "%~dp0\scripts\glsl-transcode.bat" -w 1920 -h 1080 -r %* ^
::
:: --- More Examples ---
:: Upscale everything in a folder recursively to 4K using ModeA_A HQ shader in MPV's config, force overwrite, extract subs, and set default audio priority to Japanese -> Russian -> English:
::    - call "%~dp0\scripts\glsl-transcode.bat" -w 3840 -h 2160 -shaderpath "%appdata%\mpv\shaders" -shader Anime4K_ModeA_A.glsl -r -f -extract-subs -aprioritize -alang "jpn,rus,eng" -atitle "Commentary" %* ^
::
:: Upscale to 1080p, use a lower quality setting (higher CQP for smaller files), output as MP4, specify a custom shader folder (using default shader file), process folders recursively, extract subs, and set default audio (using default priority):
::    - call "%~dp0\scripts\glsl-transcode.bat" -w 1920 -h 1080 -cqp 32 -container mp4 -shaderpath "C:\MyCustomShaders" -r -sprioritize -slang "eng" -stitle "Full,Signs" -extract-subs -aprioritize %* ^
::
:: Upscale, extract subs without specifying language, and force overwrite:
::    - call "%~dp0\scripts\glsl-transcode.bat" -extract-subs -sformat "SOURCE.title" -f %* ^
::
:: Upscale to 4K with CQP 24 and set default audio to English:
::    - call "%~dp0\scripts\glsl-transcode.bat" -w 3840 -h 2160 -cqp 24 -aprioritize -alang "eng" -acodec aac %* ^
::
:: Use default settings from glsl-transcode.bat but process folders recursively and extract subs:
::    - call "%~dp0\scripts\glsl-transcode.bat" -r -extract-subs %* ^
::
:: Upscale recursively, extract subtitles, set default audio, and delete original files after successful transcode (USE WITH CAUTION!):
::    - call "%~dp0\scripts\glsl-transcode.bat" -r -extract-subs -aprioritize -delete %* ^
::
:: Prioritize Japanese audio with "Commentary" in the title, and English "Full" subtitles, then extract them:
::    - call "%~dp0\scripts\glsl-transcode.bat" -aprioritize -alang "jpn" -atitle "Commentary" -sprioritize -slang "eng" -stitle "Full" -extract-subs %* ^
::
:: Transcode audio to AAC with a bitrate of 192k and 2 channels, while upscaling to 4K:
::    - call "%~dp0\scripts\glsl-transcode.bat" -w 3840 -h 2160 -acodec aac -abitrate 192k -achannels 2 %* ^
::
:: Set encoder profile to AMD AV1 with a custom preset, output to MKV with a custom suffix:
::    - call "%~dp0\scripts\glsl-transcode.bat" -codec-prof amd_av1 -preset quality -suffix "_remux" -container mkv %* ^
::
:: Double the input resolution using scale factor, use CRF instead of CQP:
::    - call "%~dp0\scripts\glsl-transcode.bat" -scale 2.0 -crf 26 %* ^
::
:: Upscale to 4K, use a custom encoder preset, preserve texture at maximum quality, enable MP4 FastStart for streaming:
::    - call "%~dp0\scripts\glsl-transcode.bat" -w 3840 -h 2160 -preset slow -pt 5 -container mp4 -faststart 1 %* ^
::
:: Upscale recursively with verbose output and limit CPU threads (useful for CPU encoding):
::    - call "%~dp0\scripts\glsl-transcode.bat" -r -codec-prof cpu_h265 -threads 8 -v %* ^
::
:: Upscale and replace the original file in-place (USE WITH CAUTION!):
::    - call "%~dp0\scripts\glsl-transcode.bat" -replace %* ^
:: --- Usage ---
:: CLI (check the README for better usage recommendations):
::    - C:\path\to\Anime4K-Batch.bat "C:\path\to\folder" "C:\path\to\file1" "C:\path\to\file2" ...
::    - C:\path\to\Anime4K-Batch.bat "%userprofile%\Anime\Season 1" "%userprofile%\Anime\Movie.mkv"
:: or - C:\path\to\Anime4K-Batch.bat -r "%userprofile%\Anime"
::
:: When using PowerShell, you may need to escape double quotes for files with special characters:
::    - & C:\path\to\Anime4K-Batch.bat "`"C:\path\to\1(!)test!&@##FILE&$#@@+++===}{'';;-[Copy]_upscaled.eng.test.mkv`""
:: Note that the above example includes literal single quotes in the filename, which would have to be escaped if using a single-quote string.

:: This is the default command. It will only transcode using the settings in config.json.
:: Append your desired flags and options before the %* ^ characters.
:: Include the -extract-subs flag to also extract subtitles from the input file (recommended for transcoding to mp4).
:: MAKE SURE THERE IS NO SPACE BETWEEN THE ^ AND THE NEXT LINE! A SINGLE SPACE WILL BREAK THE SCRIPT! The indentation afterwards is acceptable.
call "%~dp0\scripts\glsl-transcode.bat" %* ^
    -config "%~dp0\config.json"

pause
