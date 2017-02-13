USE [MCIODM]
GO

/****** Object:  Table [dbo].[XIOStorageCPUShorttermForecast]    Script Date: 1/31/2017 1:35:39 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

SET ANSI_PADDING ON
GO

CREATE TABLE [dbo].[XIOStorageCPUShorttermForecast](
	[SnapShotDate] [date] NULL,
	[Region] [varchar](100) NULL,
	[ClusterType] [varchar](20) NULL,
	[ForecastDate] [date] NULL,
	[ForecastValue] [float] NULL
)

GO

SET ANSI_PADDING OFF
GO


