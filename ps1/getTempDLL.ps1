﻿#!ps
#timeout-30000
# Script to get the current CPU temperature, needs to run as admin/system
# Requires an external DLL from the GitHub-Project "LibreHardwareMonitor"
# On first execution, the script downloads the DLL from the GitHub-Project

# Requires -RunAsAdministrator


$dll = "$env:windir\system32\LibreHardwareMonitorLib.dll"
$storeDll = $true

if (!(Test-Path $dll)) {
    $web = [System.Net.WebClient]::new()

    # Get the latest release from GitHub
    $releaseUrl = "https://api.github.com/repos/LibreHardwareMonitor/LibreHardwareMonitor/releases/latest"
    $latestRelease = (Invoke-RestMethod -Uri $releaseUrl)

    # Find the correct asset file dynamically
    $asset = $latestRelease.assets | Where-Object { $_.name -like 'LibreHardwareMonitor*.zip' }

    if ($asset -eq $null) {
        Write-Host "No suitable asset found for LibreHardwareMonitor."
    }
    else {
        # Download the package
        $url = $asset.browser_download_url
        $zip = $web.DownloadData($url)
        Write-Host "Downloading DLL from $url..."

        # Extract the DLL
        Add-Type -AssemblyName System.IO.Compression
        $stream = [System.IO.MemoryStream]::new()
        $stream.Write($zip, 0, $zip.Length)
        $archive = [System.IO.Compression.ZipArchive]::new($stream)
        $entry = $archive.GetEntry('LibreHardwareMonitorLib.dll')
        $bytes = [byte[]]::new($entry.Length)
        [void]$entry.Open().Read($bytes, 0, $bytes.Length)


        # Save the DLL
        if ($storeDll) {
            [System.IO.File]::WriteAllBytes($dll, $bytes)
            Unblock-File -LiteralPath $dll
        }

    }
}
else {
    $bytes = [System.IO.File]::ReadAllBytes($dll)
    if (!$storeDll) { Remove-Item $dll -Force }
}

if ((Test-Path $dll)) {
    write-host "dll found at: ", "$env:windir\system32\LibreHardwareMonitorLib.dll"
}else {
    write-host "dll not found at: ", "$env:windir\system32\LibreHardwareMonitorLib.dll"
    break
}

#!ps
#timeout-30000
$dll = "$env:windir\system32\LibreHardwareMonitorLib.dll"
Add-Type -LiteralPath $dll
$monitor = [LibreHardwareMonitor.Hardware.Computer]::new()
$monitor.IsCPUEnabled = $true
$monitor.Open()

$degreeSymbol = [char]176

foreach ($sensor in $monitor.Hardware.Sensors) {
    if ($sensor.SensorType -eq 'Temperature' -and $sensor.Name -eq 'Core Max') {
        #$sensor.Value.GetType()
        #$temp = $sensor.Value -as [string]

        #$temp.GetType()

        #$temp = $temp|out-string
        #write-host ($temp -join ",")
        write-host "<b>$temp</b>"
        #[pscustomobject]@{Value = ($temp |out-string)}

        Write-Host "Core Max Temperature = ", $temp,"$degreeSymbol","C" 
    }
    if ($sensor.SensorType -eq 'Temperature' -and $sensor.Name -eq 'Core Average') {
        $temp = $sensor.Value
        Write-Host "Core Average Temperature = ","$temp","$degreeSymbol C" #-f y 
    }
    
}
$monitor.Close()
