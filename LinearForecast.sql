--Declare @HistoryEndDate Date = DATEADD(DD,-1,[dbo].[fn_GetReportDate]());
Declare @HistoryEndDate Date = DATEADD(DD,-1,cast('2017-01-21' as Date));
Declare @HistoryStartDate Date = DATEADD(DD, -13, @HistoryEndDate);
Declare @StartRowIndex int = 1;
Declare @EndRowIndex int = 14;
Declare @NumDayHistory int = 14;


-- Generate RowIndex and Date between HistoryStartDate and HistoryEndDate across all regions
Create table #DateSeries
(
   [Date] Date,
   [RowIndex] int
);

With gen As (
    Select @HistoryStartDate As [Date], @StartRowIndex As RowIndex
    Union All
    Select DATEADD(dd, 1, [Date]), RowIndex + 1 FROM gen WHERE DATEADD(dd, 1, [Date]) <= @HistoryEndDate and RowIndex + 1 <= @EndRowIndex
)

Insert into #DateSeries
Select * From gen
Option (maxrecursion 10000)

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
    From [dbo].[StorageUsageCPUStats]  
    Where StorageType = 'Standard' and 
          GeoSetup <> 'secondary' 
    Group by Cast(FileDate as date), Region) AggregatedUsage
Where AggregatedUsage.[Date] between @HistoryStartDate and @HistoryEndDate
Order by AggregatedUsage.[Date] 

-- Generate crossjoin of distinct Region in to Series
Create table #DataSeriesWithRegion
(
   [Date] Date,
   [RowIndex] int,
   [Region] Varchar(300)
);

Insert into #DataSeriesWithRegion
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
   #DataSeriesWithRegion dsr 
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


----------------------------------------------------------


 
Drop table #HistoryUsage;
Drop table #DateSeries;
Drop table #DataSeriesWithRegion;
Drop table #UsageSeries;
Drop table #UsageSeriesWithNullFilled;