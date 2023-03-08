@echo off
set url=https://dl.google.com/chrome/install/latest/chrome_installer.exe
set output=%~dp0chrome_installer.exe

REM Download the installer if it doesn't exist. If it does, check its last modified date is earlier than the file at the download link
IF NOT EXIST "%output%" ^(
    echo Downloading Google Chrome...
    powershell.exe -Command "Invoke-WebRequest -Uri '%url%' -OutFile '%output%'"
    pause
^) ELSE ^(
    for %%f in ("%output%") do set localfilesize=%%~zf
    echo Local File size: %localfilesize%


    FOR /F "tokens=2,3 delims=: " %%B IN ('powershell.exe -Command "(Invoke-WebRequest '%url%' -UseBasicParsing).Headers | findstr Content-Length"') DO SET onlinefilesize=%%B
    echo Online File size: %onlinefilesize%

    IF NOT %localfilesize% EQU %onlinefilesize% ^(
        echo local file size different from online file size
        echo Updating Google Chrome...
        powershell.exe -Command "Invoke-WebRequest -Uri '%url%' -OutFile '%output%'"
    ^) ELSE ^(
        echo local file size is the same as online file size
        echo Google Chrome is up to date.
    ^)
^)
echo now install?
pause
REM Start the installation silently
::start /wait "" "%output%" /silent /install /system-level
