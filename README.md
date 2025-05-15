# SimpleSQLiteCache

A simple module for connecting to SQLite as a generic cache store. Mostly intended as a simple example on how to use SQLite without relying on a module outside the SQLite DLL itself.

## Usage

Download the right .Net binaries for SQLite database for your version of PowerShell. (Only tested on Windows Desktop PSVersion 5 and CLRVersion 4) I wrote a [blog article](https://ziviz.us/WP/2025/05/14/powershell-and-sqlite/) with more info on getting the SQLite DLL happy.

Unblock and extract the SQLite binaries somewhere. Drop the PSM1 file into the SQLite directory, then you should be good to go.

```powershell
# Import and connect
Import-Module -Path "<Path to SimpleSQLiteCache.psm1>"
$connection = Connect-CacheDB -DBPath "<Path to your db file, or where you want a db file>"

# Ready to use, now add something
Add-CacheTableItem -Connection $connection -Name "SomeName" -Value "SomeValue" -ExpireMinutes 60

# Query it
Get-CacheTableItem -Connection $connection -Name "SomeName"

# Replace it's value
Add-CacheTableItem -Connection $connection -Name "SomeName" -Value "SomeNewValue" -ExpireMinutes 60

# Remove it manually
Remove-CacheTableItem -Connection $connection -Name "SomeName"

# Keep some other value, but without it auto-expiring
Add-CacheTableItem -Connection $connection -Name "SomeName" -Value "SomeNewValueToKeep"

# Cleanup old cached items, this is automatically called once during "Connect-CacheDB", but never again.
Cleanup-CacheTable -Connection $connection
```
