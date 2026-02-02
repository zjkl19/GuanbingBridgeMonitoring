SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;

SET NOCOUNT ON;

DECLARE @SrcTable SYSNAME = N'$(SrcTable)';
DECLARE @Start DATETIME = '$(Start)';
DECLARE @Finish DATETIME = '$(Finish)';
DECLARE @CustomWeights NVARCHAR(MAX) = N'$(CustomWeights)';

DECLARE @db SYSNAME = PARSENAME(@SrcTable, 3);
DECLARE @sc SYSNAME = PARSENAME(@SrcTable, 2);
DECLARE @tb SYSNAME = PARSENAME(@SrcTable, 1);
IF @db IS NULL OR @sc IS NULL OR @tb IS NULL
    THROW 50000, N'SrcTable must be 3-part name: Database.Schema.Table', 1;

IF OBJECT_ID('tempdb..#weights') IS NOT NULL DROP TABLE #weights;
CREATE TABLE #weights(weight_threshold FLOAT);
DECLARE @xml XML = N'<r><v>' + REPLACE(REPLACE(@CustomWeights, N'，', N','), N',', N'</v><v>') + N'</v></r>';
INSERT INTO #weights(weight_threshold)
SELECT TRY_CAST(LTRIM(RTRIM(T.c.value('.', 'nvarchar(50)'))) AS float)
FROM @xml.nodes('/r/v') AS T(c)
WHERE LTRIM(RTRIM(T.c.value('.', 'nvarchar(50)'))) <> ''
  AND TRY_CAST(LTRIM(RTRIM(T.c.value('.', 'nvarchar(50)'))) AS float) IS NOT NULL;

IF OBJECT_ID('tempdb..#t') IS NOT NULL DROP TABLE #t;
CREATE TABLE #t
(
    Gross_Load INT NULL
);

DECLARE @sql NVARCHAR(MAX) =
N'INSERT INTO #t (Gross_Load)
  SELECT Gross_Load
  FROM ' + QUOTENAME(@db) + N'.' + QUOTENAME(@sc) + N'.' + QUOTENAME(@tb) + N'
  WHERE HSData_DT IS NOT NULL
    AND HSData_DT >= @Start AND HSData_DT < @Finish;';

EXEC sp_executesql @sql, N'@Start DATETIME, @Finish DATETIME', @Start, @Finish;

SELECT
    w.weight_threshold,
    over_cnt = COUNT(t.Gross_Load)
FROM #weights AS w
LEFT JOIN #t AS t
       ON t.Gross_Load >= w.weight_threshold
GROUP BY w.weight_threshold
ORDER BY w.weight_threshold;

