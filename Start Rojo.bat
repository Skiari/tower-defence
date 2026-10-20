@echo off
title Rojo - tower defence
cd /d "%~dp0"
echo Starting Rojo...
echo Keep this window open while you work. Close it to stop Rojo.
echo.
"tools\rojo.exe" serve default.project.json
echo.
echo Rojo stopped. If you see an error above, take a screenshot of this window.
pause
