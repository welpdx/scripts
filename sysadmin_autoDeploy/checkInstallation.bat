@echo off
set url=https://dl.google.com/chrome/install/latest/chrome_installer.exe
set output=%~dp0chrome_installer.exe

REM Download the installer if it doesn't exist. If it does, check its last modified date is earlier than the file at the download link
IF NOT EXIST "%output%" (
    echo Downloading Google Chrome...
    powershell.exe -Command "Invoke-WebRequest -Uri '%url%' -OutFile '%output%'"
) ELSE (
    echo Checking for updates...
    REM Get the last modified date of the downloaded file
    FOR /F "tokens=2*" %%A IN ('DIR /TW "%output%" ^| FIND /I "chrome_installer.exe"') DO SET filedate=%%B
    echo Last modified date of downloaded file: %filedate%
	pause
    REM Get the last modified date of the file at the download link
    FOR /F "tokens=2,3 delims=: " %%B IN ('powershell.exe -Command "(Invoke-WebRequest '%url%' -UseBasicParsing^).Headers^|findstr /c:"Last-Modified""') DO SET downloaddate=%%B %%C
    echo Last modified date of file at download link: %downloaddate%
    REM Compare the dates and download the file if the downloaded file is earlier than the file at the download link
    IF "%filedate%" LSS "%downloaddate%" (
        echo Updating Google Chrome...
        powershell.exe -Command "Invoke-WebRequest -Uri '%url%' -OutFile '%output%'"
    ) ELSE (
        echo Google Chrome is up to date.
    )
)
pause
REM Start the installation silently
start /wait "" "%output%" /silent /install /system-level
