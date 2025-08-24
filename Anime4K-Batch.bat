:: --- Anime4K-GUI Batch Transcoder ---
:: Replicates the core ffmpeg GLSL transcoding logic of the Anime4K-GUI project, as well as subtitle extraction.
:: Append your desired options before the %* parameter.
::
:: --- Settings ---
:: glsl-transcode.bat options (place BEFORE file/folder paths):
::   -w <width>         : Target output width
::   -h <height>        : Target output height
::   -shader <file>     : Shader filename
::   -shaderpath <path> : Path to shaders folder
::   -codec-prof <type> : Encoder profile (e.g., nvidia_h265, cpu_av1)
::   -cqp <value>       : Constant Quantization Parameter (0-51, lower is better) (24 is virtually lossless for double the file size)
::   -container <type>  : Output container format (avi, mkv, mp4)
::   -suffix <string>   : Suffix to append to output filenames
::   -slang <list>      : Comma-separated subtitle language priority for -sprioritize.
::   -stitle <list>     : Comma-separated subtitle title priority for -sprioritize.
::   -sformat <string>  : Subtitle filename format for -extract-subs. Placeholders: SOURCE, lang, title, dispo.
::   -alang <list>      : Comma-separated audio language priority for -aprioritize. MUST be quoted if contains commas.
::   -atitle <list>     : Comma-separated audio title priority for -aprioritize.
::   -acodec <type>     : Audio codec for transcoding (e.g., aac, ac3, flac). If not specified, audio will be copied.
::   -abitrate <value>  : Audio bitrate for transcoding (e.g., 192k, 256k). Only applies if -acodec is specified.
::   -achannels <value> : Number of audio channels (e.g., 2 for stereo, 6 for 5.1). Only applies if -acodec is specified.
:: glsl-transcode.bat flags (place BEFORE file/folder paths):
::   -r                 : Recursive search in folders
::   -f                 : Force overwrite existing output
::   -extract-subs      : Extract subtitles from the *input* file using extract-subs.bat
::   -sprioritize       : Set default subtitle track on the *input* file using set-subs-priority.bat
::   -aprioritize       : Set default audio track on the *output* file using set-audio-priority.bat
::   -delete            : Delete original file after successful transcode (USE WITH CAUTION! You can just delete the original files yourself, grouping by "Type" and sorting by "Date modified")
::   -replace           : Replace original file with processed version (USE WITH CAUTION!)
::
:: See the individual scripts for advanced settings and information. You can also edit the code in any way you'd like!
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
:: Append your desired flags and options before the %* ^ character.
:: Include the -extract-subs flag to also extract subtitles from the input file (recommended for transcoding to mp4).
:: MAKE SURE THERE IS NO SPACE BETWEEN THE ^ AND THE NEXT LINE! A SINGLE SPACE WILL BREAK THE SCRIPT! The indentation afterwards is acceptable.
call "%~dp0\scripts\glsl-transcode.bat" %* ^
    -config "%~dp0\config.json"

pause
