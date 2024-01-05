# Define the folders to check at the root of the C: drive
$folders = @("_*", "Dell", "PerfLogs", "ODT")

# Initialize an array to store the folder details
$folderDetails = @()

# Iterate over each folder and check if it exists
foreach ($folder in $folders) {
    $path = "C:\$folder"

    # Check if the path exists and is a directory
    if (Test-Path $path -PathType Container) {
        # Calculate the folder size
        $bytes = (Get-ChildItem -Recurse -File $path | Measure-Object -Property Length -Sum).Sum
        $mb = [math]::Round($bytes / 1MB, 2)

        # Add the details to the array
        $folderDetails += [PSCustomObject]@{
            Path = $path
            SizeMB = $mb
        }
    }
}

# Display the folder details
Write-Host "Folder details (Path and Size in MB):"
$folderDetails | Format-Table -AutoSize

# Prompt the user for confirmation before deleting the folders
$confirmation = Read-Host "Do you want to delete these folders? (Y/N)"
if ($confirmation -eq 'Y') {
    foreach ($folderDetail in $folderDetails) {
        # Delete the folder recursively and silently
        Remove-Item -Path $folderDetail.Path -Recurse -Force -Confirm:$false
        Write-Host "Deleted folder: $($folderDetail.Path)"
    }
    Write-Host "All specified folders have been deleted."
} else {
    Write-Host "Folder deletion cancelled by the user."
}
