@echo off
if exist "%~dp0current.txt" (del "%~dp0current.txt" & echo File deleted.) else (echo File does not exist.)


pause

echo exiting %~nx0
timeout /t 3 /nobreak > nul
exit /b