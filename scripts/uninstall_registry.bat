@echo off
setlocal

if not "%1"=="am_admin" (
    powershell -Command "Start-Process -Verb RunAs -FilePath '%0' -ArgumentList 'am_admin'"
    exit /b
)

REM Define root paths
set "ROOT_STORE=HKLM\Software\Microsoft\Windows\CurrentVersion\Explorer\CommandStore\Shell"
set "ROOT_CLASS=HKCU\Software\Classes"

echo Removing registry entries for file and directory context menus (HKLM)...

REM Delete file context menu entries
REG DELETE "%ROOT_STORE%\Ani4K.Transcode" /f
REG DELETE "%ROOT_STORE%\Ani4K.Extract" /f
REG DELETE "%ROOT_STORE%\Ani4K.Remux" /f

REM Delete directory context menu entries
REG DELETE "%ROOT_STORE%\Ani4K.TranscodeDir" /f
REG DELETE "%ROOT_STORE%\Ani4K.ExtractDir" /f
REG DELETE "%ROOT_STORE%\Ani4K.RemuxDir" /f

echo Removing main context menu entries (HKCU)...

REM Delete main entry for Files (*)
REG DELETE "%ROOT_CLASS%\*\shell\Anime4K-Batch" /f

REM Delete main entry for Directories
REG DELETE "%ROOT_CLASS%\Directory\shell\Anime4K-Batch" /f

echo Registry entries removed successfully.
endlocal
pause
