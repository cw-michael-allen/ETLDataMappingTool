USE REPLACE_ME_ETL
GO

------------------------- Time --------------------------------
IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE COLUMN_NAME = 'LegacyID' AND TABLE_NAME = 'Time')
BEGIN
	ALTER TABLE dbo.[Time] ADD LegacyID VARCHAR(20) NULL
END
GO

PRINT 'Time'
INSERT INTO [Time] (
	CreatedBy
	,CreatedDate
	,DeletedDate
	,OwnedByOrgID
	,Restriction
	,StartTime
	,TimeHours
	,TimeType
	,LegacyID
	)
SELECT ISNULL(U.EntityID, 11) AS CreatedBy
	,ISNULL(XP.CreatedDate, GETDATE()) AS CreatedDate
	,ISNULL(XP.DeletedDate, '12-31-9999') AS DeletedDate
	,OwnedByOrgID
	,Restriction
	,StartTime
	,TimeHours
	,TimeType
	,TimeID
FROM REPLACE_ME_Staging.dbo.[Time] XP
LEFT JOIN Users U ON U.LegacyID = XP.CreatedBy

------------------------ UserClientTime ----------------------------------
IF NOT EXISTS (
		SELECT *
		FROM INFORMATION_SCHEMA.COLUMNS
		WHERE COLUMN_NAME = 'LegacyID'
			AND TABLE_NAME = 'UserClientTime'
		)
	ALTER TABLE dbo.UserClientTime ADD LegacyID VARCHAR(50) NULL
GO

PRINT 'UserClientTime'
INSERT INTO UserClientTime (
	ClientID
	,TimeID
	,UsageID
	,UserID
	,X_CenterID
	,X_ProgramID
	,X_TimeActivity
	,LegacyID
	)
SELECT C.EntityID
	,T.TimeID
	,UsageID
	,ISNULL(U.EntityID, 11) AS UserID
	,X_CenterID
	,X_ProgramID
	,X_TimeActivity
	,UserClientTimeID
FROM REPLACE_ME_Staging.dbo.UserClientTime XP
INNER JOIN [Time] T ON T.LegacyID = XP.TimeID
INNER JOIN Client C ON C.LegacyID = XP.ClientID
LEFT JOIN Users U ON U.LegacyID = XP.UserID

------------------------ Credential ----------------------------------
IF NOT EXISTS (
		SELECT * FROM INFORMATION_SCHEMA.COLUMNS
		WHERE COLUMN_NAME = 'LegacyID'
			AND TABLE_NAME = 'Credential'
		)
BEGIN
	ALTER TABLE Credential ADD LegacyID VARCHAR(20)
END
GO

--Create credential and skill type match if missing
Print 'CredentialTypeSkillType'
INSERT INTO CredentialTypeSkillType (CredentialTypeID,SkillTypeID)
SELECT DISTINCT
C.CredentialTypeID,C.SkillTypeID
FROM REPLACE_ME_Staging.dbo.Credential C
LEFT JOIN CredentialTypeSkillType Existing on Existing.CredentialTypeID = C.CredentialTypeID
	AND Existing.SkillTypeID = C.SkillTypeID
WHERE Existing.CredentialTypeSkillTypeID IS NULL --Prevent Dupes

PRINT 'Credential'
INSERT INTO Credential (
	ClientID
	,CreatedBy
	,CreatedDate
	,OwnedByOrgID
	,Restriction
	,CredentialTypeID
	,CredentialTypeSkillTypeID
	,Description
	,IssuingInstitution
	,IssuedDate
	,LegacyID
	)
SELECT C.EntityID
	,11 AS CreatedBy
	,GETUTCDATE() AS CreatedDate
	,C.OwnedByOrgID
	,1 as Restriction
	,XP.CredentialTypeID
	,CTST.CredentialTypeSkillTypeID
	,ISNULL(XP.[Description],'Imported') AS [Description]
	,ISNULL(XP.IssuingInstitution,'') AS IssuingInstitution
	,XP.IssuedDate
	,XP.CredentialID AS LegacyID
FROM REPLACE_ME_Staging.dbo.Credential XP
INNER JOIN Client C ON C.LegacyID = XP.ClientID
INNER JOIN CredentialTypeSkillType CTST ON CTST.CredentialTypeID = XP.CredentialTypeID
	AND CTST.SkillTypeID = XP.SkillTypeID
LEFT JOIN [Credential] CD ON CD.CredentialTypeSkillTypeID = CTST.CredentialTypeSkillTypeID
	AND CD.ClientID = C.EntityID
WHERE CD.CredentialID IS NULL --Prevent Dupes
