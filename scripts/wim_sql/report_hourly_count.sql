SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;

SET NOCOUNT ON;

DECLARE @SrcTable SYSNAME = N'$(SrcTable)';
DECLARE @Start DATETIME = '$(Start)';
DECLARE @Finish DATETIME = '$(Finish)';
DECLARE @HourBins NVARCHAR(MAX) = N'$(HourBins)';

DECLARE @db SYSNAME = PARSENAME(@SrcTable, 3);
DECLARE @sc SYSNAME = PARSENAME(@SrcTable, 2);
DECLARE @tb SYSNAME = PARSENAME(@SrcTable, 1);
IF @db IS NULL OR @sc IS NULL OR @tb IS NULL
    THROW 50000, N'SrcTable must be 3-part name: Database.Schema.Table', 1;

IF OBJECT_ID('tempdb..#edges') IS NOT NULL DROP TABLE #edges;
CREATE TABLE #edges(ord INT IDENTITY(1,1), val INT);
DECLARE @xml XML = N'<r><v>' + REPLACE(REPLACE(@HourBins, N'，', N','), N',', N'</v><v>') + N'</v></r>';
INSERT INTO #edges(val)
SELECT TRY_CAST(LTRIM(RTRIM(T.c.value('.', 'nvarchar(20)'))) AS int)
FROM @xml.nodes('/r/v') AS T(c)
WHERE LTRIM(RTRIM(T.c.value('.', 'nvarchar(20)'))) <> ''
  AND TRY_CAST(LTRIM(RTRIM(T.c.value('.', 'nvarchar(20)'))) AS int) IS NOT NULL;

IF OBJECT_ID('tempdb..#bins') IS NOT NULL DROP TABLE #bins;
DECLARE @max_ord INT = (SELECT MAX(ord) FROM #edges);
SELECT
    bin_id = e.ord,
    lo = e.val,
    hi = CASE WHEN e.ord = @max_ord - 1 THEN NULL ELSE nxt.val END,
    label = CASE WHEN e.ord = @max_ord - 1
                 THEN N'>=' + CONVERT(nvarchar(20), e.val)
                 ELSE CONVERT(nvarchar(20), e.val) + N'-' + CONVERT(nvarchar(20), nxt.val - 1) END
INTO #bins
FROM #edges AS e
LEFT JOIN #edges AS nxt ON nxt.ord = e.ord + 1
WHERE e.ord < @max_ord;

IF OBJECT_ID('tempdb..#t') IS NOT NULL DROP TABLE #t;
CREATE TABLE #t
(
    hh INT NOT NULL
);

DECLARE @sql NVARCHAR(MAX) =
N'INSERT INTO #t (hh)
  SELECT DATEPART(HOUR, HSData_DT)
  FROM ' + QUOTENAME(@db) + N'.' + QUOTENAME(@sc) + N'.' + QUOTENAME(@tb) + N'
  WHERE HSData_DT IS NOT NULL
    AND HSData_DT >= @Start AND HSData_DT < @Finish;';

EXEC sp_executesql @sql, N'@Start DATETIME, @Finish DATETIME', @Start, @Finish;

SELECT
    b.bin_id,
    b.label,
    cnt = COUNT(t.hh)
FROM #bins AS b
LEFT JOIN #t AS t
       ON t.hh >= b.lo
      AND (b.hi IS NULL OR t.hh < b.hi)
GROUP BY b.bin_id, b.label
ORDER BY b.bin_id;

