@echo off



set "newname=genericws02"
echo New computer name: %newname%



:approveName
choice /M "Do you like the new computer name? "
if errorlevel 2 goto :enterName
if errorlevel 1 goto :rename

:rename
echo Renaming computer to %newname%
pause
rem rename computer code here
goto :end




:end
