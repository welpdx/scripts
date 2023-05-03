@echo off


set "taskbarPath=%AppData%\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar\"
REM set taskbarPath=%~dp0\

REM Delete all shortcuts in the directory
DEL /F /S /Q /A "%taskbarPath%*"


REM Create a new File Explorer shortcut
powershell -Command "$ws = New-Object -ComObject WScript.Shell; $s = $ws.CreateShortcut('%taskbarPath%\File Explorer.lnk'); $s.TargetPath = 'C:\Windows\explorer.exe'; $s.Save()"


pause