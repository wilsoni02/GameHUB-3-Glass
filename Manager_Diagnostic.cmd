@echo off
setlocal
title GameHUB 3 (Liquid Glass) - Manager diagnostic
echo GameHUB 3 (Liquid Glass) manager diagnostic
echo Close this console when finished.
echo.
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -ExecutionPolicy Bypass -NoLogo -NoProfile -NonInteractive -STA -File "%~dp0@Resources\Scripts\Manager.ps1" -Resources "%~dp0@Resources"
echo.
echo If the manager did not appear, capture the exact message above.
pause
endlocal
