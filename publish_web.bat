@echo off
rem Double-click to publish the Web build to GitHub Pages. See tools\publish_web.ps1 for what it does and the options.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\publish_web.ps1" %*
echo.
pause
