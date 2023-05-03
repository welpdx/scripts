@echo off
set uname=aalbert
set url="https://eaglecoptersltd.sharepoint.com/sites/hseshared"
set shortcut="%systemdrive%\Users\%uname%\Desktop\YYC Supervisors HSE Matters.url"
echo %shortcut%
echo [InternetShortcut]>>%shortcut%
echo URL=%url%>>%shortcut%
REM echo IconFile=%SystemRoot%\system32\SHELL32.dll>>%shortcut%
REM echo IconIndex=5>>%shortcut%

timeout /t 1 /nobreak 
exit /b


REM set shortcut="%systemdrive%\Users\dnguyen\OneDrive - LAN Solutions Corp\Desktop\EagleCopters.url"

cd C:\Users\aalbert\desktop