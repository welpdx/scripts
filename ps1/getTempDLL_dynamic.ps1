# Script to get the current CPU temperature, needs to run as admin/system
# Requires an external DLL from the GitHub-Project "LibreHardwareMonitor"
# On first execution, the script downloads the DLL from the GitHub-Project

#Requires -RunAsAdministrator

cls
$dllDirectory = "$env:windir\system32"
$dllFileName = "LibreHardwareMonitorLib.dll"
$dllPath = Join-Path -Path $dllDirectory -ChildPath $dllFileName
$storeDll = $true

if (!(Test-Path $dllPath)) {
    $web = [System.Net.WebClient]::new()

    # Get the latest release information from the GitHub API:
    $releaseInfo = Invoke-RestMethod -Uri 'https://api.github.com/repos/LibreHardwareMonitor/LibreHardwareMonitor/releases/latest'

    # Find the download URL for the DLL in the assets:
    $dllAsset = $releaseInfo.assets | Where-Object { $_.name -eq $dllFileName }
    
    if ($dllAsset) {
        $dllUrl = $dllAsset.browser_download_url
        Write-Host "Downloading DLL from $dllUrl..."

        # Download the DLL:
        $web.DownloadFile($dllUrl, $dllPath)

        # Unblock the downloaded file:
        Unblock-File -LiteralPath $dllPath
    }
    else {
        Write-Host "DLL not found in the release assets." -ForegroundColor Red
        $storeDll = $false
    }
}

if (Test-Path $dllPath) {
    Add-Type -LiteralPath $dllPath
    $monitor = [LibreHardwareMonitor.Hardware.Computer]::new()
    $monitor.IsCPUEnabled = $true
    $monitor.Open()
    
    foreach ($sensor in $monitor.Hardware.Sensors) {
        if ($sensor.SensorType -eq 'Temperature' -and $sensor.Name -eq 'Core Max') {
            $temp = $sensor.Value
            Write-Host "Core Max Temperature = $temp°C" -f Yellow
        }
        if ($sensor.SensorType -eq 'Temperature' -and $sensor.Name -eq 'Core Average') {
            $temp = $sensor.Value
            Write-Host "Core Average Temperature = $temp°C" -f Yellow
        }
    }
    
    $monitor.Close()
}
else {
    Write-Host "DLL not found or could not be downloaded." -ForegroundColor Red
}
