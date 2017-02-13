USE [MCIODM]
GO

/****** Object:  View [dbo].[vw_XIOStorageCPUDaysLin]    Script Date: 1/31/2017 1:52:42 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE VIEW [dbo].[vw_XIOStorageCPUDaysLin] AS


SELECT x.Region, CASE 
                        WHEN x.MinDate < [dbo].[fn_GetReportDate]() THEN 0
                        WHEN x.MinDate is NULL THEN datediff(dd, [dbo].[fn_GetReportDate](), y.MaxForecastDate)
						ELSE datediff(dd, [dbo].[fn_GetReportDate](), x.MinDate)
					    END  	 
                        AS DaysLeft
FROM 
(
     SELECT s.Region, min(t.ForecastDate) as MinDate 
     FROM
     (
	     Select * 
         From 
            (Select Cast(AggregatedUsage.FileDate as date) as [Date], 
                    AggregatedUsage.Region, 
	                Avg(AggregatedUsage.Usage) as Usage, 
	                Avg(AggregatedUsage.Capacity) as Capacity
             From
                 (Select LiveClusterUsage.FileDate, 
                         LiveClusterUsage.Region, 
	                     Sum(LiveClusterUsage.ACUUsed) as Usage, 
	                     Sum(LiveClusterUsage.ACUTotal) as Capacity
                  From (
		                 Select FileDate
	                           ,[Date]
                               ,az.[RegionCode] AS Region
	                           ,st.Tenant
                               ,st.[Cluster]
                               ,[StorageType]
                               ,[CPUUtilization]
                               ,[ACUUsed]
                               ,[ACUTotal]
	                           ,[GeoSetup]
                         From [dbo].[StorageUsageCPUStats] st
                         Inner join [dbo].[AzureClusters] az
                         On st.[Cluster] = az.[Cluster]
                         Where az.ClusterLIVEDateSource = 'Actual' AND az.IsIntentSellable = 'Sellable') LiveClusterUsage

                  Where StorageType = 'Premium'
                  Group by FileDate, Region) AggregatedUsage
             Group by Cast(FileDate as date), Region ) DailyAverageUsage
             Where DailyAverageUsage.[Date] = DateAdd(dd, -1, [dbo].[fn_GetReportDate]() )   ) s
  
      LEFT OUTER JOIN 
      (	SELECT * FROM [dbo].[XIOStorageCPUShorttermForecast] t (NOLOCK) WHERE ClusterType = 'XIO Storage') t
      
     ON 
	 s.Region = t.Region AND s.Capacity*0.6 <= t.ForecastValue
     GROUP BY 
	 s.Region
) x

inner join 

(
     SELECT s.Region, max(t.ForecastDate) as MaxForecastDate 
     FROM
     (
	      Select * 
         From 
            (Select Cast(AggregatedUsage.FileDate as date) as [Date], 
                    AggregatedUsage.Region, 
	                Avg(AggregatedUsage.Usage) as Usage, 
	                Avg(AggregatedUsage.Capacity) as Capacity
             From
                 (Select LiveClusterUsage.FileDate, 
                         LiveClusterUsage.Region, 
	                     Sum(LiveClusterUsage.ACUUsed) as Usage, 
	                     Sum(LiveClusterUsage.ACUTotal) as Capacity
                  From (
		                 Select FileDate
	                           ,[Date]
                               ,az.[RegionCode] AS Region
	                           ,st.Tenant
                               ,st.[Cluster]
                               ,[StorageType]
                               ,[CPUUtilization]
                               ,[ACUUsed]
                               ,[ACUTotal]
	                           ,[GeoSetup]
                         From [dbo].[StorageUsageCPUStats] st
                         Inner join [dbo].[AzureClusters] az
                         On st.[Cluster] = az.[Cluster]
                         Where az.ClusterLIVEDateSource = 'Actual' AND az.IsIntentSellable = 'Sellable') LiveClusterUsage

                  Where StorageType = 'Premium' 
                  Group by FileDate, Region) AggregatedUsage
             Group by Cast(FileDate as date), Region ) DailyAverageUsage
             Where DailyAverageUsage.[Date] = DateAdd(dd, -1, [dbo].[fn_GetReportDate]() )   
     ) s
     LEFT OUTER JOIN 
     (	SELECT * FROM [dbo].[XIOStorageCPUShorttermForecast] t (NOLOCK) WHERE ClusterType = 'XIO Storage') t
     
     ON 
	 s.Region = t.Region
     GROUP BY 
	 s.Region
) y

ON  x.Region = y.Region



GO


