# Script to check SQL Server connectivity and identify named instances
# Purpose: Check SQL servers from a list and identify named instances

# Function to log messages
function Write-Log {
    param (
        [string]$Message,
        [string]$LogFile = "C:\tool\output\script_log.txt"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $Message" | Out-File -FilePath $LogFile -Append
    Write-Host "$timestamp - $Message"
}

# Function to check if a directory exists, create if it doesn't
function Ensure-Directory {
    param (
        [string]$Path
    )
    
    if (-not (Test-Path -Path $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
        Write-Log "Created directory: $Path"
    }
}

# Ensure input and output directories exist
Ensure-Directory -Path "C:\tool\input"
Ensure-Directory -Path "C:\tool\output"

# Check if input file exists
$inputFile = "C:\tool\input\ServersList.csv"
if (-not (Test-Path -Path $inputFile)) {
    Write-Log "ERROR: Input file $inputFile does not exist. Script execution stopped."
    exit 1
}

# Initialize output files
$loginErrorFile = "C:\tool\output\loginerror.txt"
$namedInstanceFile = "C:\tool\output\NamedInstanceServerList.csv"
$loginCheckFile = "C:\tool\output\logincheck.csv"

# Clear output files if they exist
if (Test-Path -Path $loginErrorFile) {
    Remove-Item -Path $loginErrorFile -Force
}
if (Test-Path -Path $namedInstanceFile) {
    Remove-Item -Path $namedInstanceFile -Force
}
if (Test-Path -Path $loginCheckFile) {
    Remove-Item -Path $loginCheckFile -Force
}

# Create headers for output files
"ServerConnectionString,InstanceType" | Out-File -FilePath $namedInstanceFile -Encoding utf8
"Server,ErrorType,ErrorMessage" | Out-File -FilePath $loginCheckFile -Encoding utf8

# Default SQL credentials
$defaultSqlUsername = "compass_user"
$defaultSqlPassword = "C0mp@ss#123"
$defaultSecurePassword = ConvertTo-SecureString $defaultSqlPassword -AsPlainText -Force
$defaultCredential = New-Object System.Management.Automation.PSCredential ($defaultSqlUsername, $defaultSecurePassword)

# Alternative credentials for problematic servers
$altSqlUsername = "admin_user"  # Replace with actual alternative username
$altSqlPassword = "Admin@123"   # Replace with actual alternative password
$altSecurePassword = ConvertTo-SecureString $altSqlPassword -AsPlainText -Force
$altCredential = New-Object System.Management.Automation.PSCredential ($altSqlUsername, $altSecurePassword)

Write-Log "Starting SQL Server connectivity and named instance check..."

# Import SQL Server module if available
if (Get-Module -ListAvailable -Name SqlServer) {
    Import-Module SqlServer
    Write-Log "SqlServer module loaded successfully."
} else {
    Write-Log "WARNING: SqlServer module not found. Using .NET SQL Client instead."
}

# Read servers from input file
$servers = Get-Content -Path $inputFile | Where-Object { $_ -ne "" }
Write-Log "Found $($servers.Count) servers in the input file."

# Create a hashtable to store unique instances
$uniqueInstances = @{}
# Create a hashtable to track login issues
$loginIssues = @{}

foreach ($server in $servers) {
    $server = $server.Trim()
    Write-Log "Processing server: $server"
    
    # Check if server contains instance name (format: servername\instancename)
    $serverParts = $server -split '\\'
    $serverName = $serverParts[0]
    $instanceName = if ($serverParts.Count -gt 1) { $serverParts[1] } else { "MSSQLSERVER" }
    $isNamedInstance = if ($serverParts.Count -gt 1) { "Named Instance" } else { "Default Instance" }
    
    # Set credentials based on server
    $useIntegratedSecurity = $false
    $sqlUsername = $defaultSqlUsername
    $sqlPassword = $defaultSqlPassword
    
    # Special handling for problematic server
    if ($serverName -eq "EC2AMAZ-R9TKB17") {
        Write-Log "Using alternative approach for $serverName"
        
        # Option 1: Try Windows Authentication
        $useIntegratedSecurity = $true
        Write-Log "Attempting to use Windows Authentication for $serverName"
        
        # Option 2: Use alternative SQL credentials (uncomment if needed)
        # $sqlUsername = $altSqlUsername
        # $sqlPassword = $altSqlPassword
        # Write-Log "Using alternative SQL credentials for $serverName"
    }
    
    try {
        # Build connection string based on authentication method
        if ($useIntegratedSecurity) {
            $connectionString = "Server=$server;Integrated Security=True;Connection Timeout=10"
        } else {
            $connectionString = "Server=$server;User ID=$sqlUsername;Password=$sqlPassword;Connection Timeout=10"
        }
        
        # Try to connect to the SQL Server
        $connection = New-Object System.Data.SqlClient.SqlConnection($connectionString)
        $connection.Open()
        
        Write-Log "Successfully connected to $server"
        
        # Add the current server/instance to our unique instances list
        if ($instanceName -eq "MSSQLSERVER") {
            # For default instance, just use the server name
            $connectionFormat = $serverName
        } else {
            # For named instance, use server\instance format
            $connectionFormat = "$serverName\$instanceName"
        }
        
        if (-not $uniqueInstances.ContainsKey($connectionFormat)) {
            $uniqueInstances[$connectionFormat] = $isNamedInstance
        }
        
        # Query to get all instances on the server
        $query = @"
EXEC xp_regread
    @rootkey = 'HKEY_LOCAL_MACHINE',
    @key = 'SOFTWARE\Microsoft\Microsoft SQL Server',
    @value_name = 'InstalledInstances'
"@
        
        try {
            $command = New-Object System.Data.SqlClient.SqlCommand($query, $connection)
            $adapter = New-Object System.Data.SqlClient.SqlDataAdapter($command)
            $dataSet = New-Object System.Data.DataSet
            $adapter.Fill($dataSet) | Out-Null
            
            # Process results from registry query
            foreach ($row in $dataSet.Tables[0].Rows) {
                $regInstanceName = $row[0]
                
                # Skip entries that don't look like valid instance names
                if ($regInstanceName -match "InstalledInstances -" -or [string]::IsNullOrEmpty($regInstanceName)) {
                    continue
                }
                
                $isRegNamedInstance = if ($regInstanceName -ne "MSSQLSERVER") { "Named Instance" } else { "Default Instance" }
                
                # Format the connection string
                if ($regInstanceName -eq "MSSQLSERVER") {
                    $regConnectionFormat = $serverName
                } else {
                    $regConnectionFormat = "$serverName\$regInstanceName"
                }
                
                # Add to our unique instances list
                if (-not $uniqueInstances.ContainsKey($regConnectionFormat)) {
                    $uniqueInstances[$regConnectionFormat] = $isRegNamedInstance
                    Write-Log "Found instance from registry: $regConnectionFormat ($isRegNamedInstance)"
                }
            }
        }
        catch {
            Write-Log "Could not query registry for instances on $server. Error: $($_.Exception.Message)"
        }
        
        # Alternative query to get SQL Server instances
        $query2 = @"
SELECT 
    SERVERPROPERTY('MachineName') AS MachineName,
    SERVERPROPERTY('ServerName') AS FullServerName,
    SERVERPROPERTY('InstanceName') AS InstanceName
"@
        
        try {
            $command2 = New-Object System.Data.SqlClient.SqlCommand($query2, $connection)
            $adapter2 = New-Object System.Data.SqlClient.SqlDataAdapter($command2)
            $dataSet2 = New-Object System.Data.DataSet
            $adapter2.Fill($dataSet2) | Out-Null
            
            # Process results
            foreach ($row in $dataSet2.Tables[0].Rows) {
                $machineName = $row["MachineName"]
                $fullServerName = $row["FullServerName"]
                $dbInstanceName = $row["InstanceName"]
                
                # Skip if instance name is null or empty
                if ([string]::IsNullOrEmpty($dbInstanceName)) {
                    # This is a default instance
                    if (-not $uniqueInstances.ContainsKey($machineName)) {
                        $uniqueInstances[$machineName] = "Default Instance"
                        Write-Log "Found default instance: $machineName"
                    }
                } else {
                    # This is a named instance
                    $instanceConnectionString = "$machineName\$dbInstanceName"
                    if (-not $uniqueInstances.ContainsKey($instanceConnectionString)) {
                        $uniqueInstances[$instanceConnectionString] = "Named Instance"
                        Write-Log "Found named instance: $instanceConnectionString"
                    }
                }
            }
        }
        catch {
            Write-Log "Could not query server properties on $server. Error: $($_.Exception.Message)"
        }
        
        # Close connection
        $connection.Close()
    }
    catch {
        Write-Log "Failed to connect to $server. Error: $($_.Exception.Message)"
        # Log connection error
        "Server: $server - Error: $($_.Exception.Message)" | Out-File -FilePath $loginErrorFile -Append
        
        # Determine error type for logincheck.csv
        $errorMessage = $_.Exception.Message
        $errorType = "Unknown"
        
        if ($errorMessage -match "Login failed for user") {
            $errorType = "LoginFailed"
        }
        elseif ($errorMessage -match "Cannot open database") {
            $errorType = "DatabaseAccess"
        }
        elseif ($errorMessage -match "network-related or instance-specific") {
            $errorType = "ConnectionFailed"
        }
        elseif ($errorMessage -match "permission") {
            $errorType = "PermissionDenied"
        }
        
        # Add to login issues list
        if (-not $loginIssues.ContainsKey($server)) {
            $loginIssues[$server] = @{
                "ErrorType" = $errorType
                "ErrorMessage" = $errorMessage
            }
        }
        
        # If first attempt failed and it's the problematic server, try alternative method
        if ($serverName -eq "EC2AMAZ-R9TKB17" -and !$useIntegratedSecurity) {
            Write-Log "First attempt failed for $server. Trying Windows Authentication..."
            
            try {
                # Try Windows Authentication as fallback
                $connectionString = "Server=$server;Integrated Security=True;Connection Timeout=10"
                $connection = New-Object System.Data.SqlClient.SqlConnection($connectionString)
                $connection.Open()
                
                Write-Log "Successfully connected to $server using Windows Authentication"
                
                # Add the current server/instance to our unique instances list
                if ($instanceName -eq "MSSQLSERVER") {
                    # For default instance, just use the server name
                    $connectionFormat = $serverName
                } else {
                    # For named instance, use server\instance format
                    $connectionFormat = "$serverName\$instanceName"
                }
                
                if (-not $uniqueInstances.ContainsKey($connectionFormat)) {
                    $uniqueInstances[$connectionFormat] = $isNamedInstance
                }
                
                # Query to get all instances on the server
                $query = @"
EXEC xp_regread
    @rootkey = 'HKEY_LOCAL_MACHINE',
    @key = 'SOFTWARE\Microsoft\Microsoft SQL Server',
    @value_name = 'InstalledInstances'
"@
                
                try {
                    $command = New-Object System.Data.SqlClient.SqlCommand($query, $connection)
                    $adapter = New-Object System.Data.SqlClient.SqlDataAdapter($command)
                    $dataSet = New-Object System.Data.DataSet
                    $adapter.Fill($dataSet) | Out-Null
                    
                    # Process results from registry query
                    foreach ($row in $dataSet.Tables[0].Rows) {
                        $regInstanceName = $row[0]
                        
                        # Skip entries that don't look like valid instance names
                        if ($regInstanceName -match "InstalledInstances -" -or [string]::IsNullOrEmpty($regInstanceName)) {
                            continue
                        }
                        
                        $isRegNamedInstance = if ($regInstanceName -ne "MSSQLSERVER") { "Named Instance" } else { "Default Instance" }
                        
                        # Format the connection string
                        if ($regInstanceName -eq "MSSQLSERVER") {
                            $regConnectionFormat = $serverName
                        } else {
                            $regConnectionFormat = "$serverName\$regInstanceName"
                        }
                        
                        # Add to our unique instances list
                        if (-not $uniqueInstances.ContainsKey($regConnectionFormat)) {
                            $uniqueInstances[$regConnectionFormat] = $isRegNamedInstance
                            Write-Log "Found instance from registry: $regConnectionFormat ($isRegNamedInstance)"
                        }
                    }
                }
                catch {
                    Write-Log "Could not query registry for instances on $server. Error: $($_.Exception.Message)"
                }
                
                # Close connection
                $connection.Close()
                
                # Remove from login issues since we were able to connect with Windows Auth
                if ($loginIssues.ContainsKey($server)) {
                    $loginIssues.Remove($server)
                }
                
                # Add a special entry for compass_user login issue
                $loginIssues[$server] = @{
                    "ErrorType" = "CompassUserLoginFailed"
                    "ErrorMessage" = "compass_user login failed, but Windows Authentication succeeded"
                }
            }
            catch {
                Write-Log "Failed to connect to $server using Windows Authentication. Error: $($_.Exception.Message)"
                # Log connection error
                "Server: $server - Windows Auth Error: $($_.Exception.Message)" | Out-File -FilePath $loginErrorFile -Append
                
                # Update login issues with Windows Auth failure too
                if ($loginIssues.ContainsKey($server)) {
                    $loginIssues[$server]["ErrorType"] = "AllAuthFailed"
                    $loginIssues[$server]["ErrorMessage"] += " | Windows Auth: $($_.Exception.Message)"
                }
            }
        }
    }
}

# Try to discover SQL instances using SQL Browser service
Write-Log "Attempting to discover SQL instances using UDP queries..."

foreach ($server in $servers) {
    $server = $server.Trim()
    $serverName = ($server -split '\\')[0]  # Get just the server name without instance
    
    try {
        # Create UDP client to query SQL Browser service (port 1434)
        $udpClient = New-Object System.Net.Sockets.UdpClient
        $udpClient.Client.ReceiveTimeout = 2000  # 2 second timeout
        
        # Connect to the SQL Browser service
        $udpClient.Connect($serverName, 1434)
        
        # Send the discovery request (single byte 0x02)
        $bytes = [byte[]]@(0x02)
        $udpClient.Send($bytes, $bytes.Length) | Out-Null
        
        # Get the endpoint to receive from
        $remoteEndPoint = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, 0)
        
        # Receive the response
        try {
            $receivedBytes = $udpClient.Receive([ref]$remoteEndPoint)
            $response = [System.Text.Encoding]::ASCII.GetString($receivedBytes)
            
            # Parse the response (format: ServerName;InstanceName;IsClustered;Version;...)
            $instances = $response -split ";;", 0, "SimpleMatch"
            
            foreach ($instance in $instances) {
                if ($instance -match "ServerName;([^;]+);InstanceName;([^;]+);") {
                    $discoveredServerName = $Matches[1]
                    $discoveredInstanceName = $Matches[2]
                    
                    # Skip entries that don't look like valid instance names
                    if ($discoveredInstanceName -match "InstalledInstances -" -or [string]::IsNullOrEmpty($discoveredInstanceName)) {
                        continue
                    }
                    
                    $isNamedInstance = if ($discoveredInstanceName -ne "MSSQLSERVER") { "Named Instance" } else { "Default Instance" }
                    
                    # Format the connection string
                    if ($discoveredInstanceName -eq "MSSQLSERVER") {
                        $discoveredConnectionFormat = $discoveredServerName
                    } else {
                        $discoveredConnectionFormat = "$discoveredServerName\$discoveredInstanceName"
                    }
                    
                    # Add to our unique instances list
                    if (-not $uniqueInstances.ContainsKey($discoveredConnectionFormat)) {
                        $uniqueInstances[$discoveredConnectionFormat] = $isNamedInstance
                        Write-Log "Discovered via SQL Browser: $discoveredConnectionFormat ($isNamedInstance)"
                    }
                }
            }
        }
        catch {
            Write-Log "No response from SQL Browser service on $serverName. Error: $($_.Exception.Message)"
        }
        
        # Close the UDP client
        $udpClient.Close()
    }
    catch {
        Write-Log "Failed to query SQL Browser service on $serverName. Error: $($_.Exception.Message)"
    }
}

# Write the unique instances to the output file
foreach ($instance in $uniqueInstances.Keys | Sort-Object) {
    # Skip any entries with "InstalledInstances -" in them
    if ($instance -notmatch "InstalledInstances -") {
        "$instance,$($uniqueInstances[$instance])" | Out-File -FilePath $namedInstanceFile -Append -Encoding utf8
    }
}

# Write login issues to the logincheck.csv file
foreach ($server in $loginIssues.Keys | Sort-Object) {
    $errorType = $loginIssues[$server]["ErrorType"]
    $errorMessage = $loginIssues[$server]["ErrorMessage"]
    
    # Escape any commas in the error message for CSV format
    $errorMessage = $errorMessage -replace ',', ';'
    
    "$server,$errorType,$errorMessage" | Out-File -FilePath $loginCheckFile -Append -Encoding utf8
}

Write-Log "Script execution completed."
Write-Log "Login errors logged to: $loginErrorFile"
Write-Log "Named instance report generated at: $namedInstanceFile"
Write-Log "Login check report generated at: $loginCheckFile"
Write-Log "Found $($uniqueInstances.Count) unique SQL Server instances."
Write-Log "Found $($loginIssues.Count) servers with login issues."
