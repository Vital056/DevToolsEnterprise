@echo off
chcp 65001 >nul
rem Запуск тестовой базы из .v8-project.json; -OpenReport открывает собранный отчёт. Пример: scripts\run-1c.bat -Base zup -OpenReport

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0run-1c.ps1" %*
exit /b %ERRORLEVEL%
