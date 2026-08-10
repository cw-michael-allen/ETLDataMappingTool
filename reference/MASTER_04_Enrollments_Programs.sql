USE REPLACE_ME_ETL
GO

-------------------------- Program -------------------------------------------
IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE COLUMN_NAME = 'LegacyID' AND TABLE_NAME = 'Program')
BEGIN
	ALTER TABLE dbo.Program ADD LegacyID VARCHAR(20) NULL
END
GO

/* Uncomment if you want to do Progam Name Matching */
--Print 'Name Matching for Programs'
--UPDATE P
--SET LEGACYID = SP.ProgramID
--FROM Program P
--INNER JOIN REPLACE_ME_STAGING.dbo.Program SP ON P.ProgramName = SP.ProgramName
--WHERE P.DeletedDate = '12/31/9999'

PRINT 'Program'
INSERT.dbo.Program (
	ProgramName
	,AutoExitDays
	,BeginDate
	,CreatedBy
	,CreatedDate
	,EnrollmentsEnabled
	,NotifyOnAutoExit
	,LegacyID
	,ReopenDays
	,OrgGroupID
	,DuringFamilyWorkflowID
	,DuringIndividualWorkflowID
	,ExitFamilyWorkflowID
	,ExitIndividualWorkflowID
	,MinDays
	,MaxDays
	,ProgramDetail
	)
SELECT DISTINCT
	SP.ProgramName
	,ISNULL(SP.AutoExitDays, 0) 'AutoExitDays'
	,ISNULL(SP.BeginDate, GETDATE()) 'ProgramBeginDate'
	,ISNULL(U.EntityID,11) as CreatedBy
	,SP.CreatedDate
	,ISNULL(SP.EnrollmentsEnabled, 1) 'EnrollmentsEnabled'
	,ISNULL(SP.NotifyOnAutoExit,0) 'NotifyOnAutoExit'
	,SP.ProgramID AS LegacyID
	,ISNULL(SP.ReopenDays, 30) 'ReopenDays'
	,0 as OrgGroupID
	,70 AS DuringFamilyWorkflowID		--Current Default WF as of 10/31/22
	,70 AS DuringIndividualWorkflowID		--Current Default WF as of 10/31/22
	,65 AS ExitFamilyWorkflowID		--Current Default WF as of 10/31/22
	,71 AS ExitIndividualWorkflowID	--Current Default WF as of 10/31/22
	,SP.MinDays
	,SP.MaxDays
	,SP.ProgramDetail
FROM REPLACE_ME_STAGING.dbo.Program SP
LEFT JOIN Program EP ON EP.LegacyID = Convert(nvarchar(50),SP.ProgramID)
LEFT JOIN Users U ON U.LegacyID = SP.CreatedBy
WHERE EP.ProgramID IS NULL

---------------------------------------------- ProgramHMIS ------------------------------------------------------------
/*** For HMIS related imports, it is recommended to import enrollment and assessment data via the HMIS import tool.
Please discuss with customer BEFORE importing HMIS related data. */

--PRINT 'Program HMIS'
--INSERT ProgramHMIS --SELECT * FROM ProgramHMIS
--	(
--	ProgramID
--	,ProgramIdentifier
--	,ProgramType
--	,TargetPopulationA
--	,TargetPopulationB
--	,OccupancyModel
--	,DirectServiceCode
--	)
--SELECT DISTINCT EP.ProgramID
--	,ISNULL(ProgramIdentifier, '')
--	,ProgramType
--	,TargetPopulationA
--	,TargetPopulationB
--	,OccupancyModel
--	,DirectServiceCode
--FROM REPLACE_ME_STAGING.dbo.Program P
--INNER JOIN Program EP ON EP.LegacyID = P.ProgramID
--WHERE P.ProgramType IS NOT NULL
--	AND P.ProgramID NOT IN (
--		SELECT LegacyID
--		FROM Program P
--		INNER JOIN ProgramHMIS PH ON P.ProgramID = PH.ProgramID
--		WHERE LegacyID IS NOT NULL
--		)

---------------------Enrollment--------------------------------------
IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
		WHERE COLUMN_NAME = 'LegacyID' AND TABLE_NAME = 'Enrollment')
	ALTER TABLE dbo.Enrollment ADD LegacyID VARCHAR(20) NULL
GO

PRINT 'Enrollment'
INSERT dbo.Enrollment
	(
	ProgramID
	,FamilyID
	,OrganizationID
	,OwnedByOrgID
	,AccountID
	,STATUS
	,BeginDate
	,EndDate
	,CreatedBy
	,CreatedDate
	,LegacyID
	)
SELECT DISTINCT
	P.ProgramID ProgramID
	,F.FamilyID AS FamilyID
	,C.OwnedByOrgID AS OrganizationID
	,C.OwnedByOrgID AS OwnedByOrgID
	,E.AccountID AS AccountID
	,E.STATUS AS STATUS
	,E.BeginDate AS BeginDate
	,ISNULL(ExitDate, '9999-12-31') AS ExitDate
	,CASE WHEN U2.EntityID IS NOT NULL THEN U2.EntityID
		WHEN U1.EntityID IS NOT NULL THEN U1.EntityID
		ELSE 11
		END AS CreatedBy
	,ISNULL(E.CreatedDate, GETUTCDATE()) AS CreatedDate
	,E.EnrollmentID 'LegacyID'
	FROM Replace_Me_Staging.DBO.Enrollment E
	INNER JOIN Client C ON C.LegacyID = E.ClientID
	INNER JOIN FamilyMember F ON F.ClientID = C.EntityID
	INNER JOIN Program P ON E.ProgramID = P.LegacyID  --OR P.ProgramID if not using legacy ProgramIDs
	LEFT JOIN Users U1 ON U1.EntityID = E.CreatedBy
	LEFT JOIN Users U2 ON U2.LegacyID = E.CreatedBy
	LEFT JOIN Enrollment EE ON EE.LegacyID = E.EnrollmentID
	WHERE EE.LegacyID IS NULL
	AND E.Begindate IS NOT NULL --Remove invalid enrollments missing a begin date

----------------------------EnrollmentMember-----------------------------
IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS  WHERE COLUMN_NAME = 'LegacyID'AND TABLE_NAME = 'EnrollmentMember')
BEGIN
	ALTER TABLE dbo.EnrollmentMember ADD LegacyID VARCHAR(20) NULL
END
GO

PRINT 'EnrollmentMember'
INSERT EnrollmentMember (
	EnrollmentID
	,ClientID
	,ProviderID
	,AssessmentsComplete
	,BeginDate
	,EndDate
	,CreatedBy
	,CreatedDate
	,DeletedDate
	,Restriction
	,RelationToHoH
	,OwnedByOrgID
	,LegacyID
	)
SELECT DISTINCT EE.EnrollmentID
	,EC.EntityID
	,ISNULL(EP.EntityID, 14) AS ProviderID
	,0 AS AssessmentsComplete
	,ISNULL(SE.BeginDate, GETDATE()) AS BeginDate
	,ISNULL(SE.ExitDate, '9999-12-31') AS EndDate
	,EE.CreatedBy AS CreatedBy
	,SE.CreatedDate AS CreatedDate
	,EE.DeletedDate
	,CASE WHEN SE.Restriction IS NULL OR SE.Restriction = '' THEN 1
		WHEN SE.Restriction NOT IN (1,2) THEN 1
		ELSE SE.Restriction END 'Restriction'
	,CL.RelationToHoH
	,EE.OrganizationID
	,SE.MemberID 'MemberLegacyID'
FROM Replace_Me_Staging.dbo.Enrollment SE
INNER JOIN Client EC ON EC.LegacyID = SE.ClientID
INNER JOIN Replace_Me_Staging.dbo.Client CL ON CL.ClientID = SE.ClientID
--INNER JOIN FamilyMember FM  ON FM.ClientID =EC.EntityID
INNER JOIN Enrollment EE ON EE.LegacyID = SE.EnrollmentID
LEFT JOIN Users EU ON EU.LegacyID = SE.CreatedBy
LEFT OUTER JOIN Provider EP ON EP.EntityID = SE.ProviderID
LEFT OUTER JOIN EnrollmentMember EM ON EM.LegacyID = SE.MemberID
WHERE EM.LegacyID IS NULL

--INSERT INTO ProgramHMIS (ProgramID,ProgramType)
--SELECT DISTINCT
--ProgramID
--,ProgramType AS ProjectType --List 43
--,ContinuumProject --List 194
