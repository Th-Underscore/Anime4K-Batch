@echo off

set "SCRIPT=%~1"
set "INPUT=%~2"
shift & shift

set /p "args=Args (optional, remember double quotes if necessary): "

call "%SCRIPT%" "%INPUT%" %* %args%