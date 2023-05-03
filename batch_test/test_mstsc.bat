@echo off


:askNum
echo MSTSC to 192.168.0.???
SET /P num=please enter the last 3 numbers: 


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

set ip=192.168.0.%num%
echo %ip%

pause

:establiesrdp

cmdkey /generic:"%ip%" /user:".\Administrator" /pass:"rusty barrel monkey Y22"
mstsc /v:%ip%
cmdkey /delete:%ip%
pause