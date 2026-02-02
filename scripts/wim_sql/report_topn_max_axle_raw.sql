SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;

SET NOCOUNT ON;

DECLARE @SrcTable SYSNAME = N'$(SrcTable)';
DECLARE @Start DATETIME = '$(Start)';
DECLARE @Finish DATETIME = '$(Finish)';
DECLARE @TopN INT = $(TopN);

DECLARE @db SYSNAME = PARSENAME(@SrcTable, 3);
DECLARE @sc SYSNAME = PARSENAME(@SrcTable, 2);
DECLARE @tb SYSNAME = PARSENAME(@SrcTable, 1);
IF @db IS NULL OR @sc IS NULL OR @tb IS NULL
    THROW 50000, N'SrcTable must be 3-part name: Database.Schema.Table', 1;

DECLARE @sql NVARCHAR(MAX) =
N';WITH Ranked AS (
    SELECT t.*, mx.max_axle
    FROM ' + QUOTENAME(@db) + N'.' + QUOTENAME(@sc) + N'.' + QUOTENAME(@tb) + N' AS t
    CROSS APPLY (
        SELECT MAX(v) AS max_axle
        FROM (VALUES
            (ISNULL(t.LWheel_1_W,0) + ISNULL(t.RWheel_1_W,0)),
            (ISNULL(t.LWheel_2_W,0) + ISNULL(t.RWheel_2_W,0)),
            (ISNULL(t.LWheel_3_W,0) + ISNULL(t.RWheel_3_W,0)),
            (ISNULL(t.LWheel_4_W,0) + ISNULL(t.RWheel_4_W,0)),
            (ISNULL(t.LWheel_5_W,0) + ISNULL(t.RWheel_5_W,0)),
            (ISNULL(t.LWheel_6_W,0) + ISNULL(t.RWheel_6_W,0)),
            (ISNULL(t.LWheel_7_W,0) + ISNULL(t.RWheel_7_W,0)),
            (ISNULL(t.LWheel_8_W,0) + ISNULL(t.RWheel_8_W,0))
        ) AS A(v)
    ) AS mx
    WHERE t.HSData_DT IS NOT NULL
      AND t.HSData_DT >= @Start AND t.HSData_DT < @Finish
)
SELECT TOP (' + CAST(@TopN AS nvarchar(20)) + N') *
FROM Ranked
ORDER BY max_axle DESC, HSData_DT ASC, HSData_Id ASC;';

EXEC sp_executesql @sql, N'@Start DATETIME, @Finish DATETIME', @Start, @Finish;

