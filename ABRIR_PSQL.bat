@echo off
title iaFit - terminal SQL
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\rodar.ps1"
echo.
pause
