@echo off
title iaFit - consultas de cada tela
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\rodar.ps1" -Sql "banco\03_consultas.sql"
echo.
pause
