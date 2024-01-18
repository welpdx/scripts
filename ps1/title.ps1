# Prefix to add to window titles.
$prefix = "Top Secret"

# How often to update window titles (in milliseconds).
$interval = 1000

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public static class Win32 {
  [DllImport("User32.dll", EntryPoint="SetWindowText")]
  public static extern int SetWindowText(IntPtr hWnd, string strTitle);
}
"@

$timer = New-Object System.Timers.Timer

$timer.Enabled = $true
$timer.Interval = $interval
$timer.AutoReset = $true

function Change-Window-Titles($prefix) {
  Get-Process | ? {$_.mainWindowTitle -and $_.mainWindowTitle -notlike "$($prefix)*"} | %{
    [Win32]::SetWindowText($_.mainWindowHandle, "$prefix - $($_.mainWindowTitle)")
  }
}

Register-ObjectEvent -InputObject $timer -EventName Elapsed -Action {
  Change-Window-Titles $prefix
}