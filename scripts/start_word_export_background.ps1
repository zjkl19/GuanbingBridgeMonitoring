[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$DocxPath,
    [string]$PdfPath = "",
    [string]$ReceiptPath = "",
    [string]$StatusPath = "",
    [string]$StdoutPath = "",
    [string]$StderrPath = "",
    [switch]$PlanOnly
)

$ErrorActionPreference = 'Stop'
$worker = Join-Path $PSScriptRoot 'update_word_fields_and_export_pdf.ps1'
$docxFull = [IO.Path]::GetFullPath($DocxPath)
$baseDir = Split-Path -Parent $docxFull

if (-not (Test-Path -LiteralPath $worker -PathType Leaf)) {
    throw "Word export worker does not exist: $worker"
}
if (-not (Test-Path -LiteralPath $docxFull -PathType Leaf)) {
    throw "DOCX does not exist: $docxFull"
}

if ([string]::IsNullOrWhiteSpace($PdfPath)) {
    $PdfPath = [IO.Path]::ChangeExtension($docxFull, '.pdf')
}
if ([string]::IsNullOrWhiteSpace($ReceiptPath)) {
    $ReceiptPath = [IO.Path]::ChangeExtension($docxFull, '.word_export_receipt.json')
}
if ([string]::IsNullOrWhiteSpace($StatusPath)) {
    $StatusPath = [IO.Path]::ChangeExtension($docxFull, '.word_export_status.json')
}
if ([string]::IsNullOrWhiteSpace($StdoutPath)) {
    $StdoutPath = Join-Path $baseDir 'word_export_stdout.log'
}
if ([string]::IsNullOrWhiteSpace($StderrPath)) {
    $StderrPath = Join-Path $baseDir 'word_export_stderr.log'
}

$pdfFull = [IO.Path]::GetFullPath($PdfPath)
$receiptFull = [IO.Path]::GetFullPath($ReceiptPath)
$statusFull = [IO.Path]::GetFullPath($StatusPath)
$stdoutFull = [IO.Path]::GetFullPath($StdoutPath)
$stderrFull = [IO.Path]::GetFullPath($StderrPath)
if ($stdoutFull -ieq $stderrFull) {
    throw 'StdoutPath and StderrPath must be different files.'
}
foreach ($path in @($pdfFull, $receiptFull, $statusFull, $stdoutFull, $stderrFull)) {
    $parent = Split-Path -Parent $path
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
}

function ConvertTo-QuotedProcessArgument {
    param([Parameter(Mandatory = $true)][string]$Value)
    # Windows file names cannot contain a double quote. Quoting every value
    # avoids Start-Process splitting paths that contain spaces or CJK text.
    return '"' + $Value.Replace('"', '\"') + '"'
}

$arguments = @(
    '-NoProfile',
    '-ExecutionPolicy', 'Bypass',
    '-File', $worker,
    '-DocxPath', $docxFull,
    '-PdfPath', $pdfFull,
    '-ReceiptPath', $receiptFull,
    '-StatusPath', $statusFull
)
$argumentString = ($arguments | ForEach-Object { ConvertTo-QuotedProcessArgument $_ }) -join ' '

$plan = [ordered]@{
    status = if ($PlanOnly) { 'planned' } else { 'starting' }
    worker_path = [IO.Path]::GetFullPath($worker)
    docx_path = $docxFull
    pdf_path = $pdfFull
    receipt_path = $receiptFull
    status_path = $statusFull
    stdout_path = $stdoutFull
    stderr_path = $stderrFull
    argument_string = $argumentString
}
if ($PlanOnly) {
    $plan | ConvertTo-Json -Depth 4
    return
}

$process = Start-Process `
    -FilePath 'powershell.exe' `
    -ArgumentList $argumentString `
    -WindowStyle Hidden `
    -RedirectStandardOutput $stdoutFull `
    -RedirectStandardError $stderrFull `
    -PassThru

[ordered]@{
    status = 'started'
    process_id = $process.Id
    started_at = $process.StartTime.ToString('o')
    worker_path = [IO.Path]::GetFullPath($worker)
    docx_path = $docxFull
    pdf_path = $pdfFull
    receipt_path = $receiptFull
    status_path = $statusFull
    stdout_path = $stdoutFull
    stderr_path = $stderrFull
} | ConvertTo-Json -Depth 4
