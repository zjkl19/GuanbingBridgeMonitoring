SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;

SET NOCOUNT ON;

DECLARE @SrcTable SYSNAME = N'$(SrcTable)';
DECLARE @Start DATETIME = '$(Start)';
DECLARE @Finish DATETIME = '$(Finish)';
DECLARE @SpeedBins NVARCHAR(MAX) = N'$(SpeedBins)';

DECLARE @db SYSNAME = PARSENAME(@SrcTable, 3);
DECLARE @sc SYSNAME = PARSENAME(@SrcTable, 2);
DECLARE @tb SYSNAME = PARSENAME(@SrcTable, 1);
IF @db IS NULL OR @sc IS NULL OR @tb IS NULL
    THROW 50000, N'SrcTable must be 3-part name: Database.Schema.Table', 1;

IF OBJECT_ID('tempdb..#edges') IS NOT NULL DROP TABLE #edges;
CREATE TABLE #edges(ord INT IDENTITY(1,1), val FLOAT);
DECLARE @xml XML = N'<r><v>' + REPLACE(REPLACE(@SpeedBins, N'，', N','), N',', N'</v><v>') + N'</v></r>';
INSERT INTO #edges(val)
SELECT TRY_CAST(LTRIM(RTRIM(T.c.value('.', 'nvarchar(50)'))) AS float)
FROM @xml.nodes('/r/v') AS T(c)
WHERE LTRIM(RTRIM(T.c.value('.', 'nvarchar(50)'))) <> ''
  AND TRY_CAST(LTRIM(RTRIM(T.c.value('.', 'nvarchar(50)'))) AS float) IS NOT NULL;

IF OBJECT_ID('tempdb..#bins') IS NOT NULL DROP TABLE #bins;
DECLARE @max_ord INT = (SELECT MAX(ord) FROM #edges);
SELECT
    bin_id = e.ord,
    lo = e.val,
    hi = CASE WHEN e.ord = @max_ord - 1 THEN NULL ELSE nxt.val END,
    label = CASE WHEN e.ord = @max_ord - 1
                 THEN N'>=' + CONVERT(nvarchar(50), CAST(e.val AS int))
                 ELSE CONVERT(nvarchar(50), CAST(e.val AS int)) + N'-' + CONVERT(nvarchar(50), CAST(nxt.val AS int) - 1) END
INTO #bins
FROM #edges AS e
LEFT JOIN #edges AS nxt ON nxt.ord = e.ord + 1
WHERE e.ord < @max_ord;

IF OBJECT_ID('tempdb..#t') IS NOT NULL DROP TABLE #t;
CREATE TABLE #t
(
    Speed      INT         NULL,
    HSData_DT  DATETIME    NOT NULL
);

DECLARE @sql NVARCHAR(MAX) =
N'INSERT INTO #t (Speed, HSData_DT)
  SELECT Speed, HSData_DT
  FROM ' + QUOTENAME(@db) + N'.' + QUOTENAME(@sc) + N'.' + QUOTENAME(@tb) + N'
  WHERE HSData_DT IS NOT NULL
    AND HSData_DT >= @Start AND HSData_DT < @Finish;';

EXEC sp_executesql @sql, N'@Start DATETIME, @Finish DATETIME', @Start, @Finish;

SELECT
    b.bin_id,
    b.label,
    cnt = COUNT(t.Speed)
FROM #bins AS b
LEFT JOIN #t AS t
       ON t.Speed IS NOT NULL
      AND t.Speed >= b.lo
      AND (b.hi IS NULL OR t.Speed < b.hi)
GROUP BY b.bin_id, b.label
ORDER BY b.bin_id;

