@echo off
title iaFit - demonstracao do banco de dados
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\rodar.ps1" -Sql "banco\05_demonstracao.sql"
echo.
pause
