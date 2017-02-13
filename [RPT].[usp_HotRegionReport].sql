USE [MCIODM]
GO

/****** Object:  StoredProcedure [RPT].[usp_HotRegionReport]  Script Date: 1/31/2017 2:43:58 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO



-- =============================================
-- Author:		Junwei Hu
-- Create date: 12Dec 2016
-- Description:	Populate hot region summary across Azure Resource Types
-- =============================================
ALTER PROCEDURE [RPT].[usp_HotRegionReport] 
(										  
	@ReportDate DATETIME
)

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

    -- Insert statements for procedure here

	--Get Summary Data for Compute for the specified report date
	(SELECT Geo, Region, TargetUtilization, Util, DtE, DtR, DtE - DtR As DtEMinusDtR, 'Compute' As ResourceType, NextETA, CASE 
	                                                                                                                           WHEN charindex('/',capacity,1) <> 0 THEN substring(capacity,1,charindex('/',capacity,1)-1) 
	                                                                                                                           ELSE null 
																														  END AS Usage, 																 
																														  CASE 
	                                                                                                                           WHEN charindex('/',capacity,1) <> 0 THEN substring(capacity,charindex('/',capacity,1)+1,len(capacity)) 
	                                                                                                                           ELSE null 
																														  END AS Capacity
	 FROM [RPT].[vwComputeCurrent_Weekly]		
	 WHERE  reportingweek = @ReportDate AND region <> 'Geo' AND geo <> 'World')

	 UNION

	 --Get Summary Data for Godzilla for the specified report date
	(SELECT Geo, Region, TargetUtilization, Util, DtE, DtR, DtE - DtR As DtEMinusDtR, 'Godzilla' As ResourceType, NextETA, CASE 
	                                                                                                                           WHEN charindex('/',capacity,1) <> 0 THEN substring(capacity,1,charindex('/',capacity,1)-1) 
	                                                                                                                           ELSE null 
																														   END AS Usage, 																 
																														   CASE 
	                                                                                                                           WHEN charindex('/',capacity,1) <> 0 THEN substring(capacity,charindex('/',capacity,1)+1,len(capacity)) 
	                                                                                                                           ELSE null 
																														   END AS Capacity
	 FROM [RPT].[vwGodzillaComputeCurrent_Weekly]		
	 WHERE  reportingweek = @ReportDate AND region <> 'Geo' AND geo <> 'World')

	 UNION

	 --Get Summary Data for HPC for the specified report date
	(SELECT Geo, Region, TargetUtilization, Util, DtE, DtR, DtE - DtR As DtEMinusDtR, 'HPC' As ResourceType, NextETA, CASE 
	                                                                                                                      WHEN charindex('/',capacity,1) <> 0 THEN substring(capacity,1,charindex('/',capacity,1)-1) 
	                                                                                                                      ELSE null 
																													  END AS Usage, 																 
																													  CASE 
	                                                                                                                      WHEN charindex('/',capacity,1) <> 0 THEN substring(capacity,charindex('/',capacity,1)+1,len(capacity)) 
	                                                                                                                      ELSE null 
																													  END AS Capacity
	 FROM [RPT].[vwHPCCurrent_Weekly]
	 WHERE  reportingweek = @ReportDate AND region <> 'Geo' AND geo <> 'World')

	 UNION

	 --Get Summary Data for SQL for the specified report date
	(SELECT Geo, Region, TargetUtilization, Util, DtE, DtR, DtE - DtR As DtEMinusDtR, 'SQL Azure' As ResourceType, NextETA, CASE WHEN charindex('(',Usage,1) <> 0 THEN substring(Usage,1,charindex('(',Usage,1)-1)
                                                                                                                      ELSE Usage 
																												      END AS Usage 
																												      , Capacity 
	 FROM [RPT].[vwSQLCurrent_Weekly]		
	 WHERE  reportingweek = @ReportDate AND region <> 'Geo' AND geo <> 'World') 

	 UNION
	 
	 --Get Summary Data for StorageGB for the specified report date
	 SELECT a.Geo, a.Region, a.TargetUtilization, b.AvgDayGBUtilization AS Util, a.DtE, a.DtR, a.DtE - a.DtR As DtEMinusDtR, 'Storage GB' As ResourceType, a.NextETA, b.SumRealUsage as Usage, b.SumAvailableUsage as Capacity 
	 FROM    
	(SELECT * 
     FROM [RPT].[vwStorageCurrent_Weekly]		
     WHERE  reportingweek = @ReportDate AND region <> 'Geo' AND geo <> 'World') a
	 left outer join 
	(SELECT Region, SUM(BillableStorage) AS SumRealUSAGE , SUM(AvailableUsage) AS SumAvailableUsage, (CASE WHEN (SUM(AvailableUsage) > 0 )THEN SUM(BillableStorage)/SUM(AvailableUsage) ELSE NULL END) AS AvgDayGBUtilization
     FROM [dbo].[vwStorageUsageGBStats] 
     WHERE FileDate = @ReportDate
     AND StorageType = 'Standard'
     GROUP BY Region) b
	 ON a.Region = b.Region

	 UNION

	 --Get Summary Data for StorageCPU for the specified report date
	 SELECT x.Geo, x.Region, x.TargetUtilization, x.Util, y.DaysLeft as DtE , x.DtR, y.DaysLeft - x.DtR As DtEMinusDtR, x.ResourceType, x.NextETA, x.Usage, x.Capacity
	 FROM	  
	(SELECT a.Geo, a.Region, a.TargetUtilization, b.AvgDayCPUUtilization AS Util, a.DtE, a.DtR, a.DtE - a.DtR As DtEMinusDtR, 'Storage CPU' As ResourceType, a.NextETA, b.SumDayACUUsed as Usage, b.SumDayACUTotal as Capacity 
	 FROM
    (SELECT * 
     FROM [RPT].[vwStorageCurrent_Weekly]		
     WHERE  reportingweek = @ReportDate AND region <> 'Geo' AND geo <> 'World') a
     LEFT OUTER JOIN 
    (SELECT Region, SUM(ACUUsed) AS SumDayACUUsed,  SUM(ACUTotal) AS SumDayACUTotal, (CASE WHEN (SUM(ACUTotal) >0 )THEN SUM(ACUUsed)/SUM(ACUTotal) ELSE NULL END) AS AvgDayCPUUtilization
     FROM [dbo].[vwStorageUsageCPUStats]
     WHERE FileDate  >= @ReportDate
     AND GeoSetup <> 'SECONDARY'
     AND FileDate < DATEADD(DAY, 1, @ReportDate)
     AND StorageType = 'Standard'
     GROUP BY Region) b
     ON a.Region = b.Region) x
	 LEFT OUTER JOIN
	 dbo.vw_StorageCPUDaysLin y
	 ON x.Region = y.Region

	 UNION

	 --Get Summary Data for XIOStorageGB for the specified report date
	 SELECT a.Geo, a.Region, a.TargetUtilization, b.AvgDayGBUtilization AS Util, a.DtE, a.DtR, a.DtE - a.DtR As DtEMinusDtR, 'XIO Storage GB' As ResourceType, a.NextETA, b.SumRealUsage as Usage, b.SumAvailableUsage as Capacity
	 FROM
    (SELECT * 
     FROM [RPT].[vwXIOStorageCurrent_Weekly]		
     WHERE  reportingweek = @ReportDate AND region <> 'Geo' AND geo <> 'World') a
     left outer join 
    (SELECT Region, SUM(BillableStorage) AS SumRealUSAGE , SUM(AvailableUsage) AS SumAvailableUsage, (CASE WHEN (SUM(AvailableUsage) >0 )THEN SUM(BillableStorage)/SUM(AvailableUsage) ELSE NULL END) AS AvgDayGBUtilization
     FROM [dbo].[vwStorageUsageGBStats] 
     WHERE FileDate = @ReportDate
     AND StorageType = 'Premium'
     GROUP BY Region) b
     ON a.Region = b.Region

	 UNION

	 --Get Summary Data for XIOStorageCPU for the specified report date
	 SELECT x.Geo, x.Region, x.TargetUtilization, x.Util, y.DaysLeft as DtE , x.DtR, y.DaysLeft - x.DtR As DtEMinusDtR, x.ResourceType, x.NextETA, x.Usage, x.Capacity
	 FROM
	(SELECT a.Geo, a.Region, a.TargetUtilization, b.AvgDayCPUUtilization AS Util, a.DtE, a.DtR, a.DtE - a.DtR As DtEMinusDtR, 'XIO Storage CPU' As ResourceType, a.NextETA, b.SumDayACUUsed as Usage, b.SumDayACUTotal as Capacity
	 FROM
    (SELECT * 
     FROM [RPT].[vwXIOStorageCurrent_Weekly]		
     WHERE  reportingweek = @ReportDate AND region <> 'Geo' AND geo <> 'World') a
     LEFT OUTER JOIN 
    (SELECT Region, SUM(ACUUsed) AS SumDayACUUsed,  SUM(ACUTotal) AS SumDayACUTotal,	(CASE WHEN (SUM(ACUTotal) >0 )THEN SUM(ACUUsed)/SUM(ACUTotal) ELSE NULL END) AS AvgDayCPUUtilization
     FROM [dbo].[vwStorageUsageCPUStats]
     WHERE FileDate  >= @ReportDate
     AND FileDate < DATEADD(DAY, 1, @ReportDate)
     AND StorageType = 'Premium'
     GROUP BY Region) b
     ON a.Region = b.Region) x
	 LEFT OUTER JOIN
	 dbo.vw_XIOStorageCPUDaysLin y
	 ON x.Region = y.Region

	 UNION

	 --Get Summary Data for XIOCompute for the specified report date
	(SELECT Geo, Region, TargetUtilization, Util, DtE, DtR, DtE - DtR As DtEMinusDtR, 'XIO Compute' As ResourceType, NextETA, CASE 
	                                                                                                                             WHEN charindex('/',capacity,1) <> 0 THEN substring(capacity,1,charindex('/',capacity,1)-1) 
	                                                                                                                             ELSE null 
																													         END AS Usage, 																 
																													         CASE 
	                                                                                                                             WHEN charindex('/',capacity,1) <> 0 THEN substring(capacity,charindex('/',capacity,1)+1,len(capacity)) 
	                                                                                                                             ELSE null 
																													         END AS Capacity 
	 FROM [RPT].[vwXIOComputeCurrent_Weekly]
	 WHERE  reportingweek = @ReportDate AND region <> 'Geo' AND geo <> 'World')

	 UNION

	 --Get Summary Data for GPUCompute for the specified report date
    (SELECT Geo, Region, TargetUtilization, Util, DtE, DtR, DtE - DtR As DtEMinusDtR, 'GPU Compute' As ResourceType, NextETA, CASE 
	                                                                                                                             WHEN charindex('/',capacity,1) <> 0 THEN substring(capacity,1,charindex('/',capacity,1)-1) 
	                                                                                                                             ELSE null 
																													         END AS Usage, 																 
																													         CASE 
	                                                                                                                             WHEN charindex('/',capacity,1) <> 0 THEN substring(capacity,charindex('/',capacity,1)+1,len(capacity)) 
	                                                                                                                             ELSE null 
																													         END AS Capacity 
	 FROM [RPT].[vwGPUComputeCurrent_Weekly]
	 WHERE  reportingweek = @ReportDate AND region <> 'Geo' AND geo <> 'World')

	 UNION

	 --Get Summary Data for GPURemote for the specified report date
	(SELECT Geo, Region, TargetUtilization, Util, DtE, DtR, DtE - DtR As DtEMinusDtR, 'GPU Remote Viz' As ResourceType, NextETA, CASE 
	                                                                                                                             WHEN charindex('/',capacity,1) <> 0 THEN substring(capacity,1,charindex('/',capacity,1)-1) 
	                                                                                                                             ELSE null 
																													        END AS Usage, 																 
																													        CASE 
	                                                                                                                             WHEN charindex('/',capacity,1) <> 0 THEN substring(capacity,charindex('/',capacity,1)+1,len(capacity)) 
	                                                                                                                             ELSE null 
																													        END AS Capacity 
	 FROM [RPT].[vwGPURemoteCurrent_Weekly]
	 WHERE  reportingweek = @ReportDate AND region <> 'Geo' AND geo <> 'World')

END

