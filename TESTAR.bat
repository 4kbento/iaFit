@echo off
title iaFit - testes do banco de dados
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\rodar.ps1" -Sql "banco\04_testes.sql"
echo.
pause
