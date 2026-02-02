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

IF OBJECT_ID('tempdb..#t') IS NOT NULL DROP TABLE #t;
CREATE TABLE #t
(
    HSData_Id     INT          NULL,
    Lane_Id       INT          NULL,
    HSData_DT     DATETIME     NOT NULL,
    Axle_Num      INT          NULL,
    Gross_Load    INT          NULL,
    Speed         INT          NULL,
    License_Plate NVARCHAR(50) NULL,
    LWheel_1_W INT NULL, RWheel_1_W INT NULL,
    LWheel_2_W INT NULL, RWheel_2_W INT NULL,
    LWheel_3_W INT NULL, RWheel_3_W INT NULL,
    LWheel_4_W INT NULL, RWheel_4_W INT NULL,
    LWheel_5_W INT NULL, RWheel_5_W INT NULL,
    LWheel_6_W INT NULL, RWheel_6_W INT NULL,
    LWheel_7_W INT NULL, RWheel_7_W INT NULL,
    LWheel_8_W INT NULL, RWheel_8_W INT NULL,
    AxleDis1 INT NULL, AxleDis2 INT NULL, AxleDis3 INT NULL,
    AxleDis4 INT NULL, AxleDis5 INT NULL, AxleDis6 INT NULL, AxleDis7 INT NULL
);

DECLARE @sql NVARCHAR(MAX) =
N'INSERT INTO #t
  SELECT
    HSData_Id, Lane_Id, HSData_DT, Axle_Num, Gross_Load, Speed, License_Plate,
    LWheel_1_W, RWheel_1_W, LWheel_2_W, RWheel_2_W, LWheel_3_W, RWheel_3_W,
    LWheel_4_W, RWheel_4_W, LWheel_5_W, RWheel_5_W, LWheel_6_W, RWheel_6_W,
    LWheel_7_W, RWheel_7_W, LWheel_8_W, RWheel_8_W,
    AxleDis1, AxleDis2, AxleDis3, AxleDis4, AxleDis5, AxleDis6, AxleDis7
  FROM ' + QUOTENAME(@db) + N'.' + QUOTENAME(@sc) + N'.' + QUOTENAME(@tb) + N'
  WHERE HSData_DT IS NOT NULL
    AND Gross_Load IS NOT NULL
    AND HSData_DT >= @Start AND HSData_DT < @Finish;';

EXEC sp_executesql @sql, N'@Start DATETIME, @Finish DATETIME', @Start, @Finish;

;WITH Ranked AS
(
    SELECT *,
           rn = ROW_NUMBER() OVER (ORDER BY Gross_Load DESC, HSData_DT ASC, HSData_Id ASC)
    FROM #t
)
SELECT TOP (@TopN)
    [rank] = rn,
    [lane] = Lane_Id,
    [time] = CONVERT(varchar(19), HSData_DT, 120),
    [axle_num] = Axle_Num,
    [gross_kg] = Gross_Load,
    [speed_kmh] = Speed,
    [plate] = License_Plate,
    [axle1] = ISNULL(LWheel_1_W,0) + ISNULL(RWheel_1_W,0),
    [axle2] = ISNULL(LWheel_2_W,0) + ISNULL(RWheel_2_W,0),
    [axle3] = ISNULL(LWheel_3_W,0) + ISNULL(RWheel_3_W,0),
    [axle4] = ISNULL(LWheel_4_W,0) + ISNULL(RWheel_4_W,0),
    [axle5] = ISNULL(LWheel_5_W,0) + ISNULL(RWheel_5_W,0),
    [axle6] = ISNULL(LWheel_6_W,0) + ISNULL(RWheel_6_W,0),
    [axle7] = ISNULL(LWheel_7_W,0) + ISNULL(RWheel_7_W,0),
    [axle8] = ISNULL(LWheel_8_W,0) + ISNULL(RWheel_8_W,0),
    [axledis1] = AxleDis1,
    [axledis2] = AxleDis2,
    [axledis3] = AxleDis3,
    [axledis4] = AxleDis4,
    [axledis5] = AxleDis5,
    [axledis6] = AxleDis6,
    [axledis7] = AxleDis7
FROM Ranked
ORDER BY rn;

