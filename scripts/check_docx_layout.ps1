param(
    [Parameter(Mandatory = $true)]
    [string]$DocxPath,

    [string]$OutputDir = "",

    [int]$TablePreviewCount = 20,

    [switch]$ExportPdf
)

$ErrorActionPreference = "Stop"

function Resolve-OutputDir {
    param([string]$PathValue, [string]$Docx)
    if ([string]::IsNullOrWhiteSpace($PathValue)) {
        return [System.IO.Path]::GetDirectoryName((Resolve-Path -LiteralPath $Docx).Path)
    }
    if (-not (Test-Path -LiteralPath $PathValue -PathType Container)) {
        New-Item -ItemType Directory -Path $PathValue | Out-Null
    }
    return (Resolve-Path -LiteralPath $PathValue).Path
}

$docx = (Resolve-Path -LiteralPath $DocxPath).Path
$outDir = Resolve-OutputDir -PathValue $OutputDir -Docx $docx
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$baseName = [System.IO.Path]::GetFileNameWithoutExtension($docx)
$jsonPath = Join-Path $outDir ("docx_layout_check_{0}_{1}.json" -f $baseName, $timestamp)
$txtPath = Join-Path $outDir ("docx_layout_check_{0}_{1}.txt" -f $baseName, $timestamp)
$pdfPath = Join-Path $outDir ("docx_layout_check_{0}_{1}.pdf" -f $baseName, $timestamp)

$word = $null
$doc = $null
try {
    $word = New-Object -ComObject Word.Application
    $word.Visible = $false
    $word.DisplayAlerts = 0
    $word.AutomationSecurity = 3
    $doc = $word.Documents.OpenNoRepairDialog($docx, $false, $true, $false)

    $wdStatisticPages = 2
    $pages = $doc.ComputeStatistics($wdStatisticPages)
    $tables = @()
    $maxTables = [Math]::Min($doc.Tables.Count, $TablePreviewCount)
    for ($i = 1; $i -le $maxTables; $i++) {
        $table = $doc.Tables.Item($i)
        $firstCell = ""
        try {
            $firstCell = ($table.Cell(1, 1).Range.Text -replace "[`r`a]", "").Trim()
        } catch {
            $firstCell = ""
        }
        $page = $null
        try {
            $page = $table.Range.Information(3)
        } catch {
            $page = $null
        }
        $tables += [ordered]@{
            index = $i
            page = $page
            rows = $table.Rows.Count
            columns = $table.Columns.Count
            first_cell = $firstCell
        }
    }

    if ($ExportPdf) {
        $wdExportFormatPDF = 17
        $doc.ExportAsFixedFormat($pdfPath, $wdExportFormatPDF)
    }

    $payload = [ordered]@{
        checked_at = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        docx_path = $docx
        page_count = $pages
        table_count = $doc.Tables.Count
        inline_shape_count = $doc.InlineShapes.Count
        shape_count = $doc.Shapes.Count
        table_preview_count = $maxTables
        tables = $tables
        pdf_path = $(if ($ExportPdf) { $pdfPath } else { "" })
    }

    $payload | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
    $lines = @(
        "检查时间: $($payload.checked_at)",
        "文档: $docx",
        "页数: $pages",
        "表格数: $($doc.Tables.Count)",
        "内嵌图片数: $($doc.InlineShapes.Count)",
        "浮动图形数: $($doc.Shapes.Count)",
        "表格预览:"
    )
    foreach ($table in $tables) {
        $lines += ("- #{0}: page={1}, rows={2}, cols={3}, first_cell={4}" -f $table.index, $table.page, $table.rows, $table.columns, $table.first_cell)
    }
    if ($ExportPdf) {
        $lines += "PDF: $pdfPath"
    }
    $lines | Set-Content -LiteralPath $txtPath -Encoding UTF8

    Write-Host "Layout check TXT: $txtPath"
    Write-Host "Layout check JSON: $jsonPath"
    if ($ExportPdf) {
        Write-Host "Layout check PDF: $pdfPath"
    }
} finally {
    if ($doc -ne $null) {
        $doc.Close($false) | Out-Null
    }
    if ($word -ne $null) {
        $word.Quit() | Out-Null
    }
}
