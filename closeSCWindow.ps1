Add-Type @"
using System;
using System.Runtime.InteropServices;

public class WinAPI {
    [DllImport("user32.dll", SetLastError = true)]
    public static extern int GetWindowText(IntPtr hWnd, System.Text.StringBuilder lpString, int nMaxCount);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool IsWindowVisible(IntPtr hWnd);
}
"@

$compName = $env:COMPUTERNAME
$targetTitle = "$compName - ScreenConnect"

# Loop through all processes and check window titles
$matching = Get-Process | ForEach-Object {
    $hWnd = $_.MainWindowHandle
    if ($hWnd -ne 0 -and [WinAPI]::IsWindowVisible($hWnd)) {
        $titleBuilder = New-Object System.Text.StringBuilder 1024
        [void][WinAPI]::GetWindowText($hWnd, $titleBuilder, $titleBuilder.Capacity)
        $title = $titleBuilder.ToString()
        if ($title.StartsWith($targetTitle)) {
            $_
        }
    }
}

# Show matches
$matching

# Kill if found
if ($matching) {
    $matching | ForEach-Object {
        Stop-Process -Id $_.Id -Force
        Write-Host "Killed process: $($_.ProcessName) ($($_.Id))"
    }
} else {
    Write-Host "No matching windows found."
}
