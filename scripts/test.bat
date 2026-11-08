@echo off
chcp 65001 >nul
rem Сборка и запуск отчёта в тестовой базе: scripts\test.bat [id или алиас базы из .v8-project.json]

call "%~dp0build.bat" || exit /b 1
if "%~1"=="" (
    call "%~dp0run-1c.bat" -OpenReport
) else (
    call "%~dp0run-1c.bat" -Base %1 -OpenReport
)
exit /b %ERRORLEVEL%
