USE REPLACE_ME_ETL
GO

----------------------------- CaseManagerAssignment -------------------------
IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE COLUMN_NAME = 'LegacyID' AND TABLE_NAME = 'CaseManagerAssignment')
BEGIN
	ALTER TABLE dbo.CaseManagerAssignment ADD LegacyID VARCHAR(20) NULL
END
GO

PRINT 'CaseManagerAssignment'
INSERT INTO CaseManagerAssignment (
	ClientID
	,UserID
	,EnrollmentID
	,BeginDate
	,EndDate
	,Restriction
	,CreatedBy
	,CreatedDate
	,OwnedByOrgID
	,LastModifiedDate
	,LastModifiedBy
	,LegacyID
	)
SELECT
	EM.ClientID
	,U.EntityID AS UserID
	,E.EnrollmentID
	,CMA.BeginDate
	,ISNULL(CMA.EndDate,'12/31/9999') AS EndDate
	,ISNULL(CMA.Restriction,1) AS Restriction
	,CASE WHEN CMA.CreatedBy IS NOT NULL THEN CMA.CreatedBy
		WHEN E.CreatedBy IS NOT NULL THEN E.CreatedBy
		ELSE 11 END AS CreatedBy
	,CMA.BeginDate
	,ISNULL(O.EntityID,E.OwnedByOrgID) AS OwnedByOrgID
	,GETUTCDATE() AS LastModifiedDate
	,11 AS LastModifiedBy
	,CMA.ASSIGNMENTID AS LegacyID
FROM Enrollment E
INNER JOIN EnrollmentMember EM On EM.EnrollmentID = E.EnrollmentID
INNER JOIN Client C on EM.ClientID = C.EntityID
INNER JOIN REPLACE_ME_Staging.dbo.CASEMANAGERASSIGNMENT CMA ON CMA.ENROLLMENTID = E.LegacyID AND CMA.CLIENTID = C.LegacyID
LEFT JOIN Organization O ON O.EntityiD = CMA.OwnedByOrgID
INNER JOIN Users U ON U.LegacyID = CMA.UserID --Make sure to change join here if not using legacyIDs
LEFT JOIN CaseManagerAssignment CMA2 ON CMA2.LegacyID = CMA.ASSIGNMENTID
WHERE CMA2.AssignmentID IS NULL --Prevent Dupes
