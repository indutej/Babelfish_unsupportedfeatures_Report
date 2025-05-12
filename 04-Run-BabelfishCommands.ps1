# Set working directory
Set-Location -Path "C:\TOOL\BabelfishCompass"

# Path to the file containing commands
$commandFile = "C:\TOOL\output\babelfishcmds\babelfish_commands.txt"

# Check if the file exists
if (Test-Path $commandFile) {
    # Read commands line by line
    $commands = Get-Content -Path $commandFile

    foreach ($cmd in $commands) {
        if (-not [string]::IsNullOrWhiteSpace($cmd)) {
            if ($cmd -match "^\s*BabelfishCompass\.bat") {
                $cmd = $cmd -replace "^\s*BabelfishCompass\.bat", ".\BabelfishCompass.bat"
            }
            Write-Host "Executing: $cmd"
            Invoke-Expression $cmd
        }
    }
} else {
    Write-Error "Command file not found: $commandFile"
}
