param(
    [string]$ConfigPath = '',
    [string]$DatabaseName = 'HighSpeed_PROC',
    [string]$PreferredInstance = 'SQLEXPRESS',
    [string]$WimDir = '',
    [switch]$SkipConfigUpdate,
    [switch]$NoBackupConfig
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Step {
    param([string]$Message)
    Write-Host ('[WIM-SETUP] ' + $Message)
}

function Resolve-ConfigPath {
    param([string]$PathValue)
    if (-not [string]::IsNullOrWhiteSpace($PathValue)) {
        return (Resolve-Path -LiteralPath $PathValue).Path
    }
    $defaultPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'config\hongtang_config.json'
    return (Resolve-Path -LiteralPath $defaultPath).Path
}

function Find-SqlcmdExe {
    $candidates = @(
        'sqlcmd.exe',
        (Join-Path $env:ProgramFiles 'Microsoft SQL Server\Client SDK\ODBC\190\Tools\Binn\sqlcmd.exe'),
        (Join-Path $env:ProgramFiles 'Microsoft SQL Server\Client SDK\ODBC\180\Tools\Binn\sqlcmd.exe'),
        (Join-Path $env:ProgramFiles 'Microsoft SQL Server\Client SDK\ODBC\170\Tools\Binn\sqlcmd.exe'),
        (Join-Path $env:ProgramFiles 'Microsoft SQL Server\Client SDK\ODBC\130\Tools\Binn\sqlcmd.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Microsoft SQL Server\Client SDK\ODBC\170\Tools\Binn\sqlcmd.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Microsoft SQL Server\Client SDK\ODBC\130\Tools\Binn\sqlcmd.exe')
    )

    foreach ($candidate in $candidates) {
        if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
        $cmd = Get-Command $candidate -ErrorAction SilentlyContinue
        if ($cmd) { return $cmd.Source }
        if (Test-Path -LiteralPath $candidate) { return (Resolve-Path -LiteralPath $candidate).Path }
    }

    throw 'sqlcmd.exe not found. Install SQL Server command line utilities first.'
}

function Get-SqlServiceChoice {
    param([string]$Preferred)

    $services = Get-Service | Where-Object { $_.Name -eq 'MSSQLSERVER' -or $_.Name -like 'MSSQL$*' }
    if (-not $services) {
        throw 'No SQL Server service found.'
    }

    $preferredName = if ([string]::IsNullOrWhiteSpace($Preferred)) { '' } else { 'MSSQL$' + $Preferred }
    $ordered = @()
    if ($preferredName) {
        $ordered += $services | Where-Object { $_.Name -eq $preferredName }
    }
    $ordered += $services | Where-Object { $_.Name -eq 'MSSQLSERVER' }
    $ordered += $services | Where-Object { $_.Name -ne $preferredName -and $_.Name -ne 'MSSQLSERVER' }
    $ordered = $ordered | Group-Object Name | ForEach-Object { $_.Group[0] }

    $choice = $ordered | Where-Object { $_.Status -eq 'Running' } | Select-Object -First 1
    if (-not $choice) {
        $choice = $ordered | Select-Object -First 1
        Write-Step "Starting SQL Server service $($choice.Name)..."
        Start-Service -Name $choice.Name
        $choice.WaitForStatus('Running', [TimeSpan]::FromSeconds(20))
    }

    return $choice
}

function Get-ServerNameFromService {
    param([string]$ServiceName)
    if ($ServiceName -eq 'MSSQLSERVER') { return '.' }
    if ($ServiceName -like 'MSSQL$*') {
        return '.\\' + $ServiceName.Substring(6)
    }
    throw "Unsupported SQL Server service name: $ServiceName"
}

function Invoke-SqlcmdText {
    param(
        [string]$SqlcmdExe,
        [string]$Server,
        [string]$Database,
        [string]$Sql
    )

    $args = @('-S', $Server, '-d', $Database, '-E', '-b', '-C', '-Q', $Sql)
    $output = & $SqlcmdExe @args 2>&1 | Out-String
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "sqlcmd failed: $output"
    }
    return $output.Trim()
}

function Escape-SqlString {
    param([string]$Value)
    return $Value.Replace("'", "''")
}

function Quote-SqlIdentifier {
    param([string]$Value)
    return '[' + $Value.Replace(']', ']]') + ']'
}

function Ensure-DatabaseAndPermissions {
    param(
        [string]$SqlcmdExe,
        [string]$Server,
        [string]$DatabaseName,
        [string]$LoginName
    )

    $dbLit = Escape-SqlString $DatabaseName
    $dbId = Quote-SqlIdentifier $DatabaseName
    $loginLit = Escape-SqlString $LoginName
    $loginId = Quote-SqlIdentifier $LoginName

    Write-Step "Testing connection to instance $Server..."
    $serverName = Invoke-SqlcmdText -SqlcmdExe $SqlcmdExe -Server $Server -Database 'master' -Sql 'SET NOCOUNT ON; SELECT @@SERVERNAME;'
    Write-Step "Connected to SQL Server: $serverName"

    Write-Step "Ensuring database $DatabaseName exists..."
    Invoke-SqlcmdText -SqlcmdExe $SqlcmdExe -Server $Server -Database 'master' -Sql @"
SET NOCOUNT ON;
IF DB_ID(N'$dbLit') IS NULL
BEGIN
    CREATE DATABASE $dbId;
END;
"@

    Write-Step "Ensuring Windows login $LoginName exists and has permissions..."
    Invoke-SqlcmdText -SqlcmdExe $SqlcmdExe -Server $Server -Database 'master' -Sql @"
SET NOCOUNT ON;
IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'$loginLit')
BEGIN
    CREATE LOGIN $loginId FROM WINDOWS;
END;
IF IS_SRVROLEMEMBER('bulkadmin', N'$loginLit') <> 1
BEGIN
    EXEC master..sp_addsrvrolemember @loginame = N'$loginLit', @rolename = N'bulkadmin';
END;
"@

    Invoke-SqlcmdText -SqlcmdExe $SqlcmdExe -Server $Server -Database $DatabaseName -Sql @"
SET NOCOUNT ON;
DECLARE @login sysname = N'$loginLit';
DECLARE @owner sysname = SUSER_SNAME((SELECT owner_sid FROM sys.databases WHERE name = DB_NAME()));
DECLARE @user_name sysname = (SELECT TOP 1 name FROM sys.database_principals WHERE sid = SUSER_SID(@login));

IF @owner = @login
BEGIN
    PRINT N'Login is already the database owner; skipping user/role mapping.';
END
ELSE
BEGIN
    DECLARE @sql nvarchar(max);

    IF @user_name IS NULL
    BEGIN
        CREATE USER $loginId FOR LOGIN $loginId;
        SET @user_name = @login;
    END;

    IF NOT EXISTS (
        SELECT 1
        FROM sys.database_role_members drm
        JOIN sys.database_principals r ON drm.role_principal_id = r.principal_id
        JOIN sys.database_principals m ON drm.member_principal_id = m.principal_id
        WHERE r.name = N'db_owner' AND m.name = @user_name
    )
    BEGIN
        SET @sql = N'ALTER ROLE [db_owner] ADD MEMBER ' + QUOTENAME(@user_name) + N';';
        EXEC sys.sp_executesql @sql;
    END;
END;
"@
}

function Normalize-PathForJson {
    param([string]$Value)
    return ($Value -replace '\\', '/')
}

function Update-JsonField {
    param(
        [string]$Text,
        [string]$Pattern,
        [string]$Replacement
    )
    $result = [regex]::Replace($Text, $Pattern, $Replacement, [System.Text.RegularExpressions.RegexOptions]::Singleline)
    if ($result -eq $Text) {
        throw "Pattern not found: $Pattern"
    }
    return $result
}

function Update-ConfigFile {
    param(
        [string]$Path,
        [string]$Server,
        [string]$DatabaseName,
        [string]$ServiceName,
        [string]$WimDir,
        [bool]$CreateBackup
    )

    $text = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
    if ($CreateBackup) {
        $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $backup = [System.IO.Path]::Combine([System.IO.Path]::GetDirectoryName($Path), ([System.IO.Path]::GetFileNameWithoutExtension($Path) + '_backup_' + $stamp + [System.IO.Path]::GetExtension($Path)))
        [System.IO.File]::WriteAllText($backup, $text, [System.Text.UTF8Encoding]::new($false))
        Write-Step "Backup written: $backup"
    }

    $serverJson = Normalize-PathForJson $Server
    $wimJson = if ([string]::IsNullOrWhiteSpace($WimDir)) { '' } else { Normalize-PathForJson $WimDir }

    $text = Update-JsonField -Text $text -Pattern '"server"\s*:\s*"[^"]*"' -Replacement ('"server": "' + $serverJson + '"')
    $text = Update-JsonField -Text $text -Pattern '"database"\s*:\s*"[^"]*"' -Replacement ('"database": "' + $DatabaseName + '"')
    $text = Update-JsonField -Text $text -Pattern '"service_name"\s*:\s*"[^"]*"' -Replacement ('"service_name": "' + $ServiceName + '"')
    if ($wimJson) {
        $text = Update-JsonField -Text $text -Pattern '("zhichen"\s*:\s*\{.*?"dir"\s*:\s*")[^"]*(")' -Replacement ('$1' + $wimJson + '$2')
    }

    [System.IO.File]::WriteAllText($Path, $text, [System.Text.UTF8Encoding]::new($false))
    Write-Step "Updated config: $Path"
}

$configPathResolved = Resolve-ConfigPath -PathValue $ConfigPath
$sqlcmdExe = Find-SqlcmdExe
$service = Get-SqlServiceChoice -Preferred $PreferredInstance
$serverName = Get-ServerNameFromService -ServiceName $service.Name
$loginName = "$env:USERDOMAIN\$env:USERNAME"

Write-Step "Using sqlcmd: $sqlcmdExe"
Write-Step "Using SQL Server service: $($service.Name)"
Write-Step "Using server name: $serverName"
Write-Step "Using Windows login: $loginName"

Ensure-DatabaseAndPermissions -SqlcmdExe $sqlcmdExe -Server $serverName -DatabaseName $DatabaseName -LoginName $loginName

if (-not $SkipConfigUpdate) {
    Update-ConfigFile -Path $configPathResolved -Server $serverName -DatabaseName $DatabaseName -ServiceName $service.Name -WimDir $WimDir -CreateBackup:(-not $NoBackupConfig)
}

Write-Step 'Done.'
Write-Host ''
Write-Host 'Suggested WIM DB config:'
Write-Host ('  server       = ' + $serverName)
Write-Host ('  database     = ' + $DatabaseName)
Write-Host ('  service_name = ' + $service.Name)
if (-not [string]::IsNullOrWhiteSpace($WimDir)) {
    Write-Host ('  zhichen.dir  = ' + (Normalize-PathForJson $WimDir))
}
