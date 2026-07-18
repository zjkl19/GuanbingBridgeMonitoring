[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$DocxPath,

    [string]$PdfPath = "",

    [string]$ReceiptPath = "",

    [string]$StatusPath = ""
)

$ErrorActionPreference = 'Stop'

function Get-Sha256Hex {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Release-ComObject {
    param($Value)
    if ($null -ne $Value -and [System.Runtime.InteropServices.Marshal]::IsComObject($Value)) {
        [void][System.Runtime.InteropServices.Marshal]::FinalReleaseComObject($Value)
    }
}

function Publish-AtomicJson {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Value
    )
    $json = $Value | ConvertTo-Json -Depth 8
    $tmp = $Path + '.tmp.' + $PID + '.' + [Guid]::NewGuid().ToString('N')
    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($tmp, $json, $encoding)
    try {
        if (Test-Path -LiteralPath $Path -PathType Leaf) {
            [System.IO.File]::Replace($tmp, $Path, $null)
        }
        else {
            [System.IO.File]::Move($tmp, $Path)
        }
    }
    finally {
        if (Test-Path -LiteralPath $tmp -PathType Leaf) {
            Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        }
    }
}

function Publish-AtomicFile {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination
    )
    if (Test-Path -LiteralPath $Destination -PathType Leaf) {
        [System.IO.File]::Replace($Source, $Destination, $null)
    }
    else {
        [System.IO.File]::Move($Source, $Destination)
    }
}

function Write-Stage {
    param(
        [Parameter(Mandatory = $true)][string]$Stage,
        [hashtable]$Extra = @{}
    )
    $payload = [ordered]@{
        status = 'running'
        stage = $Stage
        updated_at = [DateTimeOffset]::Now.ToString('o')
        process_id = $PID
        run_id = $runId
        elapsed_seconds = [Math]::Round(([DateTimeOffset]::Now - $startedAt).TotalSeconds, 3)
    }
    foreach ($key in $Extra.Keys) {
        $payload[$key] = $Extra[$key]
    }
    Publish-AtomicJson -Path $statusFull -Value $payload
}

$docxFull = [System.IO.Path]::GetFullPath($DocxPath)
if (-not (Test-Path -LiteralPath $docxFull -PathType Leaf)) {
    throw "DOCX does not exist: $docxFull"
}

if ([string]::IsNullOrWhiteSpace($PdfPath)) {
    $PdfPath = [System.IO.Path]::ChangeExtension($docxFull, '.pdf')
}
$pdfFull = [System.IO.Path]::GetFullPath($PdfPath)

if ([string]::IsNullOrWhiteSpace($ReceiptPath)) {
    $ReceiptPath = [System.IO.Path]::ChangeExtension($docxFull, '.word_export_receipt.json')
}
$receiptFull = [System.IO.Path]::GetFullPath($ReceiptPath)

if ([string]::IsNullOrWhiteSpace($StatusPath)) {
    $StatusPath = [System.IO.Path]::ChangeExtension($docxFull, '.word_export_status.json')
}
$statusFull = [System.IO.Path]::GetFullPath($StatusPath)

$pdfDir = Split-Path -Parent $pdfFull
$receiptDir = Split-Path -Parent $receiptFull
New-Item -ItemType Directory -Path $pdfDir -Force | Out-Null
New-Item -ItemType Directory -Path $receiptDir -Force | Out-Null
New-Item -ItemType Directory -Path (Split-Path -Parent $statusFull) -Force | Out-Null

$runId = [Guid]::NewGuid().ToString('N')
$tempPdf = Join-Path $pdfDir (([System.IO.Path]::GetFileNameWithoutExtension($pdfFull)) + '.tmp.' + $runId + '.pdf')
$tempDocx = Join-Path (Split-Path -Parent $docxFull) (([System.IO.Path]::GetFileNameWithoutExtension($docxFull)) + '.tmp.' + $runId + '.docx')
$docxHashBefore = Get-Sha256Hex -Path $docxFull
$startedAt = [DateTimeOffset]::Now
Copy-Item -LiteralPath $docxFull -Destination $tempDocx

$word = $null
$document = $null
$story = $null
$nextStory = $null
$headers = $null
$footers = $null
$shapes = $null
$textFrame = $null
$textRange = $null

try {
    Write-Stage -Stage 'starting'
    $word = New-Object -ComObject Word.Application
    $word.Visible = $false
    $word.DisplayAlerts = 0
    $word.ScreenUpdating = $false
    try { $word.AutomationSecurity = 3 } catch { }

    # Work on an isolated sibling. If Word blocks or fails, the operator's
    # original DOCX and any previously accepted PDF remain unchanged.
    $document = $word.Documents.Open($tempDocx, $false, $false, $false)
    Write-Stage -Stage 'document_opened' -Extra @{ pages_before = [int]$document.ComputeStatistics(2) }

    # Update main-story fields first.
    if ($document.Fields.Count -gt 0) {
        [void]$document.Fields.Update()
    }
    Write-Stage -Stage 'main_fields_updated' -Extra @{ main_story_fields = [int]$document.Fields.Count }

    # Update only the finite, indexed header/footer collections. Avoid walking
    # NextStoryRange chains: some Word builds can cycle linked headers forever.
    for ($sectionIndex = 1; $sectionIndex -le $document.Sections.Count; $sectionIndex++) {
        $section = $document.Sections.Item($sectionIndex)
        foreach ($collectionName in @('Headers', 'Footers')) {
            $collection = $section.$collectionName
            for ($itemIndex = 1; $itemIndex -le 3; $itemIndex++) {
                $item = $collection.Item($itemIndex)
                if ($item.Exists) {
                    if ($item.Range.Fields.Count -gt 0) {
                        [void]$item.Range.Fields.Update()
                    }
                    for ($shapeIndex = 1; $shapeIndex -le $item.Shapes.Count; $shapeIndex++) {
                        $shape = $item.Shapes.Item($shapeIndex)
                        try {
                            if ($shape.TextFrame.HasText -ne 0) {
                                $textRange = $shape.TextFrame.TextRange
                                if ($textRange.Fields.Count -gt 0) {
                                    [void]$textRange.Fields.Update()
                                }
                            }
                        } catch { }
                        Release-ComObject -Value $textRange
                        $textRange = $null
                        Release-ComObject -Value $shape
                    }
                }
                Release-ComObject -Value $item
            }
            Release-ComObject -Value $collection
        }
        Release-ComObject -Value $section
    }
    Write-Stage -Stage 'header_footer_fields_updated' -Extra @{ section_count = [int]$document.Sections.Count }

    for ($index = 1; $index -le $document.TablesOfContents.Count; $index++) {
        $toc = $document.TablesOfContents.Item($index)
        [void]$toc.Update()
        Release-ComObject -Value $toc
    }
    for ($index = 1; $index -le $document.TablesOfFigures.Count; $index++) {
        $tof = $document.TablesOfFigures.Item($index)
        [void]$tof.Update()
        Release-ComObject -Value $tof
    }
    for ($index = 1; $index -le $document.TablesOfAuthorities.Count; $index++) {
        $toa = $document.TablesOfAuthorities.Item($index)
        [void]$toa.Update()
        Release-ComObject -Value $toa
    }
    Write-Stage -Stage 'tables_of_contents_updated' -Extra @{
        toc_count = [int]$document.TablesOfContents.Count
        tof_count = [int]$document.TablesOfFigures.Count
        toa_count = [int]$document.TablesOfAuthorities.Count
    }

    # Generated indexes can change pagination. Refresh header/footer PAGE,
    # NUMPAGES and PAGEREF fields again against the final layout generation.
    [void]$document.Repaginate()
    for ($sectionIndex = 1; $sectionIndex -le $document.Sections.Count; $sectionIndex++) {
        $section = $document.Sections.Item($sectionIndex)
        foreach ($collectionName in @('Headers', 'Footers')) {
            $collection = $section.$collectionName
            for ($itemIndex = 1; $itemIndex -le 3; $itemIndex++) {
                $item = $collection.Item($itemIndex)
                if ($item.Exists) {
                    if ($item.Range.Fields.Count -gt 0) {
                        [void]$item.Range.Fields.Update()
                    }
                    for ($shapeIndex = 1; $shapeIndex -le $item.Shapes.Count; $shapeIndex++) {
                        $shape = $item.Shapes.Item($shapeIndex)
                        try {
                            if ($shape.TextFrame.HasText -ne 0) {
                                $textRange = $shape.TextFrame.TextRange
                                if ($textRange.Fields.Count -gt 0) {
                                    [void]$textRange.Fields.Update()
                                }
                            }
                        } catch { }
                        Release-ComObject -Value $textRange
                        $textRange = $null
                        Release-ComObject -Value $shape
                    }
                }
                Release-ComObject -Value $item
            }
            Release-ComObject -Value $collection
        }
        Release-ComObject -Value $section
    }
    [void]$document.Repaginate()
    Write-Stage -Stage 'repaginated_before_save' -Extra @{
        pages = [int]$document.ComputeStatistics(2)
        revisions_preserved = [int]$document.Revisions.Count
    }
    [void]$document.Save()
    Write-Stage -Stage 'document_saved'
    [void]$document.Repaginate()

    $pageCount = [int]$document.ComputeStatistics(2)
    $tableCount = [int]$document.Tables.Count
    $inlineShapeCount = [int]$document.InlineShapes.Count
    $shapeCount = [int]$document.Shapes.Count
    $fieldCount = [int]$document.Fields.Count

    # wdExportFormatPDF=17, wdExportOptimizeForPrint=0, wdExportAllDocument=0,
    # wdExportDocumentContent=0, bitmapMissingFonts=true, PDF/A=false.
    Write-Stage -Stage 'exporting_pdf' -Extra @{ pages = $pageCount }
    $document.ExportAsFixedFormat($tempPdf, 17, $false, 0, 0, 1, 1, 0, $true, $true, 1, $true, $true, $false)
    Write-Stage -Stage 'pdf_exported'

    [void]$document.Close($false)
    Release-ComObject -Value $document
    $document = $null
    [void]$word.Quit()
    Release-ComObject -Value $word
    $word = $null

    if (-not (Test-Path -LiteralPath $tempPdf -PathType Leaf)) {
        throw "Microsoft Word did not create the PDF: $tempPdf"
    }
    if ((Get-Item -LiteralPath $tempPdf).Length -le 0) {
        throw "Microsoft Word created an empty PDF: $tempPdf"
    }

    # Both temporary artifacts are complete before either official path moves.
    # The receipt is written only after both same-volume atomic promotions.
    Publish-AtomicFile -Source $tempDocx -Destination $docxFull
    Publish-AtomicFile -Source $tempPdf -Destination $pdfFull

    $receipt = [ordered]@{
        status = 'ok'
        authoritative = $true
        run_id = $runId
        exporter = 'Microsoft Word COM ExportAsFixedFormat'
        started_at = $startedAt.ToString('o')
        completed_at = [DateTimeOffset]::Now.ToString('o')
        docx_path = $docxFull
        docx_bytes = (Get-Item -LiteralPath $docxFull).Length
        docx_sha256_before = $docxHashBefore
        docx_sha256_after = Get-Sha256Hex -Path $docxFull
        pdf_path = $pdfFull
        pdf_bytes = (Get-Item -LiteralPath $pdfFull).Length
        pdf_sha256 = Get-Sha256Hex -Path $pdfFull
        page_count = $pageCount
        table_count = $tableCount
        inline_shape_count = $inlineShapeCount
        shape_count = $shapeCount
        main_story_field_count = $fieldCount
    }
    Publish-AtomicJson -Path $receiptFull -Value $receipt
    $completed = [ordered]@{
        status = 'ok'
        stage = 'completed'
        updated_at = [DateTimeOffset]::Now.ToString('o')
        process_id = $PID
        run_id = $runId
        receipt_path = $receiptFull
        pdf_path = $pdfFull
    }
    Publish-AtomicJson -Path $statusFull -Value $completed
    $receipt | ConvertTo-Json -Depth 5
}
catch {
    $failed = [ordered]@{
        status = 'failed'
        stage = 'failed'
        updated_at = [DateTimeOffset]::Now.ToString('o')
        process_id = $PID
        run_id = $runId
        error = $_.Exception.ToString()
    }
    try { Publish-AtomicJson -Path $statusFull -Value $failed } catch { }
    throw
}
finally {
    if ($null -ne $document) {
        try { [void]$document.Close($false) } catch { }
    }
    if ($null -ne $word) {
        try { [void]$word.Quit() } catch { }
    }
    Release-ComObject -Value $textRange
    Release-ComObject -Value $textFrame
    Release-ComObject -Value $shapes
    Release-ComObject -Value $footers
    Release-ComObject -Value $headers
    Release-ComObject -Value $nextStory
    Release-ComObject -Value $story
    Release-ComObject -Value $document
    Release-ComObject -Value $word
    if (Test-Path -LiteralPath $tempPdf) {
        Remove-Item -LiteralPath $tempPdf -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path -LiteralPath $tempDocx) {
        Remove-Item -LiteralPath $tempDocx -Force -ErrorAction SilentlyContinue
    }
    [GC]::Collect()
    [GC]::WaitForPendingFinalizers()
}
