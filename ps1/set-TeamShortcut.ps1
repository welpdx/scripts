# Define the path to the shortcut and the target application
$shortcutPath = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Microsoft Teams classic.lnk"
$targetPath = "$env:LOCALAPPDATA\Microsoft\Teams\Update.exe"

# Check if the shortcut already exists, and delete it if it does
if (Test-Path $shortcutPath) {
    Remove-Item $shortcutPath
}

# Create a new shortcut with compatibility mode for Windows 7
$WshShell = New-Object -ComObject WScript.Shell
$shortcut = $WshShell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = $targetPath
$shortcut.Arguments = "--processStart ""Teams.exe"" --process-start-args ""--system-initiated"""
$shortcut.WorkingDirectory = "$env:LOCALAPPDATA\Microsoft\Teams"
$shortcut.IconLocation = "$env:LOCALAPPDATA\Microsoft\Teams\Update.exe,0"
$shortcut.Description = "Microsoft Teams classic (Compatibility Mode for Windows 7)"
$shortcut.Save()

Write-Host "Shortcut created/updated successfully."
write-host "Press enter to shutdown Teams and Restart it"
pause
taskkill /f /im Teams.exe
timeout /t 3
start "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Microsoft Teams classic.lnk"