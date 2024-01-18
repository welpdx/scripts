#!ps
write-host hi
#timeout-30000
# Get a list of all running processes
$processes = Get-Process

# Check if Microsoft Teams is running
$teamsProcesses = $processes | Where-Object { $_.ProcessName -eq "Teams" }

if ($teamsProcesses.Count -gt 0) {
    Write-Host "Microsoft Teams is running."
    $teamsProcesses | ForEach-Object {
        Write-Host "Path of Microsoft Teams executable: $($_.Path)"
    }
} else {
    Write-Host "Microsoft Teams is not running."
}
