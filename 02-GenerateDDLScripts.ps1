# Define folders
$ddlFolder = "C:\TOOL\output\ddl"
$logFolder = "C:\TOOL\log"
$csvPath = "C:\TOOL\output\NamedInstanceServerList.csv"

# Create folders if not exist
New-Item -ItemType Directory -Path $ddlFolder -Force | Out-Null
New-Item -ItemType Directory -Path $logFolder -Force | Out-Null

# Credentials
$username = "compass_user"
$password = "C0mp@ss#123"
$securePassword = ConvertTo-SecureString $password -AsPlainText -Force

# Load CSV
$servers = Import-Csv -Path $csvPath

# Load SMO
Import-Module SqlServer -DisableNameChecking

foreach ($entry in $servers) {
    $serverName = $entry.ServerConnectionString
    $safeServerName = $serverName -replace '[\\/:*?"<>|]', '_'
    $logFile = "$logFolder\$safeServerName.log"
    
    Write-Output "`nConnecting to $serverName..." | Tee-Object -FilePath $logFile -Append

    try {
        $srv = New-Object Microsoft.SqlServer.Management.Smo.Server $serverName
        $srv.ConnectionContext.LoginSecure = $false
        $srv.ConnectionContext.set_Login($username)
        $srv.ConnectionContext.set_SecurePassword($securePassword)
        $srv.ConnectionContext.Connect()

        foreach ($db in $srv.Databases) {
            if ($db.IsSystemObject -eq $false) {
                $dbName = $db.Name
                $ddlFile = "$ddlFolder\${safeServerName}_${dbName}_ddlscript.sql"
                Write-Output "Generating DDL for $serverName -> $dbName" | Tee-Object -FilePath $logFile -Append
                "" | Out-File -FilePath $ddlFile -Encoding UTF8

                $scripter = New-Object Microsoft.SqlServer.Management.Smo.Scripter ($srv)
                $scripter.Options.ScriptDrops = $false
                $scripter.Options.WithDependencies = $false
                $scripter.Options.Indexes = $true
                $scripter.Options.DriAll = $true
                $scripter.Options.Triggers = $true
                $scripter.Options.FullTextIndexes = $true
                $scripter.Options.IncludeIfNotExists = $true
                $scripter.Options.SchemaQualify = $true
                $scripter.Options.NoCommandTerminator = $false

                $objects = @()
                $objects += $db.Tables | Where-Object { -not $_.IsSystemObject }
                $objects += $db.Views | Where-Object { -not $_.IsSystemObject }
                $objects += $db.StoredProcedures | Where-Object { -not $_.IsSystemObject }
                $objects += $db.UserDefinedFunctions
                $objects += $db.Triggers

                Write-Output "Found $($objects.Count) scriptable objects" | Tee-Object -FilePath $logFile -Append

                foreach ($obj in $objects) {
                    try {
                        $script = $scripter.Script($obj)
                        
                        # Append script to the DDL file
                        $script | Out-File -FilePath $ddlFile -Encoding UTF8 -Append
                        
                        # Add the GO delimiter after each object script
                        "GO" | Out-File -FilePath $ddlFile -Encoding UTF8 -Append
                    } catch {
                        $msg = "⚠️ Failed to script object: $($obj.Name) - $($_.Exception.Message)"
                        Write-Output $msg | Tee-Object -FilePath $logFile -Append
                    }
                }

                Write-Output "✅ DDL saved to $ddlFile" | Tee-Object -FilePath $logFile -Append
            }
        }

    } catch {
        $_ | Out-String | Tee-Object -FilePath $logFile -Append
        Write-Output "❌ Connection or scripting error for $serverName. See log: $logFile"
    }
}
