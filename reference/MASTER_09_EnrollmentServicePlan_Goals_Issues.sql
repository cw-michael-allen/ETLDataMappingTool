USE REPLACE_ME_ETL
GO

----------------------------------------GoalType--------------------------------------
IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
		WHERE COLUMN_NAME = 'LegacyID' AND TABLE_NAME = 'GoalType')
BEGIN
	ALTER TABLE dbo.GoalType ADD LegacyID INT
END
GO

INSERT GoalType (
	TypeDescription
	,CreatedDate
	,LegacyID
	)
SELECT GoalDescription
	,GETDATE() AS CreatedDate
	,GT.GoalTypeID AS LegacyID
FROM REPLACE_ME_Staging.[dbo].[GoalType] GT
LEFT OUTER JOIN GoalType EGT ON EGT.LegacyID = GT.GoalTypeID
WHERE EGT.LegacyID IS NULL


--------------------- EnrollmentServicePlan ----------------------------
IF NOT EXISTS ( SELECT 1 FROM INFORMATION_SCHEMA .COLUMNS
	WHERE COLUMN_NAME = 'LegacyID' AND TABLE_NAME = 'EnrollmentServicePlan')
BEGIN
	ALTER TABLE dbo.EnrollmentServicePlan ADD LegacyID NVARCHAR(20) NULL
END
GO

PRINT 'EnrollmentServicePlan'
INSERT INTO EnrollmentServicePlan (
	EnrollmentID
	,ClientID
	,PlanBeginDate
	,PlanEndDate
	,ActualCompletedDate
	,Description
	,CaseManagerID
	,CreatedDate
	,CreatedBy
	,OwnedByOrgID
	,LegacyID
)
SELECT
	E.EnrollmentID AS EnrollmentID
	,C.EntityID AS ClientID
	,ESP.PlanBeginDate
	,ESP.PlanEndDate
	,ESP.ActualCompletedDate
	,ISNULL(ESP.[Description],ESP.PlanBeginDate) AS [Description]
	,ISNULL(U.EntityID, 11) AS CaseManagerID
	,ISNULL(ESP.CreatedDate, GETDATE()) AS CreatedDate
	,ISNULL(U2.EntityID, 11) AS CreatedBy
	,E.OwnedByOrgID AS OwnedByOrgID
	,ESP.EnrollmentServicePlanID AS LegacyID
FROM REPLACE_ME_Staging.dbo.EnrollmentServicePlan ESP
INNER JOIN Client C ON C.LegacyID = ESP.ClientID
INNER JOIN Enrollment E ON E.LegacyID = ESP.EnrollmentID
LEFT JOIN Users U ON U.LegacyID = ESP.AssignedUserID
LEFT JOIN Users U2 ON U2.LegacyID = ESP.CreatedBy
LEFT JOIN EnrollmentServicePlan ESP2 on ESP2.LegacyID = ESP.EnrollmentServicePlanID
WHERE ESP2.EnrollmentServicePlanID IS NULL --Prevent dupes

---------------------------------  Goal -----------------------------------------
IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
		WHERE COLUMN_NAME = 'LegacyID' AND TABLE_NAME = 'Goal'
		)
BEGIN
	ALTER TABLE dbo.Goal ADD LegacyID NVARCHAR(20) NULL
END
GO

PRINT 'Goal'
INSERT Goal (
	--GoalID
	ClientID
	,GoalTypeID
	,PlanAttainDate
	,ActualAttainDate
	,SetDate
	,CreatedDate
	,CreatedBy
	,PercentComplete
	,Restriction
	,OwnedByOrgID
	,UserID
	,ResponsibleParty
	,LegacyID
	)
SELECT
	ClientID
	,GoalTypeID
	,PlanAttainDate
	,ActualAttainDate
	,SetDate
	,CreatedDate
	,CreatedBy
	,PercentComplete
	,Restriction
	,OwnedByOrgID
	,UserIDAssignedStaff
	,ResponsibleParty
	,LegacyID
FROM
(
	SELECT EC.EntityID AS ClientID
		,GT.GoalTypeID
		,G.PlanAttainDate
		,G.ActualAttainDate
		,G.SetDate
		,G.CreatedDate
		,ISNULL(UCreatedBy.EntityID,11) AS CreatedBy
		,G.PercentComplete
		,G.Restriction
		,EC.OwnedByOrgID
		,EU.EntityID AS UserIDAssignedStaff
		,G.ResponsibleParty
		,ROW_NUMBER() OVER (PARTITION BY G.GoalID ORDER BY EU.EntityID DESC ) AS RNUM
		,G.GoalID AS LegacyID
	-- SELECT COUNT(*)
	FROM REPLACE_ME_Staging.dbo.Goal G
	INNER JOIN Client EC ON EC.LegacyID = G.ClientID
	LEFT JOIN Users EU ON EU.LegacyID = G.UserIDAssignedStaff
	LEFT JOIN Users UCreatedBy ON UCreatedBy.LegacyID = G.CreatedBy
	INNER JOIN GoalType GT ON GT.LegacyID = G.GoalTypeID	--Only used if client is adding goaltypes via ETL
	LEFT JOIN Goal EG ON EG.LegacyID = G.GoalID
	WHERE EG.LegacyID IS NULL
) ABC
WHERE RNUM = 1

------------------------ ServicePlanGoals -------------------------------
IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE COLUMN_NAME = 'LegacyID' AND TABLE_NAME = 'ServicePlanGoals')
BEGIN
	ALTER TABLE dbo.ServicePlanGoals ADD LegacyID NVARCHAR(20) NULL
END
GO

PRINT 'ServicePlanGoals'
INSERT INTO ServicePlanGoals (
	GoalID						-- From the Goal table
	,CreatedDate
	,CreatedBy
	,OwnedByOrgID
	--,[Priority]
	--,[Weight]
	,EnrollmentServicePlanID
	,LegacyID
)
SELECT
	G.GoalID
	,ISNULL(SPG.CreatedDate, GETDATE()) AS CreatedDate
	,ISNULL(U2.EntityID, 11) AS CreatedBy
	,ESP.OwnedByOrgID AS OwnedByOrgID
	--,SPG.[Priority]
	--,SPG.[Weight]
	,ESP.EnrollmentServicePlanID
	,SPG.GoalID AS LegacyID
FROM REPLACE_ME_Staging.dbo.Goal SPG
INNER JOIN Goal G ON G.LegacyID = SPG.GoalID
INNER JOIN EnrollmentServicePlan ESP ON ESP.LegacyID = SPG.EnrollmentServicePlanID
LEFT JOIN Users U2 ON U2.LegacyID = SPG.CreatedBy
LEFT JOIN ServicePlanGoals SPG2 on SPG2.LegacyID = SPG.GoalID
WHERE SPG2.PlanGoalID IS NULL ---prevent Dupes


-------------------------- ISSUE -------------------------------
IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE COLUMN_NAME = 'LegacyID' AND TABLE_NAME = 'Issue')
BEGIN
	ALTER TABLE dbo.Issue ADD LegacyID NVARCHAR(20) NULL
END
GO

PRINT 'Issue'
INSERT INTO [dbo].[Issue] (
	[ClientID]
	,[IssueTypeID]
	,[IdentifiedDate]
	,[IdentifiedByUserID]
	,[IsChronic]
	,[IsInTreatment]
	,[CaseNoteID]
	,[CreatedBy]
	,[OwnedByOrgID]
	,[CreatedDate]
	,[EndDate]
	,[Restriction]
	,[EvalLevel]
	,[EnrollmentID]
	,LegacyID
	)
SELECT DISTINCT
	C.EntityID AS [ClientID]
	,IT.[IssueTypeID]
	,CASE WHEN TRY_CONVERT(Date,I.[IdentifiedDate]) IS NOT NULL THEN I.[IdentifiedDate]
		WHEN TRY_CONVERT(Date,I.CreatedDate) IS NOT NULL THEN I.CreatedDate
		ELSE GETUTCDATE()
		END AS [IdentifiedDate]
	,ISNULL(U.EntityID, 11) AS IdentifiedByUserID
	,ISNULL(I.[IsChronic], 99) AS IsChronic
	,ISNULL(I.[IsInTreatment], 99) AS [IsInTreatment]
	,CN.[CaseNoteID]
	,ISNULL(U.EntityID, 11) 'CreatedBy'
	,ISNULL(O.EntityID,C.[OwnedByOrgID]) 'OwnedByOrgID'
	,ISNULL(I.[CreatedDate],GETUTCDATE()) 'CreatedDate'
	,I.[EndDate]
	,ISNULL(I.[Restriction],1) 'Restriction'
	,I.[EvalLevel]
	,EM.EnrollmentID
	,I.[IssueID] AS LegacyID
FROM REPLACE_ME_Staging.[dbo].[Issue] AS I
INNER JOIN dbo.Client AS C ON C.LegacyID = I.ClientID
INNER JOIN Organization O on O.EntityID = I.OwnedByOrgID
LEFT JOIN CaseNotes CN On CN.LegacyID = I.CaseNoteID
INNER JOIN IssueType IT ON IT.IssueTypeID = I.ISSUETYPEID
LEFT JOIN Users U on U.EntityID = I.IDENTIFIEDBYUSERID
LEFT JOIN Issue I2 on I2.LegacyID = I.IssueID
LEFT JOIN EnrollmentMember EM
INNER JOIN Enrollment E ON EM.EnrollmentID = E.EnrollmentID
	ON C.EntityID = EM.ClientID
	AND E.LegacyID = I.EnrollmentID
WHERE I2.IssueID IS NULL --Prevent Dupes
