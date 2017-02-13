SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- =============================================
-- Author:		Junwei Hu
-- Create date: 01/31/2017
-- Description:	Load [dbo].[StorageCPUShorttermForecast] data from [dbo].[stgStorageCPUShorttermForecast]
-- Triggered by Cas job: StorageCPUShorttermForecast
-- =============================================
CREATE PROCEDURE [dbo].[usp_LoadStorageCPUShortTermForecast] 

AS
BEGIN
	
	DECLARE @RowCount int

	/*Load Storage Shortterm Forecast Data */

	SELECT @RowCount = COUNT(*)
	FROM [dbo].[stgStorageCPUShorttermForecast]
	WHERE ClusterType = 'STORAGE' AND ResourceUnit = 'CPU'

	IF (@RowCount >0)
		TRUNCATE TABLE [dbo].[StorageCPUShorttermForecast]


	INSERT INTO [dbo].[StorageCPUShorttermForecast] (SnapShotDate, Region, ClusterType, ForecastDate, ForecastValue)
	SELECT SnapShotDate, Region, ClusterType, ForecastDate, ForecastValue
	FROM [dbo].[stgStorageCPUShorttermForecast]
	WHERE ClusterType = 'STORAGE' AND ResourceUnit = 'CPU'

END
GO
