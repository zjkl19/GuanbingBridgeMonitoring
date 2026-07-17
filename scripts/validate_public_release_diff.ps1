[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$BaseRef,

    [Parameter(Mandatory = $true)]
    [string]$AllowlistPath,

    [string]$RepositoryRoot = ".",

    [string]$BinaryContractPath = "config/public_release_binary_contract_v1.8.2.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)

$script:SchemaVersion = 2
$script:MaximumChangedXmlCharacters = 8 * 1024 * 1024

function Normalize-RepositoryPath {
    param([Parameter(Mandatory = $true)][string]$PathValue)

    $value = $PathValue.Trim().Replace("\", "/")
    while ($value.StartsWith("./", [System.StringComparison]::Ordinal)) {
        $value = $value.Substring(2)
    }
    return $value
}

function Get-RepositoryRelativeFilePath {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string]$Description
    )

    $separator = [System.IO.Path]::DirectorySeparatorChar
    $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd(
        [char[]]@([System.IO.Path]::DirectorySeparatorChar,
            [System.IO.Path]::AltDirectorySeparatorChar))
    $fileFull = [System.IO.Path]::GetFullPath($FilePath)
    $rootPrefix = $rootFull + $separator
    if (-not $fileFull.StartsWith(
            $rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "$Description must resolve inside the repository root."
    }

    $relative = Normalize-RepositoryPath -PathValue $fileFull.Substring($rootPrefix.Length)
    if ([string]::IsNullOrWhiteSpace($relative) -or
            [System.IO.Path]::IsPathRooted($relative) -or
            $relative -match '(^|/)\.\.(/|$)') {
        throw "$Description must resolve to an exact repository-relative file path."
    }
    return $relative
}

function Assert-NoReparsePointInRepositoryPath {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$RepositoryRelativePath,
        [Parameter(Mandatory = $true)][string]$Description
    )

    $current = [System.IO.Path]::GetFullPath($Root)
    $components = @('') + @($RepositoryRelativePath.Split('/') | Where-Object {
        -not [string]::IsNullOrWhiteSpace($_)
    })
    foreach ($component in $components) {
        if (-not [string]::IsNullOrEmpty($component)) {
            $current = Join-Path $current $component
        }
        if (-not (Test-Path -LiteralPath $current)) {
            continue
        }
        $item = Get-Item -LiteralPath $current -Force
        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "$Description cannot traverse a reparse point: $RepositoryRelativePath"
        }
    }
}

function Invoke-ReadOnlyGit {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    $oldOptionalLocks = $env:GIT_OPTIONAL_LOCKS
    $oldErrorPreference = $ErrorActionPreference
    $oldConsoleOutputEncoding = [Console]::OutputEncoding
    try {
        $env:GIT_OPTIONAL_LOCKS = "0"
        [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
        # Windows PowerShell wraps native stderr as ErrorRecord objects when it
        # is redirected. Capture those separately so benign Git diagnostics do
        # not contaminate path output or trip the caller's Stop preference.
        $ErrorActionPreference = "Continue"
        # Keep repository paths as actual Unicode text.  Git's default quoted
        # octal form cannot be compared safely with exact UTF-8 allowlist
        # entries such as the canonical Chinese DOCX template path.
        $gitArguments = @('-c', 'core.quotePath=false') + $Arguments
        $allOutput = @(& git -C $Root @gitArguments 2>&1)
        $exitCode = $LASTEXITCODE
    }
    finally {
        [Console]::OutputEncoding = $oldConsoleOutputEncoding
        $ErrorActionPreference = $oldErrorPreference
        if ($null -eq $oldOptionalLocks) {
            Remove-Item Env:GIT_OPTIONAL_LOCKS -ErrorAction SilentlyContinue
        }
        else {
            $env:GIT_OPTIONAL_LOCKS = $oldOptionalLocks
        }
    }

    $standardOutput = @($allOutput | Where-Object {
        $_ -isnot [System.Management.Automation.ErrorRecord]
    } | ForEach-Object { [string]$_ })
    $standardError = @($allOutput | Where-Object {
        $_ -is [System.Management.Automation.ErrorRecord]
    } | ForEach-Object { $_.ToString() })
    if ($exitCode -ne 0) {
        $detail = ($standardError + $standardOutput | Select-Object -Last 3) -join " | "
        throw "git $($Arguments -join ' ') failed with exit code ${exitCode}: $detail"
    }
    return $standardOutput
}

function Get-TextFingerprint {
    param([Parameter(Mandatory = $true)][string]$Value)

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
        return ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace("-", "").ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

if (-not ("GuanbingPublicReleaseCrc32" -as [type])) {
    Add-Type -TypeDefinition @'
using System;

public static class GuanbingPublicReleaseCrc32
{
    private static readonly uint[] Table = BuildTable();

    private static uint[] BuildTable()
    {
        var table = new uint[256];
        for (uint i = 0; i < table.Length; i++)
        {
            uint value = i;
            for (int bit = 0; bit < 8; bit++)
                value = (value & 1) != 0 ? 0xEDB88320U ^ (value >> 1) : value >> 1;
            table[i] = value;
        }
        return table;
    }

    public static uint Compute(byte[] bytes)
    {
        uint value = 0xFFFFFFFFU;
        foreach (byte item in bytes)
            value = Table[(value ^ item) & 0xFF] ^ (value >> 8);
        return value ^ 0xFFFFFFFFU;
    }
}
'@
}

function Get-Sha256HexFromBytes {
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$Bytes)

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([System.BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace("-", "")
    }
    finally {
        $sha.Dispose()
    }
}

function Get-GitBlobBytes {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Revision,
        [Parameter(Mandatory = $true)][string]$PathValue
    )

    $objectId = @(Invoke-ReadOnlyGit -Root $Root `
        -Arguments @('rev-parse', '--verify', "${Revision}:$PathValue")) |
        Select-Object -First 1
    $objectId = [string]$objectId
    if ($objectId -notmatch '^[0-9a-fA-F]{40,64}$') {
        throw "binary_contract_base_blob_missing"
    }

    $gitCommand = Get-Command git -ErrorAction Stop
    $processInfo = New-Object System.Diagnostics.ProcessStartInfo
    $processInfo.FileName = $gitCommand.Source
    $quotedRoot = '"' + $Root.Replace('"', '\"') + '"'
    $processInfo.Arguments = "-c core.quotePath=false -C $quotedRoot cat-file blob $objectId"
    $processInfo.UseShellExecute = $false
    $processInfo.CreateNoWindow = $true
    $processInfo.RedirectStandardOutput = $true
    $processInfo.RedirectStandardError = $true
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $processInfo
    $memory = New-Object System.IO.MemoryStream
    try {
        [void]$process.Start()
        $process.StandardOutput.BaseStream.CopyTo($memory)
        $stderr = $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        if ($process.ExitCode -ne 0) {
            throw "binary_contract_git_blob_read_failed"
        }
        Write-Output -NoEnumerate ([byte[]]$memory.ToArray())
    }
    finally {
        $memory.Dispose()
        $process.Dispose()
    }
}

function Get-ZipCentralDirectory {
    param([Parameter(Mandatory = $true)][byte[]]$Bytes)

    if ($Bytes.Length -lt 22) { throw "zip_eocd_missing" }
    $minimum = [Math]::Max(0, $Bytes.Length - 65557)
    $eocd = -1
    for ($offset = $Bytes.Length - 22; $offset -ge $minimum; $offset--) {
        if ([BitConverter]::ToUInt32($Bytes, $offset) -eq [uint32]0x06054B50) {
            $commentLength = [BitConverter]::ToUInt16($Bytes, $offset + 20)
            if ($offset + 22 + $commentLength -eq $Bytes.Length) {
                $eocd = $offset
                break
            }
        }
    }
    if ($eocd -lt 0) { throw "zip_eocd_missing" }

    $disk = [BitConverter]::ToUInt16($Bytes, $eocd + 4)
    $centralDisk = [BitConverter]::ToUInt16($Bytes, $eocd + 6)
    $entriesOnDisk = [BitConverter]::ToUInt16($Bytes, $eocd + 8)
    $entryCount = [BitConverter]::ToUInt16($Bytes, $eocd + 10)
    $centralSize = [BitConverter]::ToUInt32($Bytes, $eocd + 12)
    $centralOffset = [BitConverter]::ToUInt32($Bytes, $eocd + 16)
    if ($disk -ne 0 -or $centralDisk -ne 0 -or $entriesOnDisk -ne $entryCount) {
        throw "zip_multidisk_not_allowed"
    }
    if ($entryCount -eq 0xFFFF -or $centralSize -eq 0xFFFFFFFF -or
            $centralOffset -eq 0xFFFFFFFF) {
        throw "zip64_not_allowed"
    }
    if ([uint64]$centralOffset + [uint64]$centralSize -gt [uint64]$eocd) {
        throw "zip_central_directory_bounds_invalid"
    }

    $entries = New-Object 'System.Collections.Generic.List[object]'
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' `
        ([System.StringComparer]::Ordinal)
    $cursor = [int64]$centralOffset
    $utf8Strict = New-Object System.Text.UTF8Encoding($false, $true)
    $cp437 = [System.Text.Encoding]::GetEncoding(437)
    for ($index = 0; $index -lt $entryCount; $index++) {
        if ($cursor + 46 -gt $Bytes.Length -or
                [BitConverter]::ToUInt32($Bytes, [int]$cursor) -ne [uint32]0x02014B50) {
            throw "zip_central_directory_entry_invalid"
        }
        $flags = [BitConverter]::ToUInt16($Bytes, [int]$cursor + 8)
        if (($flags -band 1) -ne 0) { throw "zip_encrypted_entry_not_allowed" }
        $crc = [BitConverter]::ToUInt32($Bytes, [int]$cursor + 16)
        $compressedSize = [BitConverter]::ToUInt32($Bytes, [int]$cursor + 20)
        $uncompressedSize = [BitConverter]::ToUInt32($Bytes, [int]$cursor + 24)
        $nameLength = [BitConverter]::ToUInt16($Bytes, [int]$cursor + 28)
        $extraLength = [BitConverter]::ToUInt16($Bytes, [int]$cursor + 30)
        $commentLength = [BitConverter]::ToUInt16($Bytes, [int]$cursor + 32)
        $next = $cursor + 46 + $nameLength + $extraLength + $commentLength
        if ($next -gt [uint64]$Bytes.Length) { throw "zip_central_directory_bounds_invalid" }
        $nameBytes = New-Object byte[] $nameLength
        [Array]::Copy($Bytes, [int]$cursor + 46, $nameBytes, 0, $nameLength)
        try {
            $name = if (($flags -band 0x0800) -ne 0) {
                $utf8Strict.GetString($nameBytes)
            }
            else {
                $cp437.GetString($nameBytes)
            }
        }
        catch {
            throw "zip_member_name_encoding_invalid"
        }
        $segments = @($name.Split('/'))
        if ([string]::IsNullOrWhiteSpace($name) -or $name.Contains('\') -or
                $name.StartsWith('/') -or $name -match '^[A-Za-z]:' -or
                $segments -contains '.' -or $segments -contains '..' -or
                @($segments | Where-Object { $_ -eq '' }).Count -gt ($(if ($name.EndsWith('/')) { 1 } else { 0 }))) {
            throw "zip_member_path_unsafe"
        }
        if (-not $seen.Add($name)) { throw "zip_duplicate_member_not_allowed" }
        $entries.Add([pscustomobject][ordered]@{
            name = $name
            flags = [uint16]$flags
            crc32 = [uint32]$crc
            compressed_size = [uint32]$compressedSize
            uncompressed_size = [uint32]$uncompressedSize
        })
        $cursor = [int64]$next
    }
    if ($cursor -ne [int64]$centralOffset + [int64]$centralSize) {
        throw "zip_central_directory_size_mismatch"
    }
    return @($entries | ForEach-Object { $_ })
}

function Get-ZipContractInventory {
    param([Parameter(Mandatory = $true)][byte[]]$Bytes)

    Add-Type -AssemblyName System.IO.Compression
    $central = @(Get-ZipCentralDirectory -Bytes $Bytes)
    $stream = New-Object System.IO.MemoryStream(,$Bytes)
    $archive = $null
    try {
        $archive = New-Object System.IO.Compression.ZipArchive(
            $stream,
            [System.IO.Compression.ZipArchiveMode]::Read,
            $false)
        if ($archive.Entries.Count -ne $central.Count) {
            throw "zip_archive_entry_count_mismatch"
        }
        $byName = New-Object 'System.Collections.Generic.Dictionary[string,object]' `
            ([System.StringComparer]::Ordinal)
        $names = New-Object 'System.Collections.Generic.List[string]'
        [int64]$totalBytes = 0
        for ($index = 0; $index -lt $archive.Entries.Count; $index++) {
            $entry = $archive.Entries[$index]
            $centralEntry = $central[$index]
            if ($entry.FullName -cne $centralEntry.name) {
                throw "zip_member_order_or_name_mismatch"
            }
            $entryStream = $entry.Open()
            $content = New-Object System.IO.MemoryStream
            try {
                $entryStream.CopyTo($content)
                $payload = [byte[]]$content.ToArray()
            }
            finally {
                $entryStream.Dispose()
                $content.Dispose()
            }
            if ([uint64]$payload.Length -ne [uint64]$centralEntry.uncompressed_size) {
                throw "zip_member_uncompressed_size_mismatch"
            }
            if ([GuanbingPublicReleaseCrc32]::Compute($payload) -ne $centralEntry.crc32) {
                throw "zip_member_crc_mismatch"
            }
            $record = [pscustomobject][ordered]@{
                name = $entry.FullName
                bytes = [int64]$payload.Length
                sha256 = Get-Sha256HexFromBytes -Bytes $payload
                payload = $payload
            }
            $byName.Add($entry.FullName, $record)
            $names.Add($entry.FullName)
            $totalBytes += [int64]$payload.Length
        }
        return [pscustomobject][ordered]@{
            member_count = $names.Count
            total_uncompressed_bytes = $totalBytes
            names = @($names)
            by_name = $byName
        }
    }
    catch {
        if ($_.Exception.Message -match '^zip_[a-z0-9_]+$') { throw }
        throw "zip_archive_read_failed"
    }
    finally {
        if ($null -ne $archive) { $archive.Dispose() }
        $stream.Dispose()
    }
}

function Test-DocxBinaryContract {
    param(
        [Parameter(Mandatory = $true)][object]$Contract,
        [Parameter(Mandatory = $true)][byte[]]$BaseBytes,
        [Parameter(Mandatory = $true)][byte[]]$CurrentBytes,
        [Parameter(Mandatory = $true)][object[]]$Patterns,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()]
        [System.Collections.Generic.List[object]]$Findings,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()]
        [System.Collections.Generic.HashSet[string]]$FindingKeys
    )

    $errors = New-Object 'System.Collections.Generic.List[string]'
    if ((Get-Sha256HexFromBytes -Bytes $BaseBytes) -cne ([string]$Contract.base_sha256).ToUpperInvariant()) {
        $errors.Add('base_sha256_mismatch')
    }
    if ((Get-Sha256HexFromBytes -Bytes $CurrentBytes) -cne ([string]$Contract.current_sha256).ToUpperInvariant()) {
        $errors.Add('current_sha256_mismatch')
    }
    try {
        $baseInventory = Get-ZipContractInventory -Bytes $BaseBytes
        $currentInventory = Get-ZipContractInventory -Bytes $CurrentBytes
    }
    catch {
        $errors.Add($_.Exception.Message)
        return [pscustomobject][ordered]@{
            status = 'failed'
            errors = @($errors | ForEach-Object { $_ })
            member_count = 0
            changed_members = @()
        }
    }

    $expectedCount = [int]$Contract.member_count
    if ($baseInventory.member_count -ne $expectedCount -or
            $currentInventory.member_count -ne $expectedCount) {
        $errors.Add('member_count_mismatch')
    }
    if ($baseInventory.total_uncompressed_bytes -ne [int64]$Contract.base_total_uncompressed_bytes) {
        $errors.Add('base_total_uncompressed_bytes_mismatch')
    }
    if ($currentInventory.total_uncompressed_bytes -ne [int64]$Contract.current_total_uncompressed_bytes) {
        $errors.Add('current_total_uncompressed_bytes_mismatch')
    }
    if ($baseInventory.names.Count -ne $currentInventory.names.Count) {
        $errors.Add('member_name_or_order_mismatch')
    }
    else {
        for ($index = 0; $index -lt $baseInventory.names.Count; $index++) {
            if ($baseInventory.names[$index] -cne $currentInventory.names[$index]) {
                $errors.Add('member_name_or_order_mismatch')
                break
            }
        }
    }

    $allowed = New-Object 'System.Collections.Generic.Dictionary[string,object]' `
        ([System.StringComparer]::Ordinal)
    foreach ($member in @($Contract.allowed_changed_members)) {
        $memberPath = Normalize-RepositoryPath -PathValue ([string]$member.path)
        if ($allowed.ContainsKey($memberPath)) {
            throw "duplicate_binary_contract_member"
        }
        $allowed.Add($memberPath, $member)
    }
    $changed = New-Object 'System.Collections.Generic.List[string]'
    foreach ($name in @($baseInventory.names)) {
        if (-not $currentInventory.by_name.ContainsKey($name)) { continue }
        $baseEntry = $baseInventory.by_name[$name]
        $currentEntry = $currentInventory.by_name[$name]
        if ($baseEntry.sha256 -cne $currentEntry.sha256) { $changed.Add($name) }
    }
    $actualChanged = @($changed | Sort-Object)
    $expectedChanged = @($allowed.Keys | Sort-Object)
    if (($actualChanged -join "`n") -cne ($expectedChanged -join "`n")) {
        $errors.Add('changed_members_mismatch')
    }

    $findingCountBefore = $Findings.Count
    $utf8Strict = New-Object System.Text.UTF8Encoding($false, $true)
    foreach ($name in $expectedChanged) {
        if (-not $baseInventory.by_name.ContainsKey($name) -or
                -not $currentInventory.by_name.ContainsKey($name)) {
            continue
        }
        $expected = $allowed[$name]
        $baseEntry = $baseInventory.by_name[$name]
        $currentEntry = $currentInventory.by_name[$name]
        if ($baseEntry.sha256 -cne ([string]$expected.base_sha256).ToUpperInvariant()) {
            $errors.Add('base_changed_member_sha256_mismatch')
        }
        if ($currentEntry.sha256 -cne ([string]$expected.current_sha256).ToUpperInvariant()) {
            $errors.Add('current_changed_member_sha256_mismatch')
        }
        if ($name -notmatch '\.(?:xml|rels)$') {
            $errors.Add('changed_member_is_not_scannable_xml')
            continue
        }
        try {
            $text = $utf8Strict.GetString([byte[]]$currentEntry.payload)
            if ($text.Length -gt $script:MaximumChangedXmlCharacters) {
                $errors.Add('changed_member_xml_character_limit_exceeded')
                continue
            }
            $readerSettings = New-Object System.Xml.XmlReaderSettings
            $readerSettings.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
            $readerSettings.XmlResolver = $null
            $readerSettings.MaxCharactersInDocument = $script:MaximumChangedXmlCharacters
            $stringReader = New-Object System.IO.StringReader($text)
            $xmlReader = $null
            $xmlDocument = New-Object System.Xml.XmlDocument
            $xmlDocument.XmlResolver = $null
            try {
                $xmlReader = [System.Xml.XmlReader]::Create($stringReader, $readerSettings)
                $xmlDocument.Load($xmlReader)
            }
            finally {
                if ($null -ne $xmlReader) { $xmlReader.Dispose() }
                $stringReader.Dispose()
            }
        }
        catch {
            $errors.Add('changed_member_xml_invalid')
            continue
        }
        $lines = [regex]::Split($text, "\r?\n")
        for ($lineIndex = 0; $lineIndex -lt $lines.Count; $lineIndex++) {
            Test-AddedLine -PathValue (([string]$Contract.path) + '!' + $name) `
                -LineNumber ($lineIndex + 1) -Text $lines[$lineIndex] `
                -Patterns $Patterns -Findings $Findings -FindingKeys $FindingKeys
        }

        # Scan decoded DOM values as well as the serialized XML. Numeric and
        # named entities are semantically visible to Word but are not present
        # literally in the serialized payload (for example C&#58;&#92;Users).
        # Use a distinct virtual path so findings remain deterministic without
        # pretending that DOM nodes have source-file line numbers.
        $decodedPath = (([string]$Contract.path) + '!' + $name + '#decoded')
        $decodedIndex = 0
        foreach ($node in @($xmlDocument.SelectNodes('//text()'))) {
            $decodedIndex++
            Test-AddedLine -PathValue $decodedPath -LineNumber $decodedIndex `
                -Text ([string]$node.Value) -Patterns $Patterns `
                -Findings $Findings -FindingKeys $FindingKeys
        }
        foreach ($attribute in @($xmlDocument.SelectNodes('//@*'))) {
            $decodedIndex++
            Test-AddedLine -PathValue $decodedPath -LineNumber $decodedIndex `
                -Text ([string]$attribute.Value) -Patterns $Patterns `
                -Findings $Findings -FindingKeys $FindingKeys
        }
        $paragraphPath = (([string]$Contract.path) + '!' + $name + '#decoded-paragraph')
        $paragraphIndex = 0
        foreach ($paragraph in @($xmlDocument.SelectNodes('//*[local-name()="p"]'))) {
            $paragraphIndex++
            Test-AddedLine -PathValue $paragraphPath -LineNumber $paragraphIndex `
                -Text ([string]$paragraph.InnerText) -Patterns $Patterns `
                -Findings $Findings -FindingKeys $FindingKeys
        }
        Test-AddedLine `
            -PathValue (([string]$Contract.path) + '!' + $name + '#decoded-document') `
            -LineNumber 1 -Text ([string]$xmlDocument.DocumentElement.InnerText) `
            -Patterns $Patterns -Findings $Findings -FindingKeys $FindingKeys
    }
    if ($Findings.Count -gt $findingCountBefore) {
        $errors.Add('changed_member_sensitive_content')
    }

    return [pscustomobject][ordered]@{
        status = $(if ($errors.Count -eq 0) { 'ok' } else { 'failed' })
        errors = @($errors | Sort-Object -Unique)
        member_count = $currentInventory.member_count
        changed_members = $actualChanged
    }
}

function New-Finding {
    param(
        [Parameter(Mandatory = $true)][string]$PathValue,
        [Parameter(Mandatory = $true)][int]$LineNumber,
        [Parameter(Mandatory = $true)][int]$ColumnNumber,
        [Parameter(Mandatory = $true)][string]$Kind,
        [Parameter(Mandatory = $true)][string]$MatchedValue
    )

    return [pscustomobject][ordered]@{
        path = $PathValue
        line = $LineNumber
        column = $ColumnNumber
        kind = $Kind
        match_sha256 = Get-TextFingerprint -Value $MatchedValue
    }
}

function Get-ScanPatterns {
    $options = [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    $cnTask = "\u8ba1\u5212" + "\u4efb\u52a1"
    $cnRunning = "\u6b63\u5728" + "\u8fd0\u884c"
    $cnStarted = "\u5df2" + "\u542f\u52a8"
    $cnDisabled = "\u5df2" + "\u7981\u7528"
    $enTask = 'scheduled' + '\s+' + 'task'
    $enWindowsTask = 'windows' + '\s+' + 'task'
    $enStates = 'running' + '|disabled|started|completed'

    return @(
        [pscustomobject]@{
            kind = "rfc1918_ip"
            regex = [regex]::new(
                '(?<![0-9])(?:10(?:\.[0-9]{1,3}){3}|172\.(?:1[6-9]|2[0-9]|3[01])(?:\.[0-9]{1,3}){2}|192\.168(?:\.[0-9]{1,3}){2})(?![0-9])',
                $options)
        },
        [pscustomobject]@{
            kind = "ssh_user_target"
            regex = [regex]::new(
                '\b(?:ssh|scp|sftp)(?:\.exe)?\b[^\r\n]{0,160}\b[A-Za-z_][A-Za-z0-9._-]*@(?:[A-Za-z0-9.-]+|\[[0-9A-Fa-f:]+\])',
                $options)
        },
        [pscustomobject]@{
            kind = "absolute_windows_path"
            regex = [regex]::new(
                '(?<![A-Za-z0-9_])(?:[A-Za-z]:[\\/](?![\\/])[^\r\n`"''<>|]{2,})',
                $options)
        },
        [pscustomobject]@{
            kind = "scheduled_task_status"
            regex = [regex]::new(
                "\b(?:$enTask|$enWindowsTask|schtasks)\b[^\r\n]{0,120}\b(?:$enStates|pid\s*[:=]?\s*[0-9]+)\b",
                $options)
        },
        [pscustomobject]@{
            kind = "scheduled_task_status"
            regex = [regex]::new(
                "(?:$cnTask|\u4efb\u52a1\u540d)[^\r\n]{0,100}(?:$cnRunning|$cnStarted|$cnDisabled|PID\s*[:=]?\s*[0-9]+)",
                $options)
        },
        [pscustomobject]@{
            kind = "scheduled_task_identity"
            regex = [regex]::new(
                '\bGuanbing_v[0-9A-Za-z_]+_20[0-9]{6,}\b',
                $options)
        },
        [pscustomobject]@{
            kind = "private_key_block"
            regex = [regex]::new(
                '-----BEGIN\s+(?:RSA\s+|OPENSSH\s+|EC\s+)?PRIVATE\s+KEY-----',
                $options)
        },
        [pscustomobject]@{
            kind = "credential_token"
            regex = [regex]::new(
                '\b(?:yunpan_[A-Za-z0-9]{8,}|ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|glpat-[A-Za-z0-9_-]{20,}|AKIA[A-Z0-9]{16}|xox[baprs]-[A-Za-z0-9-]{10,})\b',
                $options)
        },
        [pscustomobject]@{
            kind = "credential_assignment"
            regex = [regex]::new(
                '\b(?:api[_-]?key|access[_-]?token|password|secret)\b\s*[:=]\s*["'']?(?!(?:\$\{|<|REDACTED\b|CHANGEME\b|PLACEHOLDER\b|TEST\b))[A-Za-z0-9_./+=-]{8,}',
                $options)
        }
    )
}

function Test-AddedLine {
    param(
        [Parameter(Mandatory = $true)][string]$PathValue,
        [Parameter(Mandatory = $true)][int]$LineNumber,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text,
        [Parameter(Mandatory = $true)][object[]]$Patterns,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()]
        [System.Collections.Generic.List[object]]$Findings,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()]
        [System.Collections.Generic.HashSet[string]]$FindingKeys
    )

    foreach ($pattern in $Patterns) {
        foreach ($match in $pattern.regex.Matches($Text)) {
            $column = $match.Index + 1
            $key = "${PathValue}:$($LineNumber):${column}:$($pattern.kind)"
            if ($FindingKeys.Add($key)) {
                $Findings.Add((New-Finding -PathValue $PathValue `
                    -LineNumber $LineNumber -ColumnNumber $column `
                    -Kind $pattern.kind -MatchedValue $match.Value))
            }
        }
    }
}

function Get-ForbiddenPaths {
    param([Parameter(Mandatory = $true)][string[]]$ChangedPaths)

    $patterns = @(
        '^docs/current_task_state\.md$',
        '^docs/known_issues\.md$',
        '^docs/ops(?:/|$)',
        '^docs/(?:machine_inventory|remote_ops_state|codex_worklog)\.md$',
        '^ops_local(?:/|$)',
        '^run_logs(?:/|$)',
        '^release/workbench/remote_deploy_evidence(?:/|$)'
    )
    return @($ChangedPaths | Where-Object {
        $candidate = $_
        @($patterns | Where-Object { $candidate -match $_ }).Count -gt 0
    } | Sort-Object -Unique)
}

$result = [ordered]@{
    schema_version = $script:SchemaVersion
    status = "error"
    read_only = $true
    base_ref = $BaseRef
    repository_name = ""
    allowlist_name = ""
    binary_contract_name = ""
    binary_contract_results = @()
    expected_files = @()
    changed_files = @()
    missing_files = @()
    unexpected_files = @()
    forbidden_files = @()
    sensitive_findings = @()
    error_count = 0
    error = ""
}
$exitCode = 3

try {
    if ($BaseRef.StartsWith("-", [System.StringComparison]::Ordinal)) {
        throw "BaseRef must be a revision name, not a command-line option."
    }

    $rootProbe = Invoke-ReadOnlyGit -Root $RepositoryRoot `
        -Arguments @('rev-parse', '--show-toplevel')
    $root = [System.IO.Path]::GetFullPath(($rootProbe | Select-Object -First 1).Trim())
    $result.repository_name = Split-Path -Leaf $root
    [void](Invoke-ReadOnlyGit -Root $root `
        -Arguments @('rev-parse', '--verify', "${BaseRef}^{commit}"))

    $allowlistCandidate = $AllowlistPath
    if (-not [System.IO.Path]::IsPathRooted($allowlistCandidate)) {
        $allowlistCandidate = Join-Path $root $allowlistCandidate
    }
    $allowlistFile = (Resolve-Path -LiteralPath $allowlistCandidate).Path
    $result.allowlist_name = Split-Path -Leaf $allowlistFile

    $expected = New-Object System.Collections.Generic.List[string]
    $expectedSet = New-Object 'System.Collections.Generic.HashSet[string]' `
        ([System.StringComparer]::Ordinal)
    foreach ($rawLine in Get-Content -LiteralPath $allowlistFile -Encoding UTF8) {
        $line = $rawLine.Trim()
        if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith('#')) {
            continue
        }
        $normalized = Normalize-RepositoryPath -PathValue $line
        if ([System.IO.Path]::IsPathRooted($normalized) -or
                $normalized -match '(^|/)\.\.(/|$)' -or
                $normalized.IndexOfAny([char[]]'*?[') -ge 0) {
            throw "Allowlist entries must be exact repository-relative paths: $line"
        }
        if (-not $expectedSet.Add($normalized)) {
            throw "Duplicate allowlist entry: $normalized"
        }
        $expected.Add($normalized)
    }
    if ($expected.Count -eq 0) {
        throw "The public release allowlist is empty."
    }

    $tracked = @(Invoke-ReadOnlyGit -Root $root `
        -Arguments @('diff', '--name-only', '--diff-filter=ACDMRTUXB', $BaseRef, '--') |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        ForEach-Object { Normalize-RepositoryPath -PathValue $_ })
    $untracked = @(Invoke-ReadOnlyGit -Root $root `
        -Arguments @('ls-files', '--others', '--exclude-standard') |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        ForEach-Object { Normalize-RepositoryPath -PathValue $_ })
    $changed = @($tracked + $untracked | Sort-Object -Unique)
    $expectedSorted = @($expected | Sort-Object -Unique)
    $missing = @($expectedSorted | Where-Object { $changed -notcontains $_ })
    $unexpected = @($changed | Where-Object { $expectedSet -notcontains $_ })
    $forbidden = @(Get-ForbiddenPaths -ChangedPaths $changed)

    $patterns = @(Get-ScanPatterns)
    $findings = New-Object 'System.Collections.Generic.List[object]'
    $findingKeys = New-Object 'System.Collections.Generic.HashSet[string]' `
        ([System.StringComparer]::Ordinal)
    $binaryContractByPath = New-Object 'System.Collections.Generic.Dictionary[string,object]' `
        ([System.StringComparer]::Ordinal)
    $binaryContractResults = New-Object 'System.Collections.Generic.List[object]'

    $binaryContractCandidate = $BinaryContractPath
    if (-not [string]::IsNullOrWhiteSpace($binaryContractCandidate)) {
        if (-not [System.IO.Path]::IsPathRooted($binaryContractCandidate)) {
            $binaryContractCandidate = Join-Path $root $binaryContractCandidate
        }
        if (Test-Path -LiteralPath $binaryContractCandidate -PathType Leaf) {
            $binaryContractFile = (Resolve-Path -LiteralPath $binaryContractCandidate).Path
            $binaryContractRepositoryPath = Get-RepositoryRelativeFilePath `
                -Root $root -FilePath $binaryContractFile `
                -Description 'BinaryContractPath'
            Assert-NoReparsePointInRepositoryPath -Root $root `
                -RepositoryRelativePath $binaryContractRepositoryPath `
                -Description 'BinaryContractPath'
            if (-not $expectedSet.Contains($binaryContractRepositoryPath)) {
                throw "BinaryContractPath must also be present in the public allowlist: $binaryContractRepositoryPath"
            }
            [void](Invoke-ReadOnlyGit -Root $root `
                -Arguments @('ls-files', '--error-unmatch', '--', $binaryContractRepositoryPath))
            $result.binary_contract_name = Split-Path -Leaf $binaryContractFile
            $binaryPayload = Get-Content -Raw -LiteralPath $binaryContractFile -Encoding UTF8 |
                ConvertFrom-Json
            if ([int]$binaryPayload.schema_version -ne 1) {
                throw "Unsupported public release binary contract schema."
            }
            foreach ($contract in @($binaryPayload.contracts)) {
                $pathValue = Normalize-RepositoryPath -PathValue ([string]$contract.path)
                if ([System.IO.Path]::IsPathRooted($pathValue) -or
                        $pathValue -match '(^|/)\.\.(/|$)' -or
                        $pathValue.IndexOfAny([char[]]'*?[') -ge 0) {
                    throw "Binary contract paths must be exact repository-relative paths."
                }
                if ($binaryContractByPath.ContainsKey($pathValue)) {
                    throw "Duplicate binary contract path: $pathValue"
                }
                if ([string]$contract.kind -cne 'docx_member_diff') {
                    throw "Unsupported binary contract kind for $pathValue"
                }
                if (-not $expectedSet.Contains($pathValue)) {
                    throw "Binary contract path must also be present in the public allowlist: $pathValue"
                }
                $binaryContractByPath.Add($pathValue, $contract)
                $fullPath = Join-Path $root ($pathValue.Replace('/', [System.IO.Path]::DirectorySeparatorChar))
                if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
                    throw "Binary contract target is missing: $pathValue"
                }
                Assert-NoReparsePointInRepositoryPath -Root $root `
                    -RepositoryRelativePath $pathValue `
                    -Description 'Binary contract target'
                $baseBytes = [byte[]](Get-GitBlobBytes -Root $root `
                    -Revision $BaseRef -PathValue $pathValue)
                $currentBytes = [System.IO.File]::ReadAllBytes($fullPath)
                $contractResult = Test-DocxBinaryContract -Contract $contract `
                    -BaseBytes $baseBytes -CurrentBytes $currentBytes `
                    -Patterns $patterns -Findings $findings -FindingKeys $findingKeys
                $binaryContractResults.Add([pscustomobject][ordered]@{
                    path = $pathValue
                    kind = 'docx_member_diff'
                    status = $contractResult.status
                    errors = @($contractResult.errors)
                    member_count = $contractResult.member_count
                    changed_members = @($contractResult.changed_members)
                })
                foreach ($contractError in @($contractResult.errors)) {
                    $key = "${pathValue}:0:0:binary_contract_violation:${contractError}"
                    if ($findingKeys.Add($key)) {
                        $findings.Add((New-Finding -PathValue $pathValue `
                            -LineNumber 0 -ColumnNumber 0 `
                            -Kind 'binary_contract_violation' `
                            -MatchedValue ([string]$contractError)))
                    }
                }
            }
        }
    }
    $result.binary_contract_results = @($binaryContractResults | ForEach-Object { $_ })

    $diffTracked = @($tracked | Where-Object {
        -not $binaryContractByPath.ContainsKey($_)
    })
    if ($diffTracked.Count -gt 0) {
        $diffArguments = @(
            'diff', '--no-ext-diff', '--no-color', '--unified=0',
            $BaseRef, '--'
        ) + $diffTracked
        $diffLines = @(Invoke-ReadOnlyGit -Root $root -Arguments $diffArguments)
        $currentPath = ""
        $newLineNumber = 0
        $inHunk = $false
        foreach ($line in $diffLines) {
            if ($line -match '^diff --git a/(\S+) b/(\S+)$') {
                $currentPath = Normalize-RepositoryPath -PathValue $Matches[2]
                $inHunk = $false
                continue
            }
            if ($line -match '^\+\+\+ b/(.+)$') {
                $currentPath = Normalize-RepositoryPath -PathValue $Matches[1]
                $inHunk = $false
                continue
            }
            if ($line -match '^@@ -[0-9]+(?:,[0-9]+)? \+([0-9]+)(?:,[0-9]+)? @@') {
                $newLineNumber = [int]$Matches[1]
                $inHunk = $true
                continue
            }
            if ($line -match '^Binary files .+ differ$') {
                if ($binaryContractByPath.ContainsKey($currentPath)) {
                    continue
                }
                $key = "${currentPath}:0:0:binary_diff_unscanned"
                if ($findingKeys.Add($key)) {
                    $findings.Add((New-Finding -PathValue $currentPath `
                        -LineNumber 0 -ColumnNumber 0 `
                        -Kind 'binary_diff_unscanned' -MatchedValue $line))
                }
                continue
            }
            if (-not $inHunk) {
                continue
            }
            if ($line.StartsWith('+') -and -not $line.StartsWith('+++')) {
                Test-AddedLine -PathValue $currentPath `
                    -LineNumber $newLineNumber -Text $line.Substring(1) `
                    -Patterns $patterns -Findings $findings `
                    -FindingKeys $findingKeys
                $newLineNumber++
            }
            elseif ($line.StartsWith('-') -or $line.StartsWith('\')) {
                continue
            }
            else {
                $newLineNumber++
            }
        }
    }

    foreach ($pathValue in $untracked) {
        $fullPath = Join-Path $root ($pathValue.Replace('/', [System.IO.Path]::DirectorySeparatorChar))
        if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
            continue
        }
        $bytes = [System.IO.File]::ReadAllBytes($fullPath)
        if ($bytes.Length -gt 5MB -or $bytes -contains [byte]0) {
            $key = "${pathValue}:0:0:untracked_binary_or_large_unscanned"
            if ($findingKeys.Add($key)) {
                $findings.Add((New-Finding -PathValue $pathValue `
                    -LineNumber 0 -ColumnNumber 0 `
                    -Kind 'untracked_binary_or_large_unscanned' `
                    -MatchedValue "${pathValue}:$($bytes.Length)"))
            }
            continue
        }
        $text = [System.Text.Encoding]::UTF8.GetString($bytes)
        $lines = [regex]::Split($text, "\r?\n")
        for ($i = 0; $i -lt $lines.Count; $i++) {
            Test-AddedLine -PathValue $pathValue -LineNumber ($i + 1) `
                -Text $lines[$i] -Patterns $patterns -Findings $findings `
                -FindingKeys $findingKeys
        }
    }

    $result.expected_files = $expectedSorted
    $result.changed_files = $changed
    $result.missing_files = $missing
    $result.unexpected_files = $unexpected
    $result.forbidden_files = $forbidden
    $result.sensitive_findings = @($findings | ForEach-Object { $_ })
    $result.error_count = $missing.Count + $unexpected.Count + `
        $forbidden.Count + $findings.Count

    if ($result.error_count -eq 0) {
        $result.status = "ok"
        $exitCode = 0
    }
    else {
        $result.status = "failed"
        $exitCode = 2
    }
}
catch {
    $result.status = "error"
    $result.error = $_.Exception.Message
    $result.error_count = 1
    $exitCode = 3
}

[Console]::Out.WriteLine(($result | ConvertTo-Json -Depth 8 -Compress))
exit $exitCode
