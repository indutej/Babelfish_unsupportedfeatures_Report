# Define input and output paths
$inputRoot = "C:\Users\Administrator\Documents\BabelfishCompass"
$outputFile = "C:\TOOL\output\babelfish_reports\unsupported_babelfish_features_report.csv"

# Create output directory if it doesn't exist
$outputDir = [System.IO.Path]::GetDirectoryName($outputFile)
if (!(Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir | Out-Null
}

# Initialize array for output data
$reportRows = @()

# Get all report CSVs recursively
$csvFiles = Get-ChildItem -Path $inputRoot -Recurse -Filter "report-*.csv"

foreach ($csvFile in $csvFiles) {
    $fileName = [System.IO.Path]::GetFileNameWithoutExtension($csvFile.Name)

    # Try to extract server, instance, database
    if ($fileName -match "^report-([^_]+)_([^_]+)_([^_]+)_ddlscript_Report") {
        $server = $matches[1]
        $instance = $matches[2]
        $database = $matches[3]
    }
    elseif ($fileName -match "^report-([^_]+)_([^_]+)_ddlscript_Report") {
        $server = $matches[1]
        $database = $matches[2]
        $instance = "default"
    }
    else {
        continue
    }

    $lines = Get-Content -Path $csvFile.FullName
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match "Status: Not Supported") {
            $j = $i + 2  # One line after the header
            while ($j -lt $lines.Count -and $lines[$j] -notmatch "^Status:") {
                $columns = $lines[$j] -split ","  # Assumes comma separator
                if ($columns.Count -ge 6) {
                    $reportRows += [PSCustomObject]@{
                        Servername               = $server
                        Instancename             = $instance
                        Database                 = $database
                        Issue                    = $columns[2].Trim('"')
                        Count                    = $columns[3].Trim('"')
                        "Babelfish Compass Hint" = $columns[4].Trim('"')
                        Complexity               = $columns[5].Trim('"')
                    }
                }
                $j++
            }
            break  # Only process the first "Not Supported" block
        }
    }
}

# Export to CSV
$reportRows | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8

Write-Host "Report generated at: $outputFile"
