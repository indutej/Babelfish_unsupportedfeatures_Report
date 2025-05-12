# Define the base path for reports and the output folder for both CSV and HTML
$basePath = "C:\Users\Administrator\Documents\BabelfishCompass"
$outputFolder = "C:\TOOL\output\babelfish_reports"
$outputCsv = Join-Path $outputFolder "Babelfish_Summary_Report.csv"  # Updated file name
$outputHtml = Join-Path $outputFolder "Babelfish_Summary_Report.html"  # HTML file name

# Delete existing reports if they exist
if (Test-Path $outputCsv) {
    Remove-Item $outputCsv -Force
    Write-Host "Deleted existing CSV report: $outputCsv"
}

if (Test-Path $outputHtml) {
    Remove-Item $outputHtml -Force
    Write-Host "Deleted existing HTML report: $outputHtml"
}

# Create output folder if it doesn't exist
if (!(Test-Path $outputFolder)) {
    New-Item -ItemType Directory -Path $outputFolder | Out-Null
}

# Prepare results array
$results = @()

# Loop through each folder under basePath
$folders = Get-ChildItem -Path $basePath -Directory

foreach ($folder in $folders) {
    $reportFile = Get-ChildItem -Path $folder.FullName -Filter "report-*.txt" | Select-Object -First 1
    if ($reportFile) {
        # Handle folders with or without instance names
        if ($folder.Name -match "^([^_]+)_([^_]+)_([^_]+)_ddlscript_Report") {
            # Folder name: servername_instancename_databasename_ddlscript_Report
            $serverName = $matches[1]
            $instanceName = $matches[2]
            $dbName = $matches[3]
        } elseif ($folder.Name -match "^([^_]+)_([^_]+)_ddlscript_Report") {
            # Folder name: servername_databasename_ddlscript_Report (no instance name)
            $serverName = $matches[1]
            $instanceName = "Default"  # Assign 'Default' for missing instance name
            $dbName = $matches[2]
        } else {
            continue
        }

        $fileContent = Get-Content -Path $reportFile.FullName
        $executiveSummaryLines = @()
        $assessmentSummaryLines = @()
        $objectCountLines = @()
        $notSupportedLines = @()
        $supportedLines = @()
        $captureExecutiveSummary = $false
        $captureAssessmentSummary = $false
        $captureObjectCount = $false
        $captureNotSupported = $false
        $captureSupported = $false

        # Loop through lines in the file
        foreach ($line in $fileContent) {
            # Capture Executive Summary for Babelfish
            if ($line.Trim() -match "Executive Summary for Babelfish") {
                $captureExecutiveSummary = $true
                continue
            }
            if ($captureExecutiveSummary -and $line.Trim() -match "--- Table Of Contents") {
                $captureExecutiveSummary = $false
            }
            if ($captureExecutiveSummary) {
                $executiveSummaryLines += $line
            }

            # Capture Assessment Summary
            if ($line.Trim() -match "--- Assessment Summary") {
                $captureAssessmentSummary = $true
                continue
            }
            if ($captureAssessmentSummary -and $line.Trim() -match "--- Object Count") {
                $captureAssessmentSummary = $false
            }
            if ($captureAssessmentSummary) {
                $assessmentSummaryLines += $line
            }

            # Capture Object Count
            if ($line.Trim() -match "--- Object Count") {
                $captureObjectCount = $true
                continue
            }
            if ($captureObjectCount -and $line.Trim() -match "=== SQL Features Report") {
                $captureObjectCount = $false
            }
            if ($captureObjectCount) {
                $objectCountLines += $line
            }

            # Capture SQL Features 'Not Supported' in Babelfish
            if ($line.Trim() -match "--- SQL features 'Not Supported' in Babelfish") {
                $captureNotSupported = $true
                continue
            }
            if ($captureNotSupported -and $line.Trim() -match "--- SQL features 'Review Manually' in Babelfish") {
                $captureNotSupported = $false
            }
            if ($captureNotSupported) {
                $notSupportedLines += $line
            }

            # Capture SQL Features 'Supported' in Babelfish
            if ($line.Trim() -match "--- SQL features 'Supported' in Babelfish") {
                $captureSupported = $true
                continue
            }
            if ($captureSupported -and $line.Trim() -match "--- X-ref: 'Not Supported'") {
                $captureSupported = $false
            }
            if ($captureSupported) {
                $supportedLines += $line
            }
        }

        # Join the sections into single text blocks
        $executiveSummaryText = ($executiveSummaryLines -join "`n") -replace '"', '""'
        $executiveSummaryText = "`"$executiveSummaryText`""

        $assessmentSummaryText = ($assessmentSummaryLines -join "`n") -replace '"', '""'
        $assessmentSummaryText = "`"$assessmentSummaryText`""

        $objectCountText = ($objectCountLines -join "`n") -replace '"', '""'
        $objectCountText = "`"$objectCountText`""

        $notSupportedText = ($notSupportedLines -join "`n") -replace '"', '""'
        $notSupportedText = "`"$notSupportedText`""

        $supportedText = ($supportedLines -join "`n") -replace '"', '""'
        $supportedText = "`"$supportedText`""

        # Add the result to the results array
        $results += [PSCustomObject]@{
            ServerName = $serverName
            InstanceName = $instanceName
            DatabaseName = $dbName
            "Executive Summary" = $executiveSummaryText
            "Assessment Summary" = $assessmentSummaryText
            "Object Count" = $objectCountText
            "SQL features 'Not Supported' in Babelfish" = $notSupportedText
            "SQL features 'Supported' in Babelfish" = $supportedText
        }
    }
}

# Export the results to CSV
$results | Export-Csv -Path $outputCsv -NoTypeInformation -Encoding UTF8

# Create HTML Table with server name at the top-left and readable format
$htmlContent = $results | ConvertTo-Html -Property ServerName, InstanceName, DatabaseName, "Executive Summary", "Assessment Summary", "Object Count", "SQL features 'Not Supported' in Babelfish", "SQL features 'Supported' in Babelfish" -Head "<style>table {width: 100%;border-collapse: collapse;}th, td {border: 1px solid black;padding: 8px;text-align: left;}th {background-color: #f2f2f2;}tr:nth-child(even) {background-color: #f9f9f9;}td {white-space: pre-wrap;}</style>" -Body "<h1>Babelfish Assessment Summary Report</h1>"

# Save the HTML content to a file
$htmlContent | Out-File -FilePath $outputHtml -Encoding UTF8

Write-Host "`n✅ Deleted existing reports (if any) and created new ones."
Write-Host "✅ CSV file saved to: $outputCsv"
Write-Host "✅ HTML report saved to: $outputHtml"
