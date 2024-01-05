[void] [System.Reflection.Assembly]::LoadWithPartialName("System.Drawing")
[void] [System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms")

$Form = New-Object System.Windows.Forms.Form    

# Define variables L and R
$L = 480
$R = 600

$Form.Size = New-Object System.Drawing.Size($L, $R)
$Form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen  # Center the form on the screen

# Specify the file path to monitor
$filePath = "C:\Windows\LTSvc\LTErrors.txt"

# Set the window title to include the specified file name
$Form.Text = "Viewing File: $filePath"

############################################## OutputBox
$outputBox = New-Object System.Windows.Forms.TextBox 
$outputBox.Location = New-Object System.Drawing.Point(10, 10)

# Adjust the size of $outputBox using variables L and R
$outputBox.Size = New-Object System.Drawing.Size($($L - 40), $($R - 40))

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

$outputBox.Lines = Get-Content $filePath | Out-String

# Refresh the table using the timer
$timer.add_Tick({
    $outputBox.Lines = Get-Content $filePath | Out-String
})
$timer.Start()

##############################################

$Form.Add_Shown({$Form.Activate()})
[void] $Form.ShowDialog()

$timer.Stop()
$timer.Dispose()
