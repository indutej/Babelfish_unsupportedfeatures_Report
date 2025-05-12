# Define the folder where the ddl scripts are located
$ddlFolder = "C:\TOOL\output\ddl"
# Define the output folder for the commands
$outputFolder = "C:\TOOL\output\babelfishcmds"

# Ensure the output folder exists
if (-not (Test-Path $outputFolder)) {
    New-Item -Path $outputFolder -ItemType Directory
}

# Define the output file to save the commands
$outputFile = "$outputFolder\babelfish_commands.txt"

# Clear the content of the output file if it exists, or create a new one
if (Test-Path $outputFile) {
    Clear-Content -Path $outputFile
} else {
    New-Item -Path $outputFile -ItemType File
}

# Get all the .sql files in the ddl folder
$ddlFiles = Get-ChildItem -Path $ddlFolder -Filter "*.sql"

# Loop through each .sql file
foreach ($ddlFile in $ddlFiles) {
    # Get filename without extension
    $fileBaseName = [System.IO.Path]::GetFileNameWithoutExtension($ddlFile.Name)
    
    # Full path to the .sql file
    $ddlFilePath = $ddlFile.FullName

    # Create the second parameter (filename without .sql + _Report)
    $reportName = "${fileBaseName}_Report"

    # Construct the Babelfish command
    $babelfishCommand = "BabelfishCompass.bat $reportName $ddlFilePath -delete -rewrite -reportoptions xref,status=all,detail"

    # Append the command to the output file
    Add-Content -Path $outputFile -Value "$babelfishCommand`r`n"
}

Write-Host "Babelfish commands saved to $outputFile"
