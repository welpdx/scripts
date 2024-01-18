# Check if the current script is running as administrator
$currentUser = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$currentUser
$isAdmin = $currentUser.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$isAdmin

# Get the current Windows user
$currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()

# Get all the roles/groups the user belongs to
$userGroups = [Security.Principal.WindowsIdentity]::GetCurrent().Groups | ForEach-Object {
    $_.Translate([Security.Principal.NTAccount]).Value
}

# List all the roles/groups
foreach ($group in $userGroups) {
    Write-Host "User is in role: $group"
}