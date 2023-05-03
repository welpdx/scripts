@echo off

::oneliner check
if 2 LSS 10 (echo asdf) else (echo adfasdf)


:askNum
set /p num=Enter a number: 

set /a check=num+0 2>nul

if "%check%"=="%num%" (
  if %num% LSS 10 (
    set "num=0%num%"
echo ondfasdf
echo %num%
  )
  echo Padded number: %num%
) else (
  echo "%num%" is not a valid number. Please try again.
  goto :askNum
)

pause

echo exiting %~nx0
timeout /t 3 /nobreak > nul
exit /b