[void] [System.Reflection.Assembly]::LoadWithPartialName("System.Drawing")
[void] [System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms")

$Form = New-Object System.Windows.Forms.Form    
$Form.Size = New-Object System.Drawing.Size(480, 600)
$Form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen  # Center the form on the screen



############################################## OutputBox

$outputBox = New-Object System.Windows.Forms.TextBox 
$outputBox.Location = New-Object System.Drawing.Point(10, 10) 
$outputBox.Size = New-Object System.Drawing.Size(440, 520)
$outputBox.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$outputBox.Multiline = $true 
$outputBox.ReadOnly = $true
$outputBox.Font = New-Object System.Drawing.Font("Calibri", 11, [System.Drawing.FontStyle]::Bold)
$outputBox.ForeColor = [System.Drawing.Color]::Green
$outputBox.ScrollBars = "Vertical" 
$Form.Controls.Add($outputBox) 

##############################################
$timer = New-Object System.Windows.Forms.Timer
# The value (in ms), at which the table is automatically refreshed (in this case, every 3 seconds)
$timer.Interval = 3000
##############################################

# Open a file dialog to select the file to be monitored
$openFileDialog = New-Object System.Windows.Forms.OpenFileDialog
$openFileDialog.InitialDirectory = [Environment]::GetFolderPath('MyDocuments')

if ($openFileDialog.ShowDialog() -eq 'OK') {
    $filePath = $openFileDialog.FileName

    $outputBox.Lines = Get-Content $filePath | Out-String

    # Refresh the table using the timer
    $timer.add_Tick({
        $outputBox.Lines = Get-Content $filePath | Out-String
    })
    $timer.Start()
}

##############################################

$filePath = $openFileDialog.FileName
$Form.Text = "Viewing File: $filePath"


$Form.Add_Shown({$Form.Activate()})
[void] $Form.ShowDialog()

$timer.Stop()
$timer.Dispose()
