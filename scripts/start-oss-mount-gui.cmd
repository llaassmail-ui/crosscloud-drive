@echo off
set "SCRIPT_DIR=%~dp0"
start "" wscript.exe "%SCRIPT_DIR%start-oss-mount-gui.vbs"
exit /b
