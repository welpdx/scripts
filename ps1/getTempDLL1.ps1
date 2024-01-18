# Script to get the current CPU temperature, needs to run as admin/system
# Requires an external DLL from the GitHub-Project "LibreHardwareMonitor"
# On first execution, the script downloads the DLL from the GitHub-Project

#Requires -RunAsAdministrator

cls
$dll = "$env:windir\system32\LibreHardwareMonitorLib.dll"
$storeDll = $true

if (!(Test-Path $dll)) {
    $web = [System.Net.WebClient]::new()

    # Download the package:
    $url = "https://github.com/LibreHardwareMonitor/LibreHardwareMonitor/releases/download/v0.9.3/LibreHardwareMonitor-net472.zip"
    $zip = $web.DownloadData($url)
    Write-Host "Downloading DLL from $url..."

    # Extract the DLL:
    Add-Type -AssemblyName System.IO.Compression
    $stream = [System.IO.MemoryStream]::new()
    $stream.Write($zip, 0, $zip.Length)
    $archive = [System.IO.Compression.ZipArchive]::new($stream)
    $entry = $archive.GetEntry('LibreHardwareMonitorLib.dll')
    $bytes = [byte[]]::new($entry.Length)
    [void]$entry.Open().Read($bytes, 0, $bytes.Length)

    # Check MD5:
    $md5 = [Security.Cryptography.MD5CryptoServiceProvider]::new().ComputeHash($bytes)
    $hash = [string]::Concat($md5.ForEach{ $_.ToString("x2") })
    if ($hash -ne '5b4ff376c0a64564dbdc149e686035e0') { break }

    # Save the DLL:
    if ($storeDll) {
        [System.IO.File]::WriteAllBytes($dll, $bytes)
        Unblock-File -LiteralPath $dll
    }
} else {
    $bytes = [System.IO.File]::ReadAllBytes($dll)
    if (!$storeDll) { Remove-Item $dll -Force }
}

<#
Add-Type -LiteralPath $dll
$monitor = [LibreHardwareMonitor.Hardware.Computer]::new()
$monitor.IsCPUEnabled = $true
$monitor.Open()

$temperatureSum = 0
$temperatureCount = 0

foreach ($sensor in $monitor.Hardware.Sensors) {
    if ($sensor.SensorType -eq 'Temperature') {
        Write-Host $sensor.Name , " - ", $sensor.Value
        $temperatureSum += $sensor.Value
        $temperatureCount++
    }
}

$monitor.Close()

if ($temperatureCount -gt 0) {
    $averageTemperature = [math]::Round(($temperatureSum / $temperatureCount), 1)
    Write-Host "Average Temperature = $averageTemperature°C" -ForegroundColor Yellow
} else {
    Write-Host "No temperature sensors found." -ForegroundColor Red
}

#>

Add-Type -LiteralPath $dll
$monitor = [LibreHardwareMonitor.Hardware.Computer]::new()
$monitor.IsCPUEnabled = $true
$monitor.Open()
foreach ($sensor in $monitor.Hardware.Sensors) {
    if ($sensor.SensorType -eq 'Temperature' -and $sensor.Name -eq 'Core Max'){
        $temp = $sensor.Value
        write-host "Core Max Temperature = $temp°C" -f y 
    }
    if ($sensor.SensorType -eq 'Temperature' -and $sensor.Name -eq 'Core Average'){
        $temp = $sensor.Value
        write-host "Core Average Temperature = $temp°C" -f y 
        #break
    }
    <#if ($sensor.SensorType -eq 'Temperature' -and $sensor.Name -eq 'CPU Package'){
        $temp = $sensor.Value
        write-host "CPU Package Temperature = $temp°C" -f y 
        #break
    }#>
}
$monitor.Close()


