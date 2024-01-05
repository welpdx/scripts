$VersionURL = 'https://helpx.adobe.com/acrobat/release-note/release-notes-acrobat-reader.html'
$download_page = Invoke-WebRequest -Uri $VersionURL -UseBasicParsing
$ReleaseText = $download_page.Links | Where-Object { $_.innerText -match 'DC.*\([0-9.]+\)' } | Select-Object -ExpandProperty innerText -First 1

if ($ReleaseText -match 'DC.*\(([0-9.]+)\)') {
    $VersionNumber = $matches[1] -replace '\.', ''
}

# Format and echo each variable
Write-Host "Version URL: $VersionURL"
Write-Host "Download Page: $download_page"
Write-Host "Release Text: $ReleaseText"
Write-Host "Version Number: $VersionNumber"
