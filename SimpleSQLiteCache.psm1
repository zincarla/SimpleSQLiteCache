Add-Type -Path (Join-Path -Path $PSScriptRoot -ChildPath ".\System.Data.SQLite.dll")

<#
.SYNOPSIS
    Connects to a SQLite DB File, ensures there is a cache table, cleans up old entries, and returns the connection.

.PARAMETER DBPath
    Path to the database file.

.OUTPUTS
    The [System.Data.SQLite.SQLiteConnection] connection object to the database

.EXAMPLE
    Connect-CacheDB -DBPath "C:\MyDatabase.db"

#>
function Connect-CacheDB {
    Param([Parameter(Mandatory=$true)][string]$DBPath)

    $connectionString = "Data Source=$DBPath;Version=3;"
    $connection = New-Object System.Data.SQLite.SQLiteConnection($connectionString)
    $connection.Open() | Out-Null

    Init-CacheTable -Connection $connection
    Cleanup-CacheTable -Connection $connection

    return $connection
}

<#
.SYNOPSIS
    Using a SQLiteConnection, ensures the cachetable exists. Not callable outside the module.

.PARAMETER Connection
    Open connection to the database

.OUTPUTS
    None

.EXAMPLE
    Init-CacheTable -Connection $con

#>
function Init-CacheTable {
    Param([Parameter(Mandatory=$true)][System.Data.SQLite.SQLiteConnection]$Connection)
    
    #region check if table already exists and end if so
    $Query = @"
SELECT name 
FROM sqlite_schema
WHERE type='table' AND name='cachetable';
"@

    $command = New-Object System.Data.SQLite.SQLiteCommand($Query, $connection)
    $reader = $command.ExecuteReader()
    $AlreadyExists = $reader.HasRows
    $reader.Close() | Out-Null
    $reader.Dispose() | Out-Null
    $command.Dispose() | Out-Null
    
    if ($AlreadyExists) {
        Write-Debug "Cache table already exists"
        return
    }
    #endregion

    #region create table
    $Query = "CREATE TABLE IF NOT EXISTS cachetable (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL UNIQUE, value TEXT, creationtime DATETIME DEFAULT CURRENT_TIMESTAMP, expiretime DATETIME DEFAULT NULL);"
    $command = New-Object System.Data.SQLite.SQLiteCommand($Query, $connection)
    $command.ExecuteNonQuery() | Out-Null
    $command.Dispose() | Out-Null

    #index name
    $Query = "CREATE INDEX name_idx ON cachetable (name);"
    $command = New-Object System.Data.SQLite.SQLiteCommand($Query, $connection)
    $command.ExecuteNonQuery() | Out-Null
    $command.Dispose() | Out-Null

    #index times
    $Query = "CREATE INDEX creationtime_idx ON cachetable (creationtime);"
    $command = New-Object System.Data.SQLite.SQLiteCommand($Query, $connection)
    $command.ExecuteNonQuery() | Out-Null
    $command.Dispose() | Out-Null

    $Query = "CREATE INDEX expiretime_idx ON cachetable (expiretime);"
    $command = New-Object System.Data.SQLite.SQLiteCommand($Query, $connection)
    $command.ExecuteNonQuery() | Out-Null
    $command.Dispose() | Out-Null
    #endregion
}

<#
.SYNOPSIS
    Using a SQLiteConnection, removes entries that have expired.

.PARAMETER Connection
    Open connection to the database

.OUTPUTS
    None

.EXAMPLE
    Cleanup-CacheTable -Connection $con

#>
function Cleanup-CacheTable {
    Param([Parameter(Mandatory=$true)][System.Data.SQLite.SQLiteConnection]$Connection)
    $Query = "DELETE FROM cachetable WHERE expiretime < CURRENT_TIMESTAMP;"
    $command = New-Object System.Data.SQLite.SQLiteCommand($Query, $connection)
    $command.ExecuteNonQuery() | Out-Null
    $command.Dispose() | Out-Null
}

<#
.SYNOPSIS
    Using a SQLiteConnection, adds an entry to the cachetable

.PARAMETER Connection
    Open connection to the database

.PARAMETER Name
    Reference name for this item we are caching

.PARAMETER Value
    The value we want to store

.PARAMETER ExpireMinutes
    How many minutes we want to keep this entry for. Values of 0 or less will not be auto-cleaned.

.OUTPUTS
    None

.EXAMPLE
    Add-CacheTableItem -Connection $con -Name "MyReferenceName" -Value "Some arbitrary value to store" -ExpireMinutes 60

.EXAMPLE
    Add-CacheTableItem -Connection $con -Name "MyNonExpiringReferenceName" -Value "Some arbitrary value to store forever"

#>
function Add-CacheTableItem {
    Param([Parameter(Mandatory=$true)][System.Data.SQLite.SQLiteConnection]$Connection, [Parameter(Mandatory=$true)][string]$Name, [Parameter(Mandatory=$true)][string]$Value, [int]$ExpireMinutes=0)

    $Query = ""

    if ($ExpireMinutes -gt 0) {
        $Query = "INSERT INTO cachetable (name, value, expiretime) VALUES (@name, @value, DATETIME('now', @mins)) ON CONFLICT(name) DO UPDATE SET value = @value, creationtime = CURRENT_TIMESTAMP, expiretime=DATETIME('now', @mins);"
    } else {
        $Query = "INSERT INTO cachetable (name, value) VALUES (@name, @value) ON CONFLICT(name) DO UPDATE SET value = @value, creationtime = CURRENT_TIMESTAMP, expiretime=NULL;"
    }


    $command = New-Object System.Data.SQLite.SQLiteCommand($Query, $connection)
    $command.Parameters.AddWithValue("@name", $Name) | Out-Null
    $command.Parameters.AddWithValue("@value", $Value) | Out-Null

    if ($ExpireMinutes -gt 0) {
        $command.Parameters.AddWithValue("@mins", "+$ExpireMinutes minutes") | Out-Null
    }
    $command.ExecuteNonQuery() | Out-Null
    $command.Dispose() | Out-Null
}

<#
.SYNOPSIS
    Using a SQLiteConnection, retrieves a value from the cachtable by name

.PARAMETER Connection
    Open connection to the database

.PARAMETER Name
    Reference name for this item we are caching

.OUTPUTS
    One or more PSObjects representing the database entry for the requested cached item

.EXAMPLE
    Get-CacheTableItem -Connection $con -Name "MyReferenceName"

#>
function Get-CacheTableItem {
    Param([Parameter(Mandatory=$true)][System.Data.SQLite.SQLiteConnection]$Connection, [Parameter(Mandatory=$true)][string]$Name)

    $Query = "SELECT * FROM cachetable WHERE name = @name;"

    $command = New-Object System.Data.SQLite.SQLiteCommand($Query, $connection)
    $command.Parameters.AddWithValue("@name", $Name) | Out-Null

    $reader = $command.ExecuteReader()

    $ToReturn = @()

    while ($reader.Read()) {
        $NewObject = @{}
	    for ($i = 0; $i -lt $reader.FieldCount; $i++) {
            $NewObject.Add($reader.GetName($I), $reader.GetValue($I)) | Out-Null
	    }
	    $ToReturn += New-Object -TypeName PSObject -Property $NewObject
    }
    $reader.Close() | Out-Null
    $reader.Dispose() | Out-Null
    $command.Dispose() | Out-Null

    return $ToReturn
}

<#
.SYNOPSIS
    Using a SQLiteConnection, removes a value from the cachtable by name

.PARAMETER Connection
    Open connection to the database

.PARAMETER Name
    Reference name for this item we are removing

.OUTPUTS
    None

.EXAMPLE
    Remove-CacheTableItem -Connection $con -Name "MyReferenceName"

#>
function Remove-CacheTableItem {
    Param([Parameter(Mandatory=$true)][System.Data.SQLite.SQLiteConnection]$Connection, [Parameter(Mandatory=$true)][string]$Name)

    $Query = "DELETE FROM cachetable WHERE name = @name;"

    $command = New-Object System.Data.SQLite.SQLiteCommand($Query, $connection)
    $command.Parameters.AddWithValue("@name", $Name) | Out-Null
    $command.ExecuteNonQuery() | Out-Null
    $command.Dispose() | Out-Null

    return $ToReturn
}

<#
.SYNOPSIS
    Using a SQLiteConnection, gets the number of cached items in teh cachetable

.PARAMETER Connection
    Open connection to the database

.OUTPUTS
    Number of cached items in table

.EXAMPLE
    Add-CacheTableItemCount -Connection $con

#>
function Get-CacheTableItemCount {
    Param([Parameter(Mandatory=$true)][System.Data.SQLite.SQLiteConnection]$Connection)

    $Query = "SELECT COUNT(*) AS Count FROM cachetable;"

    $command = New-Object System.Data.SQLite.SQLiteCommand($Query, $connection)

    $reader = $command.ExecuteReader()

    $ToReturn = @()

    while ($reader.Read()) {
        $NewObject = @{}
	    for ($i = 0; $i -lt $reader.FieldCount; $i++) {
            $NewObject.Add($reader.GetName($I), $reader.GetValue($I)) | Out-Null
	    }
	    $ToReturn += New-Object -TypeName PSObject -Property $NewObject
    }
    $reader.Close() | Out-Null
    $reader.Dispose() | Out-Null
    $command.Dispose() | Out-Null

    return $ToReturn[0].Count
}

<#
.SYNOPSIS
    Using a SQLiteConnection, returns all entries from the cachetable

.PARAMETER Connection
    Open connection to the database

.OUTPUTS
    One or more PSObjects representing entries in the cachetable

.EXAMPLE
    Get-CacheTableAllItems -Connection $con

#>
function Get-CacheTableAllItems {
    Param([Parameter(Mandatory=$true)][System.Data.SQLite.SQLiteConnection]$Connection)

    $Query = "SELECT * FROM cachetable;"

    $command = New-Object System.Data.SQLite.SQLiteCommand($Query, $connection)

    $reader = $command.ExecuteReader()

    $ToReturn = @()

    while ($reader.Read()) {
        $NewObject = @{}
	    for ($i = 0; $i -lt $reader.FieldCount; $i++) {
            $NewObject.Add($reader.GetName($I), $reader.GetValue($I)) | Out-Null
	    }
	    $ToReturn += New-Object -TypeName PSObject -Property $NewObject
    }
    $reader.Close() | Out-Null
    $reader.Dispose() | Out-Null
    $command.Dispose() | Out-Null

    return $ToReturn
}

<#
.SYNOPSIS
    Using a SQLiteConnection, gets expired entries that have not been removed yet

.PARAMETER Connection
    Open connection to the database

.OUTPUTS
    One or more PSObjects representing expired items in the cachetable

.EXAMPLE
    Get-CacheTableExpiredItems -Connection $con

#>
function Get-CacheTableExpiredItems {
    Param([Parameter(Mandatory=$true)][System.Data.SQLite.SQLiteConnection]$Connection)

    $Query = "SELECT * FROM cachetable WHERE expiretime < CURRENT_TIMESTAMP;"

    $command = New-Object System.Data.SQLite.SQLiteCommand($Query, $connection)

    $reader = $command.ExecuteReader()

    $ToReturn = @()

    while ($reader.Read()) {
        $NewObject = @{}
	    for ($i = 0; $i -lt $reader.FieldCount; $i++) {
            $NewObject.Add($reader.GetName($I), $reader.GetValue($I)) | Out-Null
	    }
	    $ToReturn += New-Object -TypeName PSObject -Property $NewObject
    }
    $reader.Close() | Out-Null
    $reader.Dispose() | Out-Null
    $command.Dispose() | Out-Null

    return $ToReturn
}

<#
.SYNOPSIS
    Closes an open SQLite connection

.PARAMETER Connection
    Open connection to the database

.OUTPUTS
    None

.EXAMPLE
    Close-CacheDB -Connection $con

#>
function Close-CacheDB {
    Param([Parameter(Mandatory=$true)][System.Data.SQLite.SQLiteConnection]$Connection)
    $Connection.Close()
    $Connection.Dispose()
    [System.GC]::Collect()
}

Export-ModuleMember -Function Connect-CacheDB, Cleanup-CacheTable, Add-CacheTableItem, Get-CacheTableItem, Get-CacheTableAllItems, Get-CacheTableExpiredItems, Close-CacheDB, Get-CacheTableItemCount, Remove-CacheTableItem
