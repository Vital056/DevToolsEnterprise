@echo off
chcp 65001 >nul
rem Сборка build\DevToolsEnterprise.erf и служебной обработки build\launcher\DevToolsLauncher.epf

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0build.ps1" %*
exit /b %ERRORLEVEL%
