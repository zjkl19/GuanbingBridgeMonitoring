SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;

SET NOCOUNT ON;

DECLARE @SrcTable SYSNAME = N'$(SrcTable)';
DECLARE @Start DATETIME = '$(Start)';
DECLARE @Finish DATETIME = '$(Finish)';
DECLARE @LaneText NVARCHAR(MAX) = N'$(LaneText)';

DECLARE @db SYSNAME = PARSENAME(@SrcTable, 3);
DECLARE @sc SYSNAME = PARSENAME(@SrcTable, 2);
DECLARE @tb SYSNAME = PARSENAME(@SrcTable, 1);
IF @db IS NULL OR @sc IS NULL OR @tb IS NULL
    THROW 50000, N'SrcTable must be 3-part name: Database.Schema.Table', 1;

IF OBJECT_ID('tempdb..#lanes') IS NOT NULL DROP TABLE #lanes;
CREATE TABLE #lanes(ord INT IDENTITY(1,1), lane INT);
DECLARE @lane_xml XML = N'<r><v>' + REPLACE(REPLACE(@LaneText, N'，', N','), N',', N'</v><v>') + N'</v></r>';
INSERT INTO #lanes(lane)
SELECT TRY_CAST(LTRIM(RTRIM(T.c.value('.', 'nvarchar(20)'))) AS int)
FROM @lane_xml.nodes('/r/v') AS T(c)
WHERE LTRIM(RTRIM(T.c.value('.', 'nvarchar(20)'))) <> ''
  AND TRY_CAST(LTRIM(RTRIM(T.c.value('.', 'nvarchar(20)'))) AS int) IS NOT NULL;

IF OBJECT_ID('tempdb..#t') IS NOT NULL DROP TABLE #t;
CREATE TABLE #t
(
    Lane_Id   INT         NULL,
    HSData_DT DATETIME    NOT NULL
);

DECLARE @sql NVARCHAR(MAX) =
N'INSERT INTO #t (Lane_Id, HSData_DT)
  SELECT Lane_Id, HSData_DT
  FROM ' + QUOTENAME(@db) + N'.' + QUOTENAME(@sc) + N'.' + QUOTENAME(@tb) + N'
  WHERE HSData_DT IS NOT NULL
    AND HSData_DT >= @Start AND HSData_DT < @Finish;';

EXEC sp_executesql @sql, N'@Start DATETIME, @Finish DATETIME', @Start, @Finish;

SELECT
    l.lane,
    cnt = COUNT(t.HSData_DT)
FROM #lanes AS l
LEFT JOIN #t AS t ON t.Lane_Id = l.lane
GROUP BY l.ord, l.lane
ORDER BY l.ord;

