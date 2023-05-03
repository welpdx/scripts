@echo off


for /f "skip=1" %%a in ('wmic bios get serialnumber') do (
  set serial=%%a
  echo %serial%
)

pause
