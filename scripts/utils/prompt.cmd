@echo off

set "SCRIPT=%~1"
set "INPUT=%~2"
shift & shift

set "params="
:collect
if "%1"=="" goto :main
shift
set "params=%params% %1"
goto :collect

:main
set /p "args=Args (optional, remember double quotes if necessary): "

call "%SCRIPT%" "%INPUT%" %params% %args%