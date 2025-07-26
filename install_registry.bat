@echo off
setlocal

if not "%1"=="am_admin" (
    powershell -Command "Start-Process -Verb RunAs -FilePath '%0' -ArgumentList 'am_admin'"
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
REG ADD "%ROOT_STORE%\Ani4K.Extract\command" /ve /d "\"%BASE_DIR%\scripts\extract-subs.bat\" \"%%1\" & pause" /f
REG ADD "%ROOT_STORE%\Ani4K.Extract" /v MUIVerb /t REG_SZ /d "Extract subtitles" /f
REG ADD "%ROOT_STORE%\Ani4K.Extract" /v Icon /t REG_SZ /d "%BASE_DIR%\assets\icons\Extract_32.ico" /f

REM Ani4K.Remux (File)
REG ADD "%ROOT_STORE%\Ani4K.Remux\command" /ve /d "\"%BASE_DIR%\scripts\remux.bat\" \"%%1\" & pause" /f
REG ADD "%ROOT_STORE%\Ani4K.Remux" /v MUIVerb /t REG_SZ /d "Remux" /f
REG ADD "%ROOT_STORE%\Ani4K.Remux" /v Icon /t REG_SZ /d "%BASE_DIR%\assets\icons\Remux_32.ico" /f

REM Ani4K.TranscodeAudio (File)
REG ADD "%ROOT_STORE%\Ani4K.TranscodeAudio\command" /ve /d "\"%BASE_DIR%\scripts\transcode-audio.bat\" \"%%1\" & pause" /f
REG ADD "%ROOT_STORE%\Ani4K.TranscodeAudio" /v MUIVerb /t REG_SZ /d "Transcode audio" /f
REG ADD "%ROOT_STORE%\Ani4K.TranscodeAudio" /v Icon /t REG_SZ /d "%BASE_DIR%\assets\icons\Transcode_32.ico" /f

REM Ani4K.SetAudioPriority (File)
REG ADD "%ROOT_STORE%\Ani4K.SetAudioPriority\command" /ve /d "\"%BASE_DIR%\scripts\set-audio-priority.bat\" \"%%1\" & pause" /f
REG ADD "%ROOT_STORE%\Ani4K.SetAudioPriority" /v MUIVerb /t REG_SZ /d "Set audio priority" /f
REG ADD "%ROOT_STORE%\Ani4K.SetAudioPriority" /v Icon /t REG_SZ /d "%SystemRoot%\System32\imageres.dll,109" /f

REM Ani4K.SetSubsPriority (File)
REG ADD "%ROOT_STORE%\Ani4K.SetSubsPriority\command" /ve /d "\"%BASE_DIR%\scripts\set-subs-priority.bat\" \"%%1\" & pause" /f
REG ADD "%ROOT_STORE%\Ani4K.SetSubsPriority" /v MUIVerb /t REG_SZ /d "Set subtitle priority" /f
REG ADD "%ROOT_STORE%\Ani4K.SetSubsPriority" /v Icon /t REG_SZ /d "%SystemRoot%\System32\imageres.dll,109" /f

REM --- Utils ---
REG ADD "%ROOT_STORE%\Ani4K.SetSubsPriority" /v CommandFlags /t REG_DWORD /d 0x040 /f

REM Ani4K.RenameFiles (File)
REG ADD "%ROOT_STORE%\Ani4K.RenameFiles\command" /ve /d "\"%BASE_DIR%\scripts\utils\exec_pwsh.cmd\" \"%BASE_DIR%\scripts\utils\Rename-MediaFiles.ps1\" -Path \"'%%1'\" & pause" /f
REG ADD "%ROOT_STORE%\Ani4K.RenameFiles" /v MUIVerb /t REG_SZ /d "Rename episodes" /f
REG ADD "%ROOT_STORE%\Ani4K.RenameFiles" /v Icon /t REG_SZ /d "%SystemRoot%\System32\imageres.dll,110" /f

echo Adding registry entries for file context menus with prompt (HKLM)...

REM --- Main GLSL Transcode Script (Prompt) ---
REM Ani4K.Transcode_Prompt (File)
REG ADD "%ROOT_STORE%\Ani4K.Transcode_Prompt\command" /ve /d "\"%BASE_DIR%\scripts\utils\prompt.cmd\" \"%BASE_DIR%\Anime4K-Batch.bat\" \"%%1\"" /f
REG ADD "%ROOT_STORE%\Ani4K.Transcode_Prompt" /v MUIVerb /t REG_SZ /d "Apply GLSL shaders" /f
REG ADD "%ROOT_STORE%\Ani4K.Transcode_Prompt" /v Icon /t REG_SZ /d "%BASE_DIR%\assets\icons\Transcode_32.ico" /f

REM --- Aux Scripts (Prompt) ---
REG ADD "%ROOT_STORE%\Ani4K.Transcode_Prompt" /v CommandFlags /t REG_DWORD /d 0x040 /f

REM Ani4K.Extract_Prompt (File)
REG ADD "%ROOT_STORE%\Ani4K.Extract_Prompt\command" /ve /d "\"%BASE_DIR%\scripts\utils\prompt.cmd\" \"%BASE_DIR%\scripts\extract-subs.bat\" \"%%1\" & pause" /f
REG ADD "%ROOT_STORE%\Ani4K.Extract_Prompt" /v MUIVerb /t REG_SZ /d "Extract subtitles" /f
REG ADD "%ROOT_STORE%\Ani4K.Extract_Prompt" /v Icon /t REG_SZ /d "%BASE_DIR%\assets\icons\Extract_32.ico" /f

REM Ani4K.Remux_Prompt (File)
REG ADD "%ROOT_STORE%\Ani4K.Remux_Prompt\command" /ve /d "\"%BASE_DIR%\scripts\utils\prompt.cmd\" \"%BASE_DIR%\scripts\remux.bat\" \"%%1\" & pause" /f
REG ADD "%ROOT_STORE%\Ani4K.Remux_Prompt" /v MUIVerb /t REG_SZ /d "Remux" /f
REG ADD "%ROOT_STORE%\Ani4K.Remux_Prompt" /v Icon /t REG_SZ /d "%BASE_DIR%\assets\icons\Remux_32.ico" /f

REM Ani4K.TranscodeAudio_Prompt (File)
REG ADD "%ROOT_STORE%\Ani4K.TranscodeAudio_Prompt\command" /ve /d "\"%BASE_DIR%\scripts\utils\prompt.cmd\" \"%BASE_DIR%\scripts\transcode-audio.bat\" \"%%1\" & pause" /f
REG ADD "%ROOT_STORE%\Ani4K.TranscodeAudio_Prompt" /v MUIVerb /t REG_SZ /d "Transcode audio" /f
REG ADD "%ROOT_STORE%\Ani4K.TranscodeAudio_Prompt" /v Icon /t REG_SZ /d "%BASE_DIR%\assets\icons\Transcode_32.ico" /f

REM Ani4K.SetAudioPriority_Prompt (File)
REG ADD "%ROOT_STORE%\Ani4K.SetAudioPriority_Prompt\command" /ve /d "\"%BASE_DIR%\scripts\utils\prompt.cmd\" \"%BASE_DIR%\scripts\set-audio-priority.bat\" \"%%1\" & pause" /f
REG ADD "%ROOT_STORE%\Ani4K.SetAudioPriority_Prompt" /v MUIVerb /t REG_SZ /d "Set audio priority" /f
REG ADD "%ROOT_STORE%\Ani4K.SetAudioPriority_Prompt" /v Icon /t REG_SZ /d "%SystemRoot%\System32\imageres.dll,109" /f

REM Ani4K.SetSubsPriority_Prompt (File)
REG ADD "%ROOT_STORE%\Ani4K.SetSubsPriority_Prompt\command" /ve /d "\"%BASE_DIR%\scripts\utils\prompt.cmd\" \"%BASE_DIR%\scripts\set-subs-priority.bat\" \"%%1\" & pause" /f
REG ADD "%ROOT_STORE%\Ani4K.SetSubsPriority_Prompt" /v MUIVerb /t REG_SZ /d "Set subtitle priority" /f
REG ADD "%ROOT_STORE%\Ani4K.SetSubsPriority_Prompt" /v Icon /t REG_SZ /d "%SystemRoot%\System32\imageres.dll,109" /f

REM --- Utils (Prompt) ---
REG ADD "%ROOT_STORE%\Ani4K.SetSubsPriority_Prompt" /v CommandFlags /t REG_DWORD /d 0x040 /f

REM Ani4K.RenameFiles_Prompt (File)
REG ADD "%ROOT_STORE%\Ani4K.RenameFiles_Prompt\command" /ve /d "\"%BASE_DIR%\scripts\utils\prompt.cmd\" \"%BASE_DIR%\scripts\utils\exec_pwsh.cmd\" \"%BASE_DIR%\scripts\utils\Rename-MediaFiles.ps1\" -Path \"'%%1'\" & pause" /f
REG ADD "%ROOT_STORE%\Ani4K.RenameFiles_Prompt" /v MUIVerb /t REG_SZ /d "Rename episodes" /f
REG ADD "%ROOT_STORE%\Ani4K.RenameFiles_Prompt" /v Icon /t REG_SZ /d "%SystemRoot%\System32\imageres.dll,110" /f

echo Adding registry entries for directory context menus (HKLM)...

REM Delete existing directory entries first (ignore errors if they don't exist)
REG DELETE "%ROOT_STORE%\Ani4K.TranscodeDir" /f > nul 2>&1
REG DELETE "%ROOT_STORE%\Ani4K.ExtractDir" /f > nul 2>&1
REG DELETE "%ROOT_STORE%\Ani4K.RemuxDir" /f > nul 2>&1
REG DELETE "%ROOT_STORE%\Ani4K.TranscodeAudioDir" /f > nul 2>&1
REG DELETE "%ROOT_STORE%\Ani4K.SetAudioPriorityDir" /f > nul 2>&1
REG DELETE "%ROOT_STORE%\Ani4K.SetSubsPriorityDir" /f > nul 2>&1
REG DELETE "%ROOT_STORE%\Ani4K.RenameFilesDir" /f > nul 2>&1
REG DELETE "%ROOT_STORE%\Ani4K.TranscodeDir_Prompt" /f > nul 2>&1
REG DELETE "%ROOT_STORE%\Ani4K.ExtractDir_Prompt" /f > nul 2>&1
REG DELETE "%ROOT_STORE%\Ani4K.RemuxDir_Prompt" /f > nul 2>&1
REG DELETE "%ROOT_STORE%\Ani4K.TranscodeAudioDir_Prompt" /f > nul 2>&1
REG DELETE "%ROOT_STORE%\Ani4K.SetAudioPriorityDir_Prompt" /f > nul 2>&1
REG DELETE "%ROOT_STORE%\Ani4K.SetSubsPriorityDir_Prompt" /f > nul 2>&1
REG DELETE "%ROOT_STORE%\Ani4K.RenameFilesDir_Prompt" /f > nul 2>&1

REM Copy file entries to create directory entries
REG COPY "%ROOT_STORE%\Ani4K.Transcode" "%ROOT_STORE%\Ani4K.TranscodeDir" /s /f
REG COPY "%ROOT_STORE%\Ani4K.Extract" "%ROOT_STORE%\Ani4K.ExtractDir" /s /f
REG COPY "%ROOT_STORE%\Ani4K.Remux" "%ROOT_STORE%\Ani4K.RemuxDir" /s /f
REG COPY "%ROOT_STORE%\Ani4K.TranscodeAudio" "%ROOT_STORE%\Ani4K.TranscodeAudioDir" /s /f
REG COPY "%ROOT_STORE%\Ani4K.SetAudioPriority" "%ROOT_STORE%\Ani4K.SetAudioPriorityDir" /s /f
REG COPY "%ROOT_STORE%\Ani4K.SetSubsPriority" "%ROOT_STORE%\Ani4K.SetSubsPriorityDir" /s /f
REG COPY "%ROOT_STORE%\Ani4K.RenameFiles" "%ROOT_STORE%\Ani4K.RenameFilesDir" /s /f
REG COPY "%ROOT_STORE%\Ani4K.Transcode_Prompt" "%ROOT_STORE%\Ani4K.TranscodeDir_Prompt" /s /f
REG COPY "%ROOT_STORE%\Ani4K.Extract_Prompt" "%ROOT_STORE%\Ani4K.ExtractDir_Prompt" /s /f
REG COPY "%ROOT_STORE%\Ani4K.Remux_Prompt" "%ROOT_STORE%\Ani4K.RemuxDir_Prompt" /s /f
REG COPY "%ROOT_STORE%\Ani4K.TranscodeAudio_Prompt" "%ROOT_STORE%\Ani4K.TranscodeAudioDir_Prompt" /s /f
REG COPY "%ROOT_STORE%\Ani4K.SetAudioPriority_Prompt" "%ROOT_STORE%\Ani4K.SetAudioPriorityDir_Prompt" /s /f
REG COPY "%ROOT_STORE%\Ani4K.SetSubsPriority_Prompt" "%ROOT_STORE%\Ani4K.SetSubsPriorityDir_Prompt" /s /f
REG COPY "%ROOT_STORE%\Ani4K.RenameFiles_Prompt" "%ROOT_STORE%\Ani4K.RenameFilesDir_Prompt" /s /f

REM Update icons for directory entries
REG ADD "%ROOT_STORE%\Ani4K.TranscodeDir" /v Icon /t REG_SZ /d "%BASE_DIR%\assets\icons\TranscodeDir_32.ico" /f
REG ADD "%ROOT_STORE%\Ani4K.ExtractDir" /v Icon /t REG_SZ /d "%BASE_DIR%\assets\icons\ExtractDir_32.ico" /f
REG ADD "%ROOT_STORE%\Ani4K.RemuxDir" /v Icon /t REG_SZ /d "%BASE_DIR%\assets\icons\RemuxDir_32.ico" /f
REG ADD "%ROOT_STORE%\Ani4K.TranscodeAudioDir" /v Icon /t REG_SZ /d "%BASE_DIR%\assets\icons\TranscodeDir_32.ico" /f
REG ADD "%ROOT_STORE%\Ani4K.SetAudioPriorityDir" /v Icon /t REG_SZ /d "%SystemRoot%\System32\shell32.dll,108" /f
REG ADD "%ROOT_STORE%\Ani4K.SetSubsPriorityDir" /v Icon /t REG_SZ /d "%SystemRoot%\System32\shell32.dll,108" /f
REG ADD "%ROOT_STORE%\Ani4K.RenameFilesDir" /v Icon /t REG_SZ /d "%SystemRoot%\System32\shell32.dll,110" /f
REG ADD "%ROOT_STORE%\Ani4K.TranscodeDir_Prompt" /v Icon /t REG_SZ /d "%BASE_DIR%\assets\icons\TranscodeDir_32.ico" /f
REG ADD "%ROOT_STORE%\Ani4K.ExtractDir_Prompt" /v Icon /t REG_SZ /d "%BASE_DIR%\assets\icons\ExtractDir_32.ico" /f
REG ADD "%ROOT_STORE%\Ani4K.RemuxDir_Prompt" /v Icon /t REG_SZ /d "%BASE_DIR%\assets\icons\RemuxDir_32.ico" /f
REG ADD "%ROOT_STORE%\Ani4K.TranscodeAudioDir_Prompt" /v Icon /t REG_SZ /d "%BASE_DIR%\assets\icons\TranscodeDir_32.ico" /f
REG ADD "%ROOT_STORE%\Ani4K.SetAudioPriorityDir_Prompt" /v Icon /t REG_SZ /d "%SystemRoot%\System32\shell32.dll,108" /f
REG ADD "%ROOT_STORE%\Ani4K.SetSubsPriorityDir_Prompt" /v Icon /t REG_SZ /d "%SystemRoot%\System32\shell32.dll,108" /f
REG ADD "%ROOT_STORE%\Ani4K.RenameFilesDir_Prompt" /v Icon /t REG_SZ /d "%SystemRoot%\System32\shell32.dll,110" /f

echo Adding main context menu entries (HKCU)...

REM Main entry for Files (*)
REG ADD "%ROOT_CLASS%\*\shell\Anime4K-Batch" /v MUIVerb /t REG_SZ /d "Anime4K-Batch" /f
REG ADD "%ROOT_CLASS%\*\shell\Anime4K-Batch" /v SubCommands /t REG_SZ /d "Ani4K.Transcode;Ani4K.Extract;Ani4K.Remux;Ani4K.TranscodeAudio;Ani4K.SetAudioPriority;Ani4K.SetSubsPriority;Ani4K.RenameFiles" /f
REG ADD "%ROOT_CLASS%\*\shell\Anime4K-Batch" /v Icon /t REG_SZ /d "%BASE_DIR%\assets\icons\cmd_16.ico" /f

REM Main entry for Files (Prompt) (*)
REG ADD "%ROOT_CLASS%\*\shell\Anime4K-Batch_Prompt" /v MUIVerb /t REG_SZ /d "Anime4K-Batch (Prompt)" /f
REG ADD "%ROOT_CLASS%\*\shell\Anime4K-Batch_Prompt" /v SubCommands /t REG_SZ /d "Ani4K.Transcode_Prompt;Ani4K.Extract_Prompt;Ani4K.Remux_Prompt;Ani4K.TranscodeAudio_Prompt;Ani4K.SetAudioPriority_Prompt;Ani4K.SetSubsPriority_Prompt;Ani4K.RenameFiles_Prompt" /f
REG ADD "%ROOT_CLASS%\*\shell\Anime4K-Batch_Prompt" /v Icon /t REG_SZ /d "%BASE_DIR%\assets\icons\cmd_16.ico" /f

REM Main entry for Directories
REG ADD "%ROOT_CLASS%\Directory\shell\Anime4K-Batch" /v MUIVerb /t REG_SZ /d "Anime4K-Batch" /f
REG ADD "%ROOT_CLASS%\Directory\shell\Anime4K-Batch" /v SubCommands /t REG_SZ /d "Ani4K.TranscodeDir;Ani4K.ExtractDir;Ani4K.RemuxDir;Ani4K.TranscodeAudioDir;Ani4K.SetAudioPriorityDir;Ani4K.SetSubsPriorityDir;Ani4K.RenameFilesDir" /f
REG ADD "%ROOT_CLASS%\Directory\shell\Anime4K-Batch" /v Icon /t REG_SZ /d "%BASE_DIR%\assets\icons\cmd_16.ico" /f

REM Main entry for Directories (Prompt)
REG ADD "%ROOT_CLASS%\Directory\shell\Anime4K-Batch_Prompt" /v MUIVerb /t REG_SZ /d "Anime4K-Batch (Prompt)" /f
REG ADD "%ROOT_CLASS%\Directory\shell\Anime4K-Batch_Prompt" /v SubCommands /t REG_SZ /d "Ani4K.TranscodeDir_Prompt;Ani4K.ExtractDir_Prompt;Ani4K.RemuxDir_Prompt;Ani4K.TranscodeAudioDir_Prompt;Ani4K.SetAudioPriorityDir_Prompt;Ani4K.SetSubsPriorityDir_Prompt;Ani4K.RenameFilesDir_Prompt" /f
REG ADD "%ROOT_CLASS%\Directory\shell\Anime4K-Batch_Prompt" /v Icon /t REG_SZ /d "%BASE_DIR%\assets\icons\cmd_16.ico" /f

echo Registry entries added successfully.
endlocal
pause
