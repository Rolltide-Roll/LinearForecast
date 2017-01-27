Declare @NumDayHistory int = 30;
Declare @NumDayForecast int = 126;

Declare @HistoryEndDate Date = DATEADD(DD,-1,[dbo].[fn_GetReportDate]());
--Declare @HistoryEndDate Date = DATEADD(DD,-1,cast('2017-01-21' as Date));
Declare @HistoryStartDate Date = DATEADD(DD, 1 - (@NumDayHistory), @HistoryEndDate);
Declare @ForecastStartDate Date = DATEADD(DD, 1, @HistoryEndDate);
Declare @ForecastEndDate Date = DATEADD(DD, @NumDayForecast, @HistoryEndDate);
Declare @StartRowIndexHistory int = 1;
Declare @EndRowIndexHistory int = @NumDayHistory;
Declare @StartRowIndexForecast int = 1 + @NumDayHistory;
Declare @EndRowIndexForecast int = @NumdayHistory + @NumDayForecast;



-- Generate RowIndex and Date between HistoryStartDate and HistoryEndDate across all regions
Create table #DateSeries
(
   [Date] Date,
   [RowIndex] int
);

With gen As (
    Select @HistoryStartDate As [Date], @StartRowIndexHistory As RowIndex
    Union All
    Select DATEADD(dd, 1, [Date]), RowIndex + 1 FROM gen WHERE DATEADD(dd, 1, [Date]) <= @HistoryEndDate and RowIndex + 1 <= @EndRowIndexHistory
)

Insert into #DateSeries
Select * From gen
Option (maxrecursion 10000)

-- Join [dbo].[StorageUsageCPUStats] with [dbo].[AzureClusters] to get only live clusters and Portal used Region
Create table #StorageUsageCPUStats
(
   FileDate Datetime,
   [Date] Datetime,
   Region Nvarchar(max),
   Tenant Varchar(255),
   Cluster Varchar(255),
   StorageType Varchar(255),
   CPUUtilization Varchar(255),
   ACUUsed Float,
   ACUTotal Float,
   GeoSetup Nvarchar(20)
);

Insert into #StorageUsageCPUStats 
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
Where az.ClusterLIVEDateSource = 'Actual' AND az.IsIntentSellable = 'Sellable'


-- Get 14 days History Usage Data across all region to train Linear Model 
Create table #HistoryUsage
(
   [Date] Date,
   [Region] Varchar(300),
   [Usage] float,
   [Capacity] int
);

Insert into #HistoryUsage
Select * 
From 
   (Select Cast(FileDate as date) as [Date], 
           Region, 
	       Sum(ACUUsed) as Usage, 
	       Sum(ACUTotal) as Capacity
    From #StorageUsageCPUStats  
    Where StorageType = 'Standard' and 
          GeoSetup <> 'secondary' 
    Group by Cast(FileDate as date), Region) AggregatedUsage
Where AggregatedUsage.[Date] between @HistoryStartDate and @HistoryEndDate
Order by AggregatedUsage.[Date] 

-- Generate crossjoin of distinct Region in to Series
Create table #DateSeriesWithRegion
(
   [Date] Date,
   [RowIndex] int,
   [Region] Varchar(300)
);

Insert into #DateSeriesWithRegion
Select * from #DateSeries d
cross join
(Select distinct Region from #HistoryUsage) r


-- Generate Usage and Capacity Based on DateSeries across all region
Create table #UsageSeries
(
   [Date] Date,
   [RowIndex] int,
   [Region] Varchar(300),
   [Usage] float,
   [Capacity] int
);

Insert into #UsageSeries
Select dsr.[Date], dsr.RowIndex, dsr.Region, hu.Usage, hu.Capacity  
From 
   #DateSeriesWithRegion dsr 
left outer join  
	 #HistoryUsage hu 
On dsr.[Date] = hu.[Date] and dsr.[Region] = hu.[Region]	   
Order by dsr.region, dsr.[Date]

 
-- fill missing values in Usage and Capacity Null Values from Previous Non-null Value or Next if No Previous Exists 
Create table #UsageSeriesWithNullFilled(
   [Date] Date,
   [RowIndex] int,
   [Region] Varchar(300),
   [Usage] float,
   [Capacity] int
);

;with UsageSeriesCTE as 
(
  Select * From #UsageSeries
)

Insert into #UsageSeriesWithNullFilled
Select UsageFilled.[Date], UsageFilled.RowIndex, UsageFilled.Region, UsageFilled.Usage, CapacityFilled.Capacity  
From

(Select r.[Date], r.RowIndex, r.Region, ISNULL(x.Usage, y.Usage) As Usage
From UsageSeriesCTE r
     OUTER APPLY (Select Top 1 * From UsageSeriesCTE
	              Where RowIndex <= r.RowIndex and 
				        Region = r.Region and 
						Usage is not null
				  Order by RowIndex	Desc) x
     OUTER APPLY (Select Top 1 * From UsageSeriesCTE
	              Where Region = r.Region and 
						Usage is not null
                  Order by RowIndex) y) UsageFilled

join 

(Select r.[Date], r.RowIndex, r.Region, ISNULL(x.Capacity, y.Capacity) As Capacity
From UsageSeriesCTE r
     OUTER APPLY (Select Top 1 * From UsageSeriesCTE
	              Where RowIndex <= r.RowIndex and 
				        Region = r.Region and 
						Capacity is not null
				  Order by RowIndex	Desc) x
     OUTER APPLY (Select Top 1 * From UsageSeriesCTE
	              Where Region = r.Region and 
						Capacity is not null
                  Order by RowIndex) y) CapacityFilled

On

UsageFilled.[Date] = CapacityFilled.[Date] and
UsageFilled.RowIndex = CapacityFilled.RowIndex and 
UsageFilled.Region = CapacityFilled.Region

Order by

UsageFilled.[Date], UsageFilled.Region

-- Set Previous Day's Usage if Current Day's both Usage and Capacity decrease compare to Previous Day 

Declare @Date Date;
Declare @RowIndex Int;
Declare @Region Varchar(300);
Declare @UsageToday float;
Declare @CapacityToday int;
Declare @UsageYesterday float;
Declare @CapacityYesterday int;


Declare cur Cursor For (Select today.[Date], today.[RowIndex], today.[Region], today.[Usage] as UsageToday, today.[Capacity] as CapacityToday, IsNull(yesterday.[Usage], 0) as UsageYesterday, IsNull(yesterday.[Capacity], 0) as CapacityYesterday from #UsageSeriesWithNullFilled today

                        left outer join 
  
                        #UsageSeriesWithNullFilled yesterday

                        on DateAdd(dd, -1, today.[Date]) = yesterday.[Date]  and today.[Region] = yesterday.[Region])


Open cur

Fetch Next from cur into @Date, @RowIndex, @Region, @UsageToday, @CapacityToday, @UsageYesterday, @CapacityYesterday

While(@@FETCH_STATUS = 0)
Begin

     If (@UsageToday < @UsageYesterday and @CapacityToday < @CapacityYesterday)
	 Begin
         Update #UsageSeriesWithNullFilled set Usage = @UsageYesterday where [Date] = @Date and [RowIndex] = @RowIndex and [Region] = @Region
		 Update #UsageSeriesWithNullFilled set Capacity = @CapacityYesterday where [Date] = @Date and [RowIndex] = @RowIndex and [Region] = @Region
     End
     Fetch Next from cur into @Date, @RowIndex, @Region, @UsageToday, @CapacityToday, @UsageYesterday, @CapacityYesterday
End

Close cur
Deallocate cur

-- Linear Projection for every Region
Create Table #LinearModelParams
(
   Region Varchar(300),
   b float,
   a float
);

Insert into #LinearModelParams
Select ModelParamsWithTrend.Region, ModelParamsWithTrend.b, cast(ModelParamsWithTrend.yAverage - cast(ModelParamsWithTrend.b * (@NumDayHistory + 1) as float) / cast(2 as float)  as float) as a
From
   (Select ModelParams.Region, ModelParams.yAverage, cast(ModelParams.Sxy/ModelParams.Sxx as float) as b
    From
        (Select Region
               ,cast( ( cast(@NumDayHistory * Sum(Usage * RowIndex) as float) - (cast(@NumDayHistory * (@NumDayHistory + 1) as float) / cast(2 as float)) * Sum (Usage) ) as float ) as Sxy
	           ,cast((@NumDayHistory * @NumDayHistory * (@NumDayHistory + 1) * (2 * @NumDayHistory + 1)) as float) / cast(6 as float) - cast((@NumDayHistory * @NumDayHistory * (@NumDayHistory + 1) * (@NumDayHistory + 1)) as float)/ cast(4 as float) as Sxx
	           ,cast((cast(Sum(Usage) as float) / cast(@NumDayHistory as float)) as float) as yAverage 	    
         From #UsageSeriesWithNullFilled
         Group by Region) as ModelParams) as ModelParamsWithTrend
Order by Region

-- Generate Forecast DateSeries
Create table #DateSeriesForecast
(
   [Date] Date,
   [RowIndex] int
);

With gen2 As (
    Select @ForecastStartDate As [Date], @StartRowIndexForecast As RowIndex
    Union All
    Select DATEADD(dd, 1, [Date]), RowIndex + 1 FROM gen2 WHERE DATEADD(dd, 1, [Date]) <= @ForecastEndDate and RowIndex + 1 <= @EndRowIndexForecast
)

Insert into #DateSeriesForecast
Select * From gen2
Option (maxrecursion 10000)

-- Generate crossjoin of distinct Region in to Series
Create table #DateSeriesForecastWithRegion
(
   [Date] Date,
   [RowIndex] int,
   [Region] Varchar(300)
);

Insert into #DateSeriesForecastWithRegion
Select * from #DateSeriesForecast d
cross join
(Select distinct Region from #HistoryUsage) r

-- Generate the ForecastResult, the Geo value for Region is from HotRegionReport
Select x.SnapshotDate,
       y.Geo, 
       x.Region,
	   x.ClusterType,
	   x.ResourceUnit,
	   x.ForecastDate,
	   x.ForecastValue
From 

(Select 
       [dbo].[fn_GetReportDate]() as SnapshotDate,
	   d.Region as Region,
	   'STORAGE' as ClusterType,
	   'CPU' as ResourceUnit,
       d.[Date] as [ForecastDate],
	   cast((RowIndex * b + a) as float) as ForecastValue
 From 
    #DateSeriesForecastWithRegion d
 Left outer join
    #LinearModelParams l
 on d.Region = l.Region) x

left outer join

(Select Geo, Region 
 From rpt.HotRegionReport
 Group by Geo, Region) y 

on x.Region = y.Region

order by x.Region, x.ForecastDate


----------------------------------------------------------
--Select * From #HistoryUsage Order by Region, Date
--Select * From #DateSeries Order by Date
--Select * From #DateSeriesWithRegion Order by Region, Date
--Select * From #UsageSeries Order by Region, Date
--Select * From #UsageSeriesWithNullFilled Order by Region, Date
--Select * From #LinearModelParams Order by Region
--Select * From #DateSeriesForecast
--Select * From #DateSeriesForecastWithRegion

Drop table #DateSeries;
Drop table #StorageUsageCPUStats;
Drop table #HistoryUsage;
Drop table #DateSeriesWithRegion;
Drop table #UsageSeries;
Drop table #UsageSeriesWithNullFilled;
Drop table #LinearModelParams;
Drop table #DateSeriesForecast;
Drop table #DateSeriesForecastWithRegion;