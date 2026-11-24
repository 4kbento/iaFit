@echo off
title iaFit - app (deixe esta janela aberta)
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\abrir_app.ps1"
echo.
pause
