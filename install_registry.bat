@echo off
setlocal

if not "%~1"=="am_admin" (
    call sudo "%~0" am_admin & goto :complete
    :complete
    if %ERRORLEVEL% neq 0 ( powershell -Command "Start-Process -Verb RunAs -FilePath '%0' -ArgumentList 'am_admin'" )
    exit /b
)

REM Get base directory, removing the trailing backslash
set "BASE_DIR=%~dp0"
if "%BASE_DIR:~-1%"=="\" set "BASE_DIR=%BASE_DIR:~0,-1%"

REM Define root paths
set "ROOT_STORE=HKLM\Software\Microsoft\Windows\CurrentVersion\Explorer\CommandStore\Shell"
set "ROOT_CLASS=HKCU\Software\Classes"

echo Adding registry entries for file context menus (HKLM)...

REM --- Main GLSL Transcode Script ---
REM Ani4K.Transcode (File)
REG ADD "%ROOT_STORE%\Ani4K.Transcode\command" /ve /d "\"%BASE_DIR%\Anime4K-Batch.bat\" \"%%1\"" /f
REG ADD "%ROOT_STORE%\Ani4K.Transcode" /v MUIVerb /t REG_SZ /d "Apply GLSL shaders" /f
REG ADD "%ROOT_STORE%\Ani4K.Transcode" /v Icon /t REG_SZ /d "%BASE_DIR%\assets\icons\Transcode_32.ico" /f

REM --- Aux Scripts ---
REG ADD "%ROOT_STORE%\Ani4K.Transcode" /v CommandFlags /t REG_DWORD /d 0x040 /f

REM Ani4K.Extract (File)
REG ADD "%ROOT_STORE%\Ani4K.Extract\command" /ve /d "\"%BASE_DIR%\scripts\extract-subs.bat\" -r \"%%1\" & pause" /f
REG ADD "%ROOT_STORE%\Ani4K.Extract" /v MUIVerb /t REG_SZ /d "Extract subtitles" /f
REG ADD "%ROOT_STORE%\Ani4K.Extract" /v Icon /t REG_SZ /d "%BASE_DIR%\assets\icons\Extract_32.ico" /f

REM Ani4K.Remux (File)
REG ADD "%ROOT_STORE%\Ani4K.Remux\command" /ve /d "\"%BASE_DIR%\scripts\remux.bat\" -r \"%%1\" & pause" /f
REG ADD "%ROOT_STORE%\Ani4K.Remux" /v MUIVerb /t REG_SZ /d "Remux" /f
REG ADD "%ROOT_STORE%\Ani4K.Remux" /v Icon /t REG_SZ /d "%BASE_DIR%\assets\icons\Remux_32.ico" /f

REM Ani4K.SetAudioPriority (File)
REG ADD "%ROOT_STORE%\Ani4K.SetAudioPriority\command" /ve /d "\"%BASE_DIR%\scripts\set-audio-priority.bat\" -replace \"%%1\" & pause" /f
REG ADD "%ROOT_STORE%\Ani4K.SetAudioPriority" /v MUIVerb /t REG_SZ /d "Set audio priority" /f
REG ADD "%ROOT_STORE%\Ani4K.SetAudioPriority" /v Icon /t REG_SZ /d "%SystemRoot%\System32\imageres.dll,62" /f

REM Ani4K.TranscodeAudio (File)
REG ADD "%ROOT_STORE%\Ani4K.TranscodeAudio\command" /ve /d "\"%BASE_DIR%\scripts\transcode-audio.bat\" \"%%1\" & pause" /f
REG ADD "%ROOT_STORE%\Ani4K.TranscodeAudio" /v MUIVerb /t REG_SZ /d "Transcode audio" /f
REG ADD "%ROOT_STORE%\Ani4K.TranscodeAudio" /v Icon /t REG_SZ /d "%SystemRoot%\System32\imageres.dll,80" /f

REM Ani4K.SetSubsPriority (File)
REG ADD "%ROOT_STORE%\Ani4K.SetSubsPriority\command" /ve /d "\"%BASE_DIR%\scripts\set-subs-priority.bat\" -replace \"%%1\" & pause" /f
REG ADD "%ROOT_STORE%\Ani4K.SetSubsPriority" /v MUIVerb /t REG_SZ /d "Set subtitle priority" /f
REG ADD "%ROOT_STORE%\Ani4K.SetSubsPriority" /v Icon /t REG_SZ /d "%SystemRoot%\System32\imageres.dll,62" /f

REM --- Utils ---
REG ADD "%ROOT_STORE%\Ani4K.SetSubsPriority" /v CommandFlags /t REG_DWORD /d 0x040 /f

REM Ani4K.RenameFiles (File)
REG ADD "%ROOT_STORE%\Ani4K.RenameFiles\command" /ve /d "\"%BASE_DIR%\scripts\utils\exec_pwsh.cmd\" \"%BASE_DIR%\scripts\utils\Rename-MediaFiles.ps1\" -Path \"'%%1'\" & pause" /f
REG ADD "%ROOT_STORE%\Ani4K.RenameFiles" /v MUIVerb /t REG_SZ /d "Rename episodes to SxxExx" /f
REG ADD "%ROOT_STORE%\Ani4K.RenameFiles" /v Icon /t REG_SZ /d "%SystemRoot%\System32\imageres.dll,89" /f

echo Adding registry entries for Anime4K-Batch file context menus with prompt (HKLM)...

REM --- Prompt commands ---
REM Delete existing prompt entries first (ignore errors if they don't exist)
REG DELETE "%ROOT_STORE%\Ani4K.Transcode_Prompt" /f > nul 2>&1
REG DELETE "%ROOT_STORE%\Ani4K.Extract_Prompt" /f > nul 2>&1
REG DELETE "%ROOT_STORE%\Ani4K.Remux_Prompt" /f > nul 2>&1
REG DELETE "%ROOT_STORE%\Ani4K.SetAudioPriority_Prompt" /f > nul 2>&1
REG DELETE "%ROOT_STORE%\Ani4K.TranscodeAudio_Prompt" /f > nul 2>&1
REG DELETE "%ROOT_STORE%\Ani4K.SetSubsPriority_Prompt" /f > nul 2>&1
REG DELETE "%ROOT_STORE%\Ani4K.RenameFiles_Prompt" /f > nul 2>&1

REM Copy file entries to create prompt entries
REG COPY "%ROOT_STORE%\Ani4K.Transcode" "%ROOT_STORE%\Ani4K.Transcode_Prompt" /s /f
REG COPY "%ROOT_STORE%\Ani4K.Extract" "%ROOT_STORE%\Ani4K.Extract_Prompt" /s /f
REG COPY "%ROOT_STORE%\Ani4K.Remux" "%ROOT_STORE%\Ani4K.Remux_Prompt" /s /f
REG COPY "%ROOT_STORE%\Ani4K.SetAudioPriority" "%ROOT_STORE%\Ani4K.SetAudioPriority_Prompt" /s /f
REG COPY "%ROOT_STORE%\Ani4K.TranscodeAudio" "%ROOT_STORE%\Ani4K.TranscodeAudio_Prompt" /s /f
REG COPY "%ROOT_STORE%\Ani4K.SetSubsPriority" "%ROOT_STORE%\Ani4K.SetSubsPriority_Prompt" /s /f
REG COPY "%ROOT_STORE%\Ani4K.RenameFiles" "%ROOT_STORE%\Ani4K.RenameFiles_Prompt" /s /f

REM Update commands for prompt entries
REG ADD "%ROOT_STORE%\Ani4K.Transcode_Prompt\command" /ve /d "\"%BASE_DIR%\scripts\utils\prompt.cmd\" \"%BASE_DIR%\Anime4K-Batch.bat\" \"%%1\"" /f
REG ADD "%ROOT_STORE%\Ani4K.Extract_Prompt\command" /ve /d "\"%BASE_DIR%\scripts\utils\prompt.cmd\" \"%BASE_DIR%\scripts\extract-subs.bat\" -r \"%%1\" & pause" /f
REG ADD "%ROOT_STORE%\Ani4K.Remux_Prompt\command" /ve /d "\"%BASE_DIR%\scripts\utils\prompt.cmd\" \"%BASE_DIR%\scripts\remux.bat\" -r \"%%1\" & pause" /f
REG ADD "%ROOT_STORE%\Ani4K.SetAudioPriority_Prompt\command" /ve /d "\"%BASE_DIR%\scripts\utils\prompt.cmd\" \"%BASE_DIR%\scripts\set-audio-priority.bat\" -replace \"%%1\" & pause" /f
REG ADD "%ROOT_STORE%\Ani4K.TranscodeAudio_Prompt\command" /ve /d "\"%BASE_DIR%\scripts\utils\prompt.cmd\" \"%BASE_DIR%\scripts\transcode-audio.bat\" \"%%1\" & pause" /f
REG ADD "%ROOT_STORE%\Ani4K.SetSubsPriority_Prompt\command" /ve /d "\"%BASE_DIR%\scripts\utils\prompt.cmd\" \"%BASE_DIR%\scripts\set-subs-priority.bat\" -replace \"%%1\" & pause" /f
REG ADD "%ROOT_STORE%\Ani4K.RenameFiles_Prompt\command" /ve /d "\"%BASE_DIR%\scripts\utils\prompt.cmd\" \"%BASE_DIR%\scripts\utils\exec_pwsh.cmd\" \"%BASE_DIR%\scripts\utils\Rename-MediaFiles.ps1\" -Path \"'%%1'\" & pause" /f

echo Adding registry entries for Anime4K-Batch directory context menus (HKLM)...

REM --- Directory context menus ---
REM Delete existing directory entries first (ignore errors if keys don't exist)
REG DELETE "%ROOT_STORE%\Ani4K.TranscodeDir" /f > nul 2>&1
REG DELETE "%ROOT_STORE%\Ani4K.ExtractDir" /f > nul 2>&1
REG DELETE "%ROOT_STORE%\Ani4K.RemuxDir" /f > nul 2>&1
REG DELETE "%ROOT_STORE%\Ani4K.SetAudioPriorityDir" /f > nul 2>&1
REG DELETE "%ROOT_STORE%\Ani4K.TranscodeAudioDir" /f > nul 2>&1
REG DELETE "%ROOT_STORE%\Ani4K.SetSubsPriorityDir" /f > nul 2>&1
REG DELETE "%ROOT_STORE%\Ani4K.RenameFilesDir" /f > nul 2>&1
REG DELETE "%ROOT_STORE%\Ani4K.TranscodeDir_Prompt" /f > nul 2>&1
REG DELETE "%ROOT_STORE%\Ani4K.ExtractDir_Prompt" /f > nul 2>&1
REG DELETE "%ROOT_STORE%\Ani4K.RemuxDir_Prompt" /f > nul 2>&1
REG DELETE "%ROOT_STORE%\Ani4K.SetAudioPriorityDir_Prompt" /f > nul 2>&1
REG DELETE "%ROOT_STORE%\Ani4K.TranscodeAudioDir_Prompt" /f > nul 2>&1
REG DELETE "%ROOT_STORE%\Ani4K.SetSubsPriorityDir_Prompt" /f > nul 2>&1
REG DELETE "%ROOT_STORE%\Ani4K.RenameFilesDir_Prompt" /f > nul 2>&1

REM Copy file entries to create directory entries
REG COPY "%ROOT_STORE%\Ani4K.Transcode" "%ROOT_STORE%\Ani4K.TranscodeDir" /s /f
REG COPY "%ROOT_STORE%\Ani4K.Extract" "%ROOT_STORE%\Ani4K.ExtractDir" /s /f
REG COPY "%ROOT_STORE%\Ani4K.Remux" "%ROOT_STORE%\Ani4K.RemuxDir" /s /f
REG COPY "%ROOT_STORE%\Ani4K.SetAudioPriority" "%ROOT_STORE%\Ani4K.SetAudioPriorityDir" /s /f
REG COPY "%ROOT_STORE%\Ani4K.TranscodeAudio" "%ROOT_STORE%\Ani4K.TranscodeAudioDir" /s /f
REG COPY "%ROOT_STORE%\Ani4K.SetSubsPriority" "%ROOT_STORE%\Ani4K.SetSubsPriorityDir" /s /f
REG COPY "%ROOT_STORE%\Ani4K.RenameFiles" "%ROOT_STORE%\Ani4K.RenameFilesDir" /s /f
REG COPY "%ROOT_STORE%\Ani4K.Transcode_Prompt" "%ROOT_STORE%\Ani4K.TranscodeDir_Prompt" /s /f
REG COPY "%ROOT_STORE%\Ani4K.Extract_Prompt" "%ROOT_STORE%\Ani4K.ExtractDir_Prompt" /s /f
REG COPY "%ROOT_STORE%\Ani4K.Remux_Prompt" "%ROOT_STORE%\Ani4K.RemuxDir_Prompt" /s /f
REG COPY "%ROOT_STORE%\Ani4K.SetAudioPriority_Prompt" "%ROOT_STORE%\Ani4K.SetAudioPriorityDir_Prompt" /s /f
REG COPY "%ROOT_STORE%\Ani4K.TranscodeAudio_Prompt" "%ROOT_STORE%\Ani4K.TranscodeAudioDir_Prompt" /s /f
REG COPY "%ROOT_STORE%\Ani4K.SetSubsPriority_Prompt" "%ROOT_STORE%\Ani4K.SetSubsPriorityDir_Prompt" /s /f
REG COPY "%ROOT_STORE%\Ani4K.RenameFiles_Prompt" "%ROOT_STORE%\Ani4K.RenameFilesDir_Prompt" /s /f

REM Update icons for directory entries
REG ADD "%ROOT_STORE%\Ani4K.TranscodeDir" /v Icon /t REG_SZ /d "%BASE_DIR%\assets\icons\TranscodeDir_32.ico" /f
REG ADD "%ROOT_STORE%\Ani4K.ExtractDir" /v Icon /t REG_SZ /d "%BASE_DIR%\assets\icons\ExtractDir_32.ico" /f
REG ADD "%ROOT_STORE%\Ani4K.RemuxDir" /v Icon /t REG_SZ /d "%BASE_DIR%\assets\icons\RemuxDir_32.ico" /f
REG ADD "%ROOT_STORE%\Ani4K.SetAudioPriorityDir" /v Icon /t REG_SZ /d "%SystemRoot%\System32\imageres.dll,62" /f
REG ADD "%ROOT_STORE%\Ani4K.TranscodeAudioDir" /v Icon /t REG_SZ /d "%SystemRoot%\System32\imageres.dll,80" /f
REG ADD "%ROOT_STORE%\Ani4K.SetSubsPriorityDir" /v Icon /t REG_SZ /d "%SystemRoot%\System32\imageres.dll,62" /f
REG ADD "%ROOT_STORE%\Ani4K.RenameFilesDir" /v Icon /t REG_SZ /d "%SystemRoot%\System32\imageres.dll,89" /f
REG ADD "%ROOT_STORE%\Ani4K.TranscodeDir_Prompt" /v Icon /t REG_SZ /d "%BASE_DIR%\assets\icons\TranscodeDir_32.ico" /f
REG ADD "%ROOT_STORE%\Ani4K.ExtractDir_Prompt" /v Icon /t REG_SZ /d "%BASE_DIR%\assets\icons\ExtractDir_32.ico" /f
REG ADD "%ROOT_STORE%\Ani4K.RemuxDir_Prompt" /v Icon /t REG_SZ /d "%BASE_DIR%\assets\icons\RemuxDir_32.ico" /f
REG ADD "%ROOT_STORE%\Ani4K.SetAudioPriorityDir_Prompt" /v Icon /t REG_SZ /d "%SystemRoot%\System32\imageres.dll,62" /f
REG ADD "%ROOT_STORE%\Ani4K.TranscodeAudioDir_Prompt" /v Icon /t REG_SZ /d "%SystemRoot%\System32\imageres.dll,80" /f
REG ADD "%ROOT_STORE%\Ani4K.SetSubsPriorityDir_Prompt" /v Icon /t REG_SZ /d "%SystemRoot%\System32\imageres.dll,62" /f
REG ADD "%ROOT_STORE%\Ani4K.RenameFilesDir_Prompt" /v Icon /t REG_SZ /d "%SystemRoot%\System32\imageres.dll,89" /f

echo Adding registry entries for Anime4K-Batch background context menus (HKLM)...

REM --- Background context menus ---
REM Delete existing background entries first (ignore errors if keys don't exist)
REG DELETE "%ROOT_STORE%\Ani4K.TranscodeBg" /f > nul 2>&1
REG DELETE "%ROOT_STORE%\Ani4K.ExtractBg" /f > nul 2>&1
REG DELETE "%ROOT_STORE%\Ani4K.RemuxBg" /f > nul 2>&1
REG DELETE "%ROOT_STORE%\Ani4K.SetAudioPriorityBg" /f > nul 2>&1
REG DELETE "%ROOT_STORE%\Ani4K.TranscodeAudioBg" /f > nul 2>&1
REG DELETE "%ROOT_STORE%\Ani4K.SetSubsPriorityBg" /f > nul 2>&1
REG DELETE "%ROOT_STORE%\Ani4K.RenameFilesBg" /f > nul 2>&1
REG DELETE "%ROOT_STORE%\Ani4K.TranscodeBg_Prompt" /f > nul 2>&1
REG DELETE "%ROOT_STORE%\Ani4K.ExtractBg_Prompt" /f > nul 2>&1
REG DELETE "%ROOT_STORE%\Ani4K.RemuxBg_Prompt" /f > nul 2>&1
REG DELETE "%ROOT_STORE%\Ani4K.SetAudioPriorityBg_Prompt" /f > nul 2>&1
REG DELETE "%ROOT_STORE%\Ani4K.TranscodeAudioBg_Prompt" /f > nul 2>&1
REG DELETE "%ROOT_STORE%\Ani4K.SetSubsPriorityBg_Prompt" /f > nul 2>&1
REG DELETE "%ROOT_STORE%\Ani4K.RenameFilesBg_Prompt" /f > nul 2>&1

REM Copy file entries to create background entries
REG COPY "%ROOT_STORE%\Ani4K.TranscodeDir" "%ROOT_STORE%\Ani4K.TranscodeBg" /s /f
REG COPY "%ROOT_STORE%\Ani4K.ExtractDir" "%ROOT_STORE%\Ani4K.ExtractBg" /s /f
REG COPY "%ROOT_STORE%\Ani4K.RemuxDir" "%ROOT_STORE%\Ani4K.RemuxBg" /s /f
REG COPY "%ROOT_STORE%\Ani4K.SetAudioPriorityDir" "%ROOT_STORE%\Ani4K.SetAudioPriorityBg" /s /f
REG COPY "%ROOT_STORE%\Ani4K.TranscodeAudioDir" "%ROOT_STORE%\Ani4K.TranscodeAudioBg" /s /f
REG COPY "%ROOT_STORE%\Ani4K.SetSubsPriorityDir" "%ROOT_STORE%\Ani4K.SetSubsPriorityBg" /s /f
REG COPY "%ROOT_STORE%\Ani4K.RenameFilesDir" "%ROOT_STORE%\Ani4K.RenameFilesBg" /s /f
REG COPY "%ROOT_STORE%\Ani4K.TranscodeDir_Prompt" "%ROOT_STORE%\Ani4K.TranscodeBg_Prompt" /s /f
REG COPY "%ROOT_STORE%\Ani4K.ExtractDir_Prompt" "%ROOT_STORE%\Ani4K.ExtractBg_Prompt" /s /f
REG COPY "%ROOT_STORE%\Ani4K.RemuxDir_Prompt" "%ROOT_STORE%\Ani4K.RemuxBg_Prompt" /s /f
REG COPY "%ROOT_STORE%\Ani4K.SetAudioPriorityDir_Prompt" "%ROOT_STORE%\Ani4K.SetAudioPriorityBg_Prompt" /s /f
REG COPY "%ROOT_STORE%\Ani4K.TranscodeAudioDir_Prompt" "%ROOT_STORE%\Ani4K.TranscodeAudioBg_Prompt" /s /f
REG COPY "%ROOT_STORE%\Ani4K.SetSubsPriorityDir_Prompt" "%ROOT_STORE%\Ani4K.SetSubsPriorityBg_Prompt" /s /f
REG COPY "%ROOT_STORE%\Ani4K.RenameFilesDir_Prompt" "%ROOT_STORE%\Ani4K.RenameFilesBg_Prompt" /s /f

REM Update commands for background entries
REG ADD "%ROOT_STORE%\Ani4K.TranscodeBg\command" /ve /d "\"%BASE_DIR%\Anime4K-Batch.bat\" \"%%V\" & pause" /f
REG ADD "%ROOT_STORE%\Ani4K.ExtractBg\command" /ve /d "\"%BASE_DIR%\scripts\extract-subs.bat\" -r \"%%V\" & pause" /f
REG ADD "%ROOT_STORE%\Ani4K.RemuxBg\command" /ve /d "\"%BASE_DIR%\scripts\remux.bat\" -r \"%%V\" & pause" /f
REG ADD "%ROOT_STORE%\Ani4K.SetAudioPriorityBg\command" /ve /d "\"%BASE_DIR%\scripts\set-audio-priority.bat\" -replace \"%%V\" & pause" /f
REG ADD "%ROOT_STORE%\Ani4K.TranscodeAudioBg\command" /ve /d "\"%BASE_DIR%\scripts\transcode-audio.bat\" \"%%V\" & pause" /f
REG ADD "%ROOT_STORE%\Ani4K.SetSubsPriorityBg\command" /ve /d "\"%BASE_DIR%\scripts\set-subs-priority.bat\" -replace \"%%V\" & pause" /f
REG ADD "%ROOT_STORE%\Ani4K.RenameFilesBg\command" /ve /d "\"%BASE_DIR%\scripts\utils\exec_pwsh.cmd\" \"%BASE_DIR%\scripts\utils\Rename-MediaFiles.ps1\" -Path \"'%%V'\" & pause" /f
REG ADD "%ROOT_STORE%\Ani4K.TranscodeBg_Prompt\command" /ve /d "\"%BASE_DIR%\scripts\utils\prompt.cmd\" \"%BASE_DIR%\Anime4K-Batch.bat\" \"%%V\" & pause" /f
REG ADD "%ROOT_STORE%\Ani4K.ExtractBg_Prompt\command" /ve /d "\"%BASE_DIR%\scripts\utils\prompt.cmd\" \"%BASE_DIR%\scripts\extract-subs.bat\" -r \"%%V\" & pause" /f
REG ADD "%ROOT_STORE%\Ani4K.RemuxBg_Prompt\command" /ve /d "\"%BASE_DIR%\scripts\utils\prompt.cmd\" \"%BASE_DIR%\scripts\remux.bat\" -r \"%%V\" & pause" /f
REG ADD "%ROOT_STORE%\Ani4K.SetAudioPriorityBg_Prompt\command" /ve /d "\"%BASE_DIR%\scripts\utils\prompt.cmd\" \"%BASE_DIR%\scripts\set-audio-priority.bat\" -replace \"%%V\" & pause" /f
REG ADD "%ROOT_STORE%\Ani4K.TranscodeAudioBg_Prompt\command" /ve /d "\"%BASE_DIR%\scripts\utils\prompt.cmd\" \"%BASE_DIR%\scripts\transcode-audio.bat\" \"%%V\" & pause" /f
REG ADD "%ROOT_STORE%\Ani4K.SetSubsPriorityBg_Prompt\command" /ve /d "\"%BASE_DIR%\scripts\utils\prompt.cmd\" \"%BASE_DIR%\scripts\set-subs-priority.bat\" -replace \"%%V\" & pause" /f
REG ADD "%ROOT_STORE%\Ani4K.RenameFilesBg_Prompt\command" /ve /d "\"%BASE_DIR%\scripts\utils\prompt.cmd\" \"%BASE_DIR%\scripts\utils\exec_pwsh.cmd\" \"%BASE_DIR%\scripts\utils\Rename-MediaFiles.ps1\" -Path \"'%%V'\" & pause" /f

echo Adding main context menu entries (HKCU)...

REM Main entry for Files (*)
REG ADD "%ROOT_CLASS%\*\shell\Anime4K-Batch" /v MUIVerb /t REG_SZ /d "Anime4K-Batch" /f
REG ADD "%ROOT_CLASS%\*\shell\Anime4K-Batch" /v SubCommands /t REG_SZ /d "Ani4K.Transcode;Ani4K.Extract;Ani4K.Remux;Ani4K.TranscodeAudio;Ani4K.SetAudioPriority;Ani4K.SetSubsPriority;Ani4K.RenameFiles" /f
REG ADD "%ROOT_CLASS%\*\shell\Anime4K-Batch" /v Icon /t REG_SZ /d "%SystemRoot%\System32\imageres.dll,263" /f

REM Main entry for Files (Prompt) (*)
REG ADD "%ROOT_CLASS%\*\shell\Anime4K-Batch_Prompt" /v MUIVerb /t REG_SZ /d "Anime4K-Batch (Prompt)" /f
REG ADD "%ROOT_CLASS%\*\shell\Anime4K-Batch_Prompt" /v SubCommands /t REG_SZ /d "Ani4K.Transcode_Prompt;Ani4K.Extract_Prompt;Ani4K.Remux_Prompt;Ani4K.TranscodeAudio_Prompt;Ani4K.SetAudioPriority_Prompt;Ani4K.SetSubsPriority_Prompt;Ani4K.RenameFiles_Prompt" /f
REG ADD "%ROOT_CLASS%\*\shell\Anime4K-Batch_Prompt" /v Icon /t REG_SZ /d "%SystemRoot%\System32\imageres.dll,263" /f

REM Main entry for Directories
REG ADD "%ROOT_CLASS%\Directory\shell\Anime4K-Batch" /v MUIVerb /t REG_SZ /d "Anime4K-Batch" /f
REG ADD "%ROOT_CLASS%\Directory\shell\Anime4K-Batch" /v SubCommands /t REG_SZ /d "Ani4K.TranscodeDir;Ani4K.ExtractDir;Ani4K.RemuxDir;Ani4K.TranscodeAudioDir;Ani4K.SetAudioPriorityDir;Ani4K.SetSubsPriorityDir;Ani4K.RenameFilesDir" /f
REG ADD "%ROOT_CLASS%\Directory\shell\Anime4K-Batch" /v Icon /t REG_SZ /d "%SystemRoot%\System32\imageres.dll,263" /f

REM Main entry for Directories (Prompt)
REG ADD "%ROOT_CLASS%\Directory\shell\Anime4K-Batch_Prompt" /v MUIVerb /t REG_SZ /d "Anime4K-Batch (Prompt)" /f
REG ADD "%ROOT_CLASS%\Directory\shell\Anime4K-Batch_Prompt" /v SubCommands /t REG_SZ /d "Ani4K.TranscodeDir_Prompt;Ani4K.ExtractDir_Prompt;Ani4K.RemuxDir_Prompt;Ani4K.TranscodeAudioDir_Prompt;Ani4K.SetAudioPriorityDir_Prompt;Ani4K.SetSubsPriorityDir_Prompt;Ani4K.RenameFilesDir_Prompt" /f
REG ADD "%ROOT_CLASS%\Directory\shell\Anime4K-Batch_Prompt" /v Icon /t REG_SZ /d "%SystemRoot%\System32\imageres.dll,263" /f

REM Main entry for Background
REG ADD "%ROOT_CLASS%\Directory\Background\shell\Anime4K-Batch" /v MUIVerb /t REG_SZ /d "Anime4K-Batch" /f
REG ADD "%ROOT_CLASS%\Directory\Background\shell\Anime4K-Batch" /v SubCommands /t REG_SZ /d "Ani4K.TranscodeBg;Ani4K.ExtractBg;Ani4K.RemuxBg;Ani4K.TranscodeAudioBg;Ani4K.SetAudioPriorityBg;Ani4K.SetSubsPriorityBg;Ani4K.RenameFilesBg" /f
REG ADD "%ROOT_CLASS%\Directory\Background\shell\Anime4K-Batch" /v Icon /t REG_SZ /d "%SystemRoot%\System32\imageres.dll,263" /f

REM Main entry for Background (Prompt)
REG ADD "%ROOT_CLASS%\Directory\Background\shell\Anime4K-Batch_Prompt" /v MUIVerb /t REG_SZ /d "Anime4K-Batch (Prompt)" /f
REG ADD "%ROOT_CLASS%\Directory\Background\shell\Anime4K-Batch_Prompt" /v SubCommands /t REG_SZ /d "Ani4K.TranscodeBg_Prompt;Ani4K.ExtractBg_Prompt;Ani4K.RemuxBg_Prompt;Ani4K.TranscodeAudioBg_Prompt;Ani4K.SetAudioPriorityBg_Prompt;Ani4K.SetSubsPriorityBg_Prompt;Ani4K.RenameFilesBg_Prompt" /f
REG ADD "%ROOT_CLASS%\Directory\Background\shell\Anime4K-Batch_Prompt" /v Icon /t REG_SZ /d "%SystemRoot%\System32\imageres.dll,263" /f

echo Registry entries added successfully.
endlocal
pause
