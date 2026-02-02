SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;

SET NOCOUNT ON;

DECLARE @SrcTable SYSNAME = N'$(SrcTable)';
DECLARE @Start DATETIME = '$(Start)';
DECLARE @Finish DATETIME = '$(Finish)';
DECLARE @DesignTotal FLOAT = $(DesignTotal);
DECLARE @DesignAxle FLOAT = $(DesignAxle);
DECLARE @OverloadFactors NVARCHAR(MAX) = N'$(OverloadFactors)';

DECLARE @db SYSNAME = PARSENAME(@SrcTable, 3);
DECLARE @sc SYSNAME = PARSENAME(@SrcTable, 2);
DECLARE @tb SYSNAME = PARSENAME(@SrcTable, 1);
IF @db IS NULL OR @sc IS NULL OR @tb IS NULL
    THROW 50000, N'SrcTable must be 3-part name: Database.Schema.Table', 1;

IF OBJECT_ID('tempdb..#f') IS NOT NULL DROP TABLE #f;
CREATE TABLE #f(factor FLOAT);
DECLARE @xmlF XML = N'<r><v>' + REPLACE(REPLACE(@OverloadFactors, N'，', N','), N',', N'</v><v>') + N'</v></r>';
INSERT INTO #f(factor)
SELECT TRY_CAST(LTRIM(RTRIM(T.c.value('.', 'nvarchar(50)'))) AS float)
FROM @xmlF.nodes('/r/v') AS T(c)
WHERE LTRIM(RTRIM(T.c.value('.', 'nvarchar(50)'))) <> ''
  AND TRY_CAST(LTRIM(RTRIM(T.c.value('.', 'nvarchar(50)'))) AS float) IS NOT NULL;

IF OBJECT_ID('tempdb..#t') IS NOT NULL DROP TABLE #t;
CREATE TABLE #t
(
    Gross_Load INT NULL,
    max_axle INT NULL
);

DECLARE @sql NVARCHAR(MAX) =
N'INSERT INTO #t (Gross_Load, max_axle)
  SELECT
    Gross_Load,
    (SELECT MAX(v) FROM (VALUES
        (ISNULL(LWheel_1_W,0) + ISNULL(RWheel_1_W,0)),
        (ISNULL(LWheel_2_W,0) + ISNULL(RWheel_2_W,0)),
        (ISNULL(LWheel_3_W,0) + ISNULL(RWheel_3_W,0)),
        (ISNULL(LWheel_4_W,0) + ISNULL(RWheel_4_W,0)),
        (ISNULL(LWheel_5_W,0) + ISNULL(RWheel_5_W,0)),
        (ISNULL(LWheel_6_W,0) + ISNULL(RWheel_6_W,0)),
        (ISNULL(LWheel_7_W,0) + ISNULL(RWheel_7_W,0)),
        (ISNULL(LWheel_8_W,0) + ISNULL(RWheel_8_W,0))
    ) AS A(v))
  FROM ' + QUOTENAME(@db) + N'.' + QUOTENAME(@sc) + N'.' + QUOTENAME(@tb) + N'
  WHERE HSData_DT IS NOT NULL
    AND HSData_DT >= @Start AND HSData_DT < @Finish;';

EXEC sp_executesql @sql, N'@Start DATETIME, @Finish DATETIME', @Start, @Finish;

SELECT
    [type] = N'total',
    threshold_kg = CAST(@DesignTotal * f.factor AS float),
    count = SUM(CASE WHEN t.Gross_Load >= @DesignTotal * f.factor THEN 1 ELSE 0 END)
FROM #f AS f
CROSS JOIN #t AS t
GROUP BY f.factor

UNION ALL

SELECT
    [type] = N'axle',
    threshold_kg = CAST(@DesignAxle * f.factor AS float),
    count = SUM(CASE WHEN t.max_axle >= @DesignAxle * f.factor THEN 1 ELSE 0 END)
FROM #f AS f
CROSS JOIN #t AS t
GROUP BY f.factor

ORDER BY [type], threshold_kg;

