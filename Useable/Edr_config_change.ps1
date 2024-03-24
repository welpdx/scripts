$path = "C:\ProgramData\FortiEDR\Config\Collector\CollectorBootstrap.jsn"
$content = Get-Content $path

$regex = '^(\s*"NetworkMonitoringMode"\s*:\s*")[^"]*'
$matchingLine = $content | Select-String -Pattern $regex

if ($matchingLine) {
    Write-Host "Matching line: $matchingLine"
    $newContent = $content -replace $regex, '${1}TDI'
    $newContent | Set-Content $path
    Write-Host "Value changed successfully."
    Write-Host "$($content | Select-String -Pattern $regex)"
} else {
    Write-Host "Key not found."
}

