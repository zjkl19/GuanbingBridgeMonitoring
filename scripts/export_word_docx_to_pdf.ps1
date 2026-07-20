[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$DocxPath,
    [Parameter(Mandatory = $true)][string]$PdfPath
)

$ErrorActionPreference = 'Stop'
$word = $null
$document = $null

function Release-ComObject {
    param($Value)
    if ($null -ne $Value -and [Runtime.InteropServices.Marshal]::IsComObject($Value)) {
        [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($Value)
    }
}

try {
    $docxFull = [IO.Path]::GetFullPath($DocxPath)
    $pdfFull = [IO.Path]::GetFullPath($PdfPath)
    if (-not (Test-Path -LiteralPath $docxFull -PathType Leaf)) {
        throw "DOCX does not exist: $docxFull"
    }
    if (Test-Path -LiteralPath $pdfFull) {
        throw "PDF target already exists: $pdfFull"
    }

    $word = New-Object -ComObject Word.Application
    $word.Visible = $false
    $word.DisplayAlerts = 0
    $word.ScreenUpdating = $false
    try { $word.AutomationSecurity = 3 } catch { }
    $document = $word.Documents.Open($docxFull, $false, $true, $false)
    [void]$document.Repaginate()
    $pageCount = [int]$document.ComputeStatistics(2)
    $wordVersion = [string]$word.Version

    # wdFormatPDF=17.  SaveAs2 is intentionally isolated in a fresh
    # PowerShell/COM apartment; Office 16 can spin indefinitely when PDF
    # export follows a large TOC/field update in the same automation process.
    [void]$document.SaveAs2($pdfFull, 17)
    if (-not (Test-Path -LiteralPath $pdfFull -PathType Leaf)) {
        throw "Microsoft Word did not create the PDF: $pdfFull"
    }
    $pdf = Get-Item -LiteralPath $pdfFull
    if ($pdf.Length -le 0) {
        throw "Microsoft Word created an empty PDF: $pdfFull"
    }

    [ordered]@{
        status = 'ok'
        exporter = 'Microsoft Word COM SaveAs2 PDF (isolated process)'
        word_version = $wordVersion
        page_count = $pageCount
        pdf_path = $pdfFull
        pdf_bytes = $pdf.Length
        pdf_sha256 = (Get-FileHash -LiteralPath $pdfFull -Algorithm SHA256).Hash
    } | ConvertTo-Json -Depth 4
}
finally {
    if ($null -ne $document) { try { [void]$document.Close($false) } catch { } }
    if ($null -ne $word) { try { [void]$word.Quit() } catch { } }
    Release-ComObject -Value $document
    Release-ComObject -Value $word
    [GC]::Collect()
    [GC]::WaitForPendingFinalizers()
}
