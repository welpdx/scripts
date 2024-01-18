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

# Create a timer for checking file existence
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 10000  # 60 seconds

# Create a checkbox to control the timer
$checkbox = New-Object System.Windows.Forms.CheckBox
$checkbox.Location = New-Object System.Drawing.Point(10, 10)
$checkbox.Text = "Auto-Check for File"
$Form.Controls.Add($checkbox)

# Create a textbox to display the file content or the message
$outputBox = New-Object System.Windows.Forms.TextBox
$outputBox.Location = New-Object System.Drawing.Point(10, 40)
$outputBox.Size = New-Object System.Drawing.Size(($FormWidth - 30), ($FormHeight - 100))
$outputBox.Multiline = $true
$outputBox.ReadOnly = $true
$outputBox.Font = New-Object System.Drawing.Font("Calibri", 11, [System.Drawing.FontStyle]::Bold)
$outputBox.ForeColor = [System.Drawing.Color]::Green
$outputBox.ScrollBars = "Vertical"

# Set initial text of the outputBox
if (Test-Path $filePath) {
    $outputBox.Text = Get-Content $filePath | Out-String
} else {
    $outputBox.Text = "C:\Windows\LTSvc\LTErrors.txt isn't created yet. Please wait... Checking again in " + ($timer.Interval / 1000) + " seconds."
}

$Form.Controls.Add($outputBox)

# Function to scroll to the bottom of the TextBox
function ScrollToBottom {
    $outputBox.SelectionStart = $outputBox.TextLength
    $outputBox.ScrollToCaret()
}

# Event handler for timer tick
$timer.add_Tick({
    if (Test-Path $filePath) {
        $outputBox.Text = Get-Content $filePath | Out-String
        ScrollToBottom
        
        # Reduce the timer interval to 5 seconds after the file is found
        $timer.Interval = 5000
    } else {
        $outputBox.Text = "C:\Windows\LTSvc\LTErrors.txt isn't created yet. Please wait... Checking again in " + ($timer.Interval / 1000) + " seconds."
    }
})

# Event handler for checkbox state change
$checkbox.add_CheckedChanged({
    if ($checkbox.Checked) {
        $timer.Start()
    } else {
        $timer.Stop()
    }
})

# Add the controls to the form
$Form.Controls.Add($checkbox)

# Event handler for Form closing
$Form.add_FormClosing({
    $timer.Stop()
})

$Form.Add_Shown({$Form.Activate()})
[void] $Form.ShowDialog()
