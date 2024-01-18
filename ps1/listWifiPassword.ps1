# Get the list of Wi-Fi profiles
$profiles = netsh wlan show profiles | Select-String "All User Profile" | ForEach-Object { $_ -replace "All User Profile     : ", "" }

# Initialize an array to store the profile information
$wifiProfiles = @()

# Iterate through each Wi-Fi profile
foreach ($profile in $profiles) {
    # Remove leading and trailing spaces from the profile name
    $profile = $profile.Trim()

    $profileInfo = New-Object PSObject -Property @{
        "Profile Name" = $profile
        "Wi-Fi Key" = ""
    }

    # Retrieve the Wi-Fi key for each profile
    $keyResult = netsh wlan show profile name="$profile" key=clear
    $keyContent = $keyResult | Select-String "Key content"
    
    if ($keyContent) {
        $key = ($keyContent -split ":")[1].Trim()
        $profileInfo."Wi-Fi Key" = $key
    }

    $wifiProfiles += $profileInfo
}

# Display the Wi-Fi profiles and keys in a table
$wifiProfiles | Format-Table -AutoSize
