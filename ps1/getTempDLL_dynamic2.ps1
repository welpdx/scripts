# Script to get the current CPU temperature, needs to run as admin/system
# Requires an external DLL from the GitHub-Project "LibreHardwareMonitor"
# On first execution, the script downloads the DLL from the GitHub-Project

# Requires -RunAsAdministrator

cls
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

Add-Type -LiteralPath $dll
$monitor = [LibreHardwareMonitor.Hardware.Computer]::new()
$monitor.IsCPUEnabled = $true
$monitor.Open()

foreach ($sensor in $monitor.Hardware.Sensors) {
    if ($sensor.SensorType -eq 'Temperature' -and $sensor.Name -eq 'Core Max') {
        $temp = $sensor.Value
        Write-Host "Core Max Temperature = $temp°C" -f y 
    }
    if ($sensor.SensorType -eq 'Temperature' -and $sensor.Name -eq 'Core Average') {
        $temp = $sensor.Value
        Write-Host "Core Average Temperature = $temp°C" -f y 
    }
    <#if ($sensor.SensorType -eq 'Temperature' ) {
        $temp = $sensor.Value
        Write-Host $sensor.name,$sensor.Value,"°C" -f y 
    }#>
}

$monitor.Close()
