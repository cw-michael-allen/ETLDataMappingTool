USE REPLACEME_ETL
GO

---------------------------- ServiceType ----------------------------------------
IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
		WHERE COLUMN_NAME = 'LegacyID' AND TABLE_NAME = 'ServiceType')
BEGIN
	ALTER TABLE dbo.ServiceType ADD LegacyID VARCHAR(20) NULL
END
GO

Print 'ServiceType'
INSERT ServiceType (
	[Description]
	,OrgGroupID
	,UnitOfMeasure
	,UnitValue
	,CreatedBy
	,CreatedDate
	,DuplicateMinutes
	,LegacyID
	)
SELECT DISTINCT
	SST.[Description]
	,0 AS 'OrgGroupID' --All orgs
	,ISNULL(4,SST.UnitOfMeasure) AS UnitOfMeasure --Default is each
	,SST.UnitValue
	,11 AS CreatedBy
	,SST.CreatedDate
	,ISNULL(SST.DuplicateMinutes,0) 'DuplicateMinutes'
	,SST.ServiceTypeID AS LegacyID
FROM REPLACEME_Staging.dbo.ServiceType SST
LEFT JOIN ServiceType ST ON ST.LegacyID = SST.ServiceTypeID
WHERE ST.ServiceTypeID IS NULL
GO

Print 'ServiceTypeCategory'
INSERT INTO ServiceTypeCategory (ServiceTypeID,CategoryID)
SELECT DISTINCT STT.ServiceTypeID, X.NodeChar 'CategoryID'
FROM REPLACEME_Staging.dbo.ServiceType ST
INNER JOIN ServiceType STT on STT.LegacyID = ST.ServiceTypeID
CROSS APPLY dbo.fn_SplitNodeChar(ST.Categories, ',') X
LEFT JOIN ServiceTypeCategoryType STCT ON STCT.CategoryID = X.NodeChar
INNER JOIN ServiceTypeCategory STC ON STC.CategoryID = X.NodeChar
	AND STC.ServiceTypeID = STT.ServiceTypeID
WHERE X.NodeChar IS NOT NULL
AND STC.ServiceTypeID IS NULL --prevent dupes
GO

Print 'ServiceTypeUsage'
INSERT INTO ServiceTypeUsage (ServiceTypeID,ServiceUsage)
SELECT DISTINCT STT.ServiceTypeID,SU.ListValue 'ServiceUsage'
FROM REPLACEME_Staging.dbo.ServiceType ST
INNER JOIN ServiceType STT on STT.LegacyID = ST.ServiceTypeID
CROSS APPLY dbo.fn_SplitNodeChar(ST.ServiceTypeUsage, ',') X
INNER JOIN ListItem SU on SU.ListID = 31 AND SU.listvalue = X.NodeChar
LEFT JOIN ServiceTypeUsage STU ON STU.ServiceTypeID = STT.ServiceTypeID
	AND STU.ServiceUsage = SU.ListValue
WHERE STU.ServiceTypeID IS NULL --prevent dupes
GO

------------------------------ Service --------------------------
IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE COLUMN_NAME = 'LegacyID' AND TABLE_NAME = 'Service')
BEGIN
	ALTER TABLE dbo.Service ADD LegacyID VARCHAR(20) NULL
END
GO

ALTER TABLE Service DISABLE TRIGGER [tiu_ServiceAccounting]
GO

PRINT 'Service'
INSERT INTO Service WITH (TABLOCK) (
	ServiceTypeID
	,ProvidedToEntityID
	,ProvidedByEntityID
	,ProvidedByUserID
	,EnrollmentID
	,UnitOfMeasure
	,UnitValue
	,Units
	,ServiceTotal
	,PaidtoDate
	,BeginDate
	,EndDate
	,CreatedBy
	,OwnedByOrgID
	,CreatedDate
	,Restriction
	,LegacyID
	)
SELECT DISTINCT
	ST.ServiceTypeID
	,C.EntityID AS ProvidedToEntityID
	,CASE WHEN U5.EntityID IS NOT NULL THEN U5.EntityID
		WHEN U6.EntityID IS NOT NULL THEN U6.EntityID
		ELSE 11 END AS ProvidedByEntityID
	,CASE WHEN U3.EntityID IS NOT NULL THEN U3.EntityID
		WHEN U4.EntityID IS NOT NULL THEN U4.EntityID
		ELSE 11 END AS ProvidedByUserID
	,E.EnrollmentID
	,ISNULL(S.UnitOfMeasure, 1) AS UnitOfMeasure
	,ISNULL(S.UnitValue, 0) AS UnitValue
	,ISNULL(S.Units, 0) AS Units
	,ISNULL(CONVERT(float, S.UnitValue), 0) * ISNULL(CONVERT(float, S.Units), 0) AS ServiceTotal
	,S.PaidtoDate
	,S.BeginDate
	,CASE WHEN IsDate(S.EndDate) = 1 THEN S.EndDate
		WHEN IsDate(S.BeginDate) = 1 THEN S.BeginDate
		End AS EndDate
	,CASE WHEN U2.EntityID IS NOT NULL THEN U2.EntityID
		WHEN U.EntityID IS NOT NULL THEN U.EntityID
		ELSE 11 END AS CreatedBy
	,ISNULL(S.OwnedbyOrgID,C.OwnedbyorgID) AS OwnedByOrgID
	,ISNULL(S.CreatedDate, S.BeginDate) AS CreatedDate
	,ISNULL(S.Restriction,1) AS Restriction
	,S.ServiceID AS LegacyID
FROM REPLACEME_Staging.dbo.Service S
INNER JOIN ServiceType ST  ON S.ServiceTypeID = ST.LegacyID --Change join if serviceTypes exist
INNER JOIN Client C  ON C.LegacyID = S.ProvidedToEntityID
LEFT JOIN Users U ON U.LegacyID = S.CreatedBy
LEFT JOIN Users U2 ON U2.EntityID = S.CreatedBy
LEFT JOIN Users U3 on U3.LegacyID = S.ProvidedByUserID
LEFT JOIN Users U4 on U4.EntityID = S.ProvidedByUserID
LEFT JOIN Users U5 on U5.LegacyID = S.ProvidedByEntityID
LEFT JOIN Users U6 on U6.EntityID = S.ProvidedByEntityID
LEFT JOIN Enrollment E  ON E.LegacyID=S.EnrollmentID
LEFT JOIN Service S2 on S2.LegacyID = S.ServiceID
WHERE S.BeginDate IS NOT NULL ---Clients should not be uploading services with begindate
	AND S2.ServiceID IS NULL --Prevent dupes

ALTER TABLE Service ENABLE TRIGGER [tiu_ServiceAccounting]
GO

---------------------------------- CaseNotes ---------------------------------------------------
IF NOT EXISTS (SELECT 1
		FROM INFORMATION_SCHEMA.COLUMNS
		WHERE COLUMN_NAME = 'LegacyID'AND TABLE_NAME = 'CaseNotes')
BEGIN
	ALTER TABLE dbo.CaseNotes ADD LegacyID VARCHAR(25) NULL
END
GO

/* Occassionly these ALTERS need ran to allow data to be imported */
--ALTER TABLE [CaseNotes] ALTER COLUMN [Body] NVARCHAR(MAX)
--ALTER TABLE [CaseNotes] ALTER COLUMN [CaseNoteSummary] NVARCHAR(100)

PRINT 'CaseNotes'
INSERT INTO [dbo].[CaseNotes] WITH (TABLOCK) (
	[EntityID]
	,[CaseNoteSummary]
	,[Body]
	,CreatedBy
	,[OwnedByOrgID]
	,CreatedDate
	,Restriction
	,[CaseNoteTypeID]
	--,EnrollmentID
	,[LegacyID]
	)
SELECT DISTINCT C.EntityID AS ClientID
	,CN.CaseNoteSummary
	,CN.[Body]
	,CASE WHEN U2.EntityID IS NOT NULL THEN U2.EntityID
		WHEN U.EntityID IS NOT NULL THEN U.EntityID
		ELSE 11 END AS CreatedBy
	,C.OwnedByOrgID
	,CN.CreatedDate
	,CASE WHEN CN.RESTRICTION IN (1,2,3) THEN CN.RESTRICTION
		ELSE 1 END AS Restriction
	,CN.CaseNoteTypeID
	--,E.EnrollmentID  --optional
	,CN.CaseNoteID AS LegacyID
FROM REPLACEME_Staging.dbo.CaseNotes AS CN
INNER JOIN Client C  ON C.LegacyID = CN.ClientID
LEFT JOIN Users U ON U.LegacyID = CN.CreatedBy
LEFT JOIN Users U2 ON CONVERT(varchar,U2.EntityID) = CN.CreatedBy
LEFT JOIN CaseNotes CN2 ON CN2.LegacyID = CN.CaseNoteID
WHERE CN2.LegacyID IS NULL


PRINT 'CaseNotesExtension'
INSERT INTO [dbo].[CaseNotesExtension] (
	CaseNoteID
	,ReferenceDate
	)
SELECT DISTINCT CNT.CaseNoteID
	,ISNULL(CNS.ReferenceDate,CNS.CreatedDate)
FROM REPLACEME_Staging.dbo.CaseNotes AS CNS
INNER JOIN CaseNotes CNT ON CNS.CaseNoteID = CNT.LegacyID
LEFT JOIN CaseNotesExtension CNE on CNT.CaseNoteID = CNE.CaseNoteID
WHERE CNE.casenoteid is null
