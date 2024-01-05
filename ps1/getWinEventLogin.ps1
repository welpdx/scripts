


# get full message of the first 20 events
# Get-WinEvent -LogName Security -MaxEvents 20 | Select-Object TimeCreated, Id, LevelDisplayName, @{Name='Message';Expression={$_.Message -replace '\r\n', ' '}} | Format-Table -AutoSize

# first 200 events, id 4624, message Logon Type, 
#Get-WinEvent -LogName Security -MaxEvents 200 | Where-Object { $_.Id -eq 4624 -and $_.Message -match "Logon Type:\s+3" } | Select-Object TimeCreated, Id, LevelDisplayName, @{Name='Message';Expression={$_.Message -replace '\r\n', ' '}} | Format-Table -AutoSize




# first 200 events
Get-WinEvent -LogName Security -MaxEvents 200 | Where-Object { $_.Id -eq 4624 } | Select-Object TimeCreated, Id, LevelDisplayName, @{Name='Message';Expression={$_.Message -replace '\r\n', ' '}} | Format-Table -AutoSize



