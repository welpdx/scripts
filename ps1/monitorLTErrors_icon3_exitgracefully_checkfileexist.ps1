[void] [System.Reflection.Assembly]::LoadWithPartialName("System.Drawing")
[void] [System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms")

$Form = New-Object System.Windows.Forms.Form

# Define variables for Form width and height
$FormWidth = 800
$FormHeight = 450

$Form.Size = New-Object System.Drawing.Size($FormWidth, $FormHeight)
$Form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen  # Center the form on the screen

# Specify the file path to monitor
$filePath = "C:\Windows\LTSvc\LTErrors.txt"

# Check if the file exists, and if not, display a pop-up message and keep checking every 60 seconds
$FileFound = $false
$CheckInterval = 60

while (-not $FileFound) {
    if (Test-Path $filePath) {
        $FileFound = $true
    } else {
        $PopupMessage = "C:\Windows\LTSvc\LTErrors.txt isn't created yet. Please wait... Checking again in $CheckInterval seconds."
        $Popup = New-Object System.Windows.Forms.Form
        $Popup.Size = New-Object System.Drawing.Size(400, 100)
        $Popup.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterParent
        $Label = New-Object System.Windows.Forms.Label
        $Label.Location = New-Object System.Drawing.Point(10, 10)
        $Label.Size = New-Object System.Drawing.Size(380, 50)
        $Label.Text = $PopupMessage
        $Popup.Controls.Add($Label)
        $Popup.ShowDialog()
        Start-Sleep -Seconds $CheckInterval
    }
}

# Rest of the script after the file is found
# ...

############################################## OutputBox
# Define variables for OutputBox location
$OutputBoxX = 10
$OutputBoxY = 10

$outputBox = New-Object System.Windows.Forms.TextBox 
$outputBox.Location = New-Object System.Drawing.Point($OutputBoxX, $OutputBoxY)

# Adjust the size of $outputBox using variables for Form width and height
$outputBox.Size = New-Object System.Drawing.Size(($FormWidth - 4 * $OutputBoxX), ($FormHeight - 6 * $OutputBoxY))

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

# Function to scroll to the bottom of the TextBox
function ScrollToBottom {
    $outputBox.SelectionStart = $outputBox.TextLength
    $outputBox.ScrollToCaret()
}

# Initial scroll to bottom
ScrollToBottom

# Flag to prevent recursive closure
$FormClosed = $false

# Function to stop the application gracefully
function Stop-Application {
    $FormClosed = $true
    $timer.Stop()
    $timer.Dispose()
    $Form.Close()
}

$outputBox.Lines = Get-Content $filePath | Out-String

# Refresh the table using the timer
$timer.add_Tick({
    try {
        $outputBox.Lines = Get-Content $filePath | Out-String
        ScrollToBottom
    } catch {
        # Handle the error gracefully, e.g., stop the application
        if (-not $FormClosed) {
            Stop-Application
        }
    }
})

# Event handler for Form closing
$Form.add_FormClosing({
    if (-not $FormClosed) {
        Stop-Application
    }
})

$timer.Start()

##############################################

$Form.Add_Shown({$Form.Activate()})
[void] $Form.ShowDialog()
