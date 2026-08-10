USE REPLACE_ME_ETL
GO

------------------------------------ ProviderReferral -----------------------------------------------
IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
		WHERE COLUMN_NAME = 'LegacyID' AND TABLE_NAME = 'ProviderReferral')
BEGIN
	ALTER TABLE [ProviderReferral] ADD LegacyID VARCHAR(20) NULL
END
GO

INSERT dbo.[ProviderReferral] (
	ClientID
	,ReferFromProviderID
	,ReferToProviderID
	,ReferToUserID
	,ServiceTypeID
	,EnrollmentID
	,ReferralDate
	,ReferralStatus
	,Restriction
	,CreatedBy
	,LegacyID
	,CreatedDate
	)
SELECT DISTINCT
	EC.EntityID AS ClientID
	,EP.EntityID 'ReferFromProviderID'
	,EPP.EntityID 'ReferToProviderID'
	,U.EntityID 'ReferToUserID'
	,ST.ServiceTypeID
	,E.EnrollmentID
	,ReferralDate
	,ReferralStatus
	,ISNULL(PR.Restriction, 1) AS Restriction
	,11 AS CreatedBy
	,ProviderReferralID
	,ISNULL(PR.CreatedDate,GETUTCDATE()) AS CreatedDate
FROM Replace_Me_Staging.DBO.[ProviderReferral] PR
INNER JOIN Client EC ON EC.LegacyID = PR.ClientID
INNER JOIN ServiceType ST ON ST.LegacyID = PR.ServiceTypeID
LEFT JOIN Enrollment E ON E.LegacyID = PR.EnrollmentID
LEFT JOIN Users U on U.LegacyID = PR.RefertoUserID
INNER JOIN Provider EP ON EP.LegacyID = PR.ReferFromProviderID
INNER JOIN Provider EPP ON EPP.LegacyID = PR.ReferToProviderID

----------------------------------Client EntityContact--------------------------------------
IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE COLUMN_NAME = 'LegacyID' AND TABLE_NAME = 'EntityContact')
BEGIN
	ALTER TABLE EntityContact ADD LegacyID VARCHAR(20) NULL
END
GO

PRINT 'EntityContact For Clients'
INSERT dbo.Entity (
	EntityTypeID
	,EntityName
	,CreatedBy
	,CreatedDate
	,OwnedByOrgID
	)
SELECT 5 'EntityTypeID'
	,ContactID AS EntityName
	,CASE WHEN U1.EntityID IS NOT NULL THEN U1.EntityID
		WHEN U2.EntityID IS NOT NULL THEN U2.EntityID
		ELSE 11
		END AS CreatedBy
	,ISNULL(C.BeginDate, GETUTCDATE()) AS CreatedDate
	,Cl.OwnedByOrgID
FROM Replace_Me_Staging.dbo.EntityContact C
INNER JOIN Client Cl ON C.ParentEntityID = Cl.LegacyID --If importing for non-imported client, change to Cl.EntityID
LEFT JOIN EntityContact ET ON ET.LegacyID = C.ContactID
LEFT JOIN Users U1 on U1.LegacyID =	C.CREATEDBY --For imported users
LEFT JOIN Users U2 on U2.EntityID =	C.CREATEDBY --For existing users
WHERE ET.LegacyID IS NULL
AND C.EntityContextType = 11 --Client Contact Type

PRINT 'EntityContact - Client'
INSERT dbo.EntityContact (
	EntityID
	,ParentEntityID
	,LastName
	,FirstName
	,BeginDate
	,EndDate
	,IsEmergencyContact
	,RelationshipID
	,CreatedBy
	,CreatedDate
	,OwnedByOrgID
	,Restriction
	,LegacyID
	)
SELECT DISTINCT
	E.EntityID
	,C.EntityID AS ParentEntityID
	,LEFT(EC.ContactLastName, 100) AS ContactLastName
	,LEFT(EC.ContactFirstName, 100) AS ContactFirstName
	,ISNULL(EC.BeginDate, '1/1/1900') AS BeginDate
	,ISNULL(EC.EndDate, '9999-12-31') AS EndDate
	,EC.IsEmergencyContact
	,EC.RelationshipTypeID AS RelationshipTypeID
	,11 AS CreatedBy
	,GETUTCDATE() AS CreatedDate
	,C.OwnedByOrgID AS OwnedByOrgID
	,1 AS Restriction
	,EC.ContactID
FROM dbo.Entity E
INNER JOIN Replace_Me_Staging.dbo.EntityContact EC ON E.EntityName = EC.ContactID
LEFT JOIN Client C ON C.LegacyID = EC.PARENTENTITYID
LEFT JOIN EntityContact EC2 ON EC2.EntityID = E.EntityID
WHERE EC2.EntityID IS NULL

/* Address needs to be added for Client EntityContacts to make the default zip = 00000 */
PRINT 'Address for Entity Contacts'
INSERT INTO Address (
	ContextType
	,ContextID
	,Address1
	,ZipCode
	,AddressType
	,BeginDate
	,EndDate
	,Restriction
	,CreatedBy
	,OwnedByOrgID
	)
SELECT 11 AS ContextType
	,EC.EntityID AS ContextID
	,ISNULL(C.Address1, '') AS Address1
	,CASE
		WHEN LEFT(C.ZipCode, 5) IN (SELECT ZipCode FROM ZipCode)
		THEN LEFT(C.ZipCode, 5)
		ELSE '00000'
		END AS ZipCode
	,1 AS AddressType
	,ISNULL(C.BeginDate,GETUTCDATE()) AS BeginDate
	,'9999-12-31' AS EndDate
	,1 AS Restriction
	,11 AS CreatedBy
	,EC.OwnedByOrgID AS OwnedByOrgID
FROM EntityContact EC
INNER JOIN Replace_Me_Staging.dbo.EntityContact C ON C.ContactID = EC.LegacyID
LEFT JOIN Address A on A.Address1 = ISNULL(C.Address1, '')
	AND A.ContextID = EC.EntityID
	AND A.ContextType = 11
WHERE LegacyID IN (SELECT ContactID FROM Replace_Me_Staging.dbo.EntityContact	)
	AND C.EntityContextType = 11 --Client Context
	AND A.AddressID IS NULL

/* These next two are required to backfill the City and State based on the zip code. */
PRINT 'Backfill City and State'
UPDATE A
SET City = ISNULL(A.City,CityName)
,[State] = ISNULL(A.[State],Z.[STATE])
FROM ZipCode Z
INNER JOIN Address A ON A.ZipCode = Z.ZipCode
INNER JOIN EntityContact EC ON EC.EntityID = A.ContextID
INNER JOIN Replace_Me_Staging.dbo.EntityContact C on C.ContactID = EC.LegacyID
WHERE EC.LegacyID IS NOT NULL
AND (A.[City] IS NULL OR A.[State] IS NULL)

--Clean up Phone numbers by removing special characters
--Removing: - ) ( and whitespace
UPDATE C
SET
HomePhone =  REPLACE(  REPLACE(  REPLACE(  REPLACE(HomePhone, '-', '') ,'(','') ,')','') ,' ','')
,CellPhone = REPLACE(  REPLACE(  REPLACE(  REPLACE(CellPhone, '-', '') ,'(','') ,')','') ,' ','')
,WorkPhone = REPLACE(  REPLACE(  REPLACE(  REPLACE(WorkPhone, '-', '') ,'(','') ,')','') ,' ','')
FROM Replace_Me_Staging.dbo.EntityContact C

/* This is required for phone numbers */
PRINT 'EntityContactPreference'
INSERT INTO EntityContactPreference (
	EntityID
	,PhoneVoiceOptIn
	,PhoneTextOptIn
	,EmailOptIn
	,HomePhoneType
	,CellPhoneType
	,WorkPhoneType
	,HomePhone
	,CellPhone
	,WorkPhone
	,Email
	,CreatedDate
	,CreatedBy
	,WorkPhoneExt
	,FaxNumber
	)
SELECT EC.EntityID
	,NULL AS PhoneVoiceOptIn
	,NULL AS PhoneTextOptIn
	,NULL AS EmailOptIn
	,NULL AS HomePhoneType
	,1 AS CellPhoneType
	,2 AS WorkPhoneType
	,CASE WHEN LEN(C.HomePhone) = 10 THEN SUBSTRING(REPLACE(C.HomePhone, '-', ''), 1, 3) + '-' + SUBSTRING(C.HomePhone, 4, 3) + '-' + SUBSTRING(C.HomePhone, 7, 4)
		WHEN LEN(C.HomePhone) = 7 THEN '000-' + SUBSTRING(C.HomePhone, 1, 3) + '-' + SUBSTRING(REPLACE(C.HomePhone, '-', ''), 4, 4)
		END AS HomePhone
	,CASE WHEN LEN(C.CellPhone) = 10 THEN SUBSTRING(C.CellPhone, 1, 3) + '-' + SUBSTRING(C.CellPhone, 4, 3) + '-' + SUBSTRING(C.CellPhone, 7, 4)
		WHEN LEN(C.CellPhone) = 7 THEN '000-' + SUBSTRING(C.CellPhone, 1, 3) + '-' + SUBSTRING(C.CellPhone, 4, 4)
		END AS CellPhone
	,CASE WHEN LEN(C.WorkPhone) = 10 THEN SUBSTRING(C.WorkPhone, 1, 3) + '-' + SUBSTRING(C.WorkPhone, 4, 3) + '-' + SUBSTRING(C.WorkPhone, 7, 4)
		WHEN LEN(C.WorkPhone) = 7 THEN '000-' + SUBSTRING(C.WorkPhone, 1, 3) + '-' + SUBSTRING(C.WorkPhone, 4, 4)
		END AS WorkPhone
	,C.Email
	,GETUTCDATE() AS CreatedDate
	,11 AS CreatedBy
	,NULL AS WorkPhoneExt
	,NULL AS FaxNumber
FROM EntityContact EC
INNER JOIN Replace_Me_Staging.dbo.EntityContact C ON EC.LegacyID = C.ContactID
LEFT JOIN EntityContactPreference ECP ON ECP.EntityID = EC.EntityID
WHERE EC.LegacyID IS NOT NULL
AND ECP.EntityID IS NULL--Prevent Dupes

PRINT 'EntityContactTypeCategory - Client Contacts'
INSERT INTO EntityContactTypeCategory (
	EntityID
	,EntityContactTypeCategoryTypeID
	,CreatedDate
	)
SELECT DISTINCT
	EC.EntityID
	,EC2.EntityContactTypeCategoryTypeID
	,EC.CreatedDate
FROM EntityContact EC
INNER JOIN Replace_Me_Staging.dbo.EntityContact EC2 on EC.LegacyID = EC2.ContactID
LEFT JOIN EntityContactTypeCategory ECTC on ECTC.EntityContactTypeCategoryTypeID = EC2.EntityContactTypeCategoryTypeID
	AND ECTC.EntityID = EC.EntityID
WHERE EC2.EntityContactTypeCategoryTypeID IS NOT NULL

PRINT 'EntityContactTypeCategory - Added category for emergency contacts'
INSERT INTO EntityContactTypeCategory (
	EntityID
	,EntityContactTypeCategoryTypeID
	,CreatedDate
	)
SELECT DISTINCT
	EC.EntityID
	,38 AS EntityContactTypeCategoryTypeID --EmergencyContactType
	,EC.CreatedDate
FROM EntityContact EC
INNER JOIN Replace_Me_Staging.dbo.EntityContact EC2 on EC.LegacyID = EC2.ContactID
	AND EC2.IsEmergencyContact = 1 --Must be flagged as emergency
LEFT JOIN EntityContactTypeCategory ECTC on ECTC.EntityContactTypeCategoryTypeID = 38
	AND ECTC.EntityID = EC.EntityID
WHERE ECTC.EntityContactTypeCategoryTypeID IS NULL

/* Not really used much, but let in */
PRINT 'EntityDemographic - Client Contact'
INSERT INTO EntityDemographic (entityid)
SELECT EntityID
FROM EntityContact
WHERE LegacyID IS NOT NULL
	AND EntityID NOT IN (SELECT EntityID FROM EntityDemographic	)

------------------------------ EntityContact - Provider -----------------------------------
PRINT 'EntityContact Entity'
INSERT dbo.Entity (
	EntityTypeID
	,EntityName
	,CreatedBy
	,CreatedDate
	)
SELECT
	5 AS EntityTypeID
	,ContactID 'EntityName'
	,1 'CreatedBy'
	,ISNULL(C.BeginDate, '1/1/1900')
FROM Replace_Me_Staging.dbo.EntityContact C
LEFT JOIN Provider P ON P.LegacyID = C.ParentEntityID
WHERE P.LegacyID IS NOT NULL
AND C.EntityContextType = 84 --Provider Context Type

PRINT 'EntityContact - Provider'
INSERT dbo.EntityContact (
	EntityID
	,ParentEntityID
	,LastName
	,FirstName
	,BeginDate
	,EndDate
	,Email
	,IsEmergencyContact
	,CreatedBy
	,CreatedDate
	,OwnedByOrgID
	,Restriction
	,LegacyID
	)
SELECT DISTINCT E.EntityID
	,P.EntityID AS ParentEntityID
	,LEFT(ContactLastName, 100) AS ContactLastName
	,LEFT(ContactFirstName, 100) AS ContactFirstName
	,ISNULL(C.BeginDate,GETUTCDATE()) AS BeginDate
	,'9999-12-31' AS EndDate
	,LEFT(C.Email, 100) AS Email
	,IsEmergencyContact
	,11 AS CreatedBy
	,GETUTCDATE() AS CreatedDate
	,P.OrganizationID AS OwnedByOrgID
	,1 AS Restriction
	,C.ContactID AS LegacyID
FROM dbo.Entity E
INNER JOIN Replace_Me_Staging.dbo.EntityContact C ON E.EntityName =  C.ContactID
	AND C.EntityContextType = 84 --ContextType for Provider Contacts
INNER JOIN Provider P ON P.LegacyID = C.ParentEntityID
WHERE E.EntityTypeID = 5

/* This is required for Address */
PRINT 'Address - Provider'
INSERT INTO Address (
	ContextType
	,ContextID
	,Address1
	,Address2
	,ZipCode
	,City
	,[State]
	,AddressType
	,BeginDate
	,EndDate
	,Restriction
	,CreatedBy
	,CreatedDate
	,OwnedByOrgID
	)
SELECT EntityContextType AS ContextType -- 84 = Provider Contacts
	,EC.EntityID AS ContextID
	,ISNULL(C.Address1, '') AS Address1
	,C.Address2
	,CASE 	WHEN LEFT(C.ZipCode, 5) IN (
				SELECT ZipCode
				FROM ZipCode
				)
			THEN LEFT(C.ZipCode, 5)
		ELSE '00000'
		END AS ZipCode
	,(	SELECT CityName
		FROM ZipCode Z
		WHERE Z.ZipCode = LEFT(C.ZipCode, 5)
		) AS City
	,(	SELECT [State]
		FROM ZipCode Z
		WHERE Z.ZipCode = LEFT(C.ZipCode, 5)
		) AS STATE
	,1 AS AddressType
	,C.BeginDate
	,'9999-12-31' AS EndDate
	,1 AS Restriction
	,11 AS CreatedBy
	,EC.CreatedDate AS CreatedDate
	,EC.OwnedByOrgID AS OwnedByOrgID
FROM EntityContact EC
INNER JOIN Replace_Me_Staging.dbo.EntityContact C ON EC.LegacyID = C.ContactID
	AND C.EntityContextType = 84
LEFT JOIN [Address] A ON A.ContextID = EC.EntityID
	AND A.ContextType = 84
WHERE A.AddressID IS NULL

/* This is required for phone numbers */
PRINT 'EntityContactPreference'
INSERT INTO EntityContactPreference (
	EntityID
	,PhoneVoiceOptIn
	,PhoneTextOptIn
	,EmailOptIn
	,HomePhone
	,HomePhoneType
	,CellPhone
	,CellPhoneType
	,WorkPhone
	,WorkPhoneType
	,Email
	,CreatedDate
	,CreatedBy
	)
SELECT EC.EntityID
	,NULL AS PhoneVoiceOptIn
	,NULL AS PhoneTextOptIn
	,NULL AS EmailOptIn
	,(SUBSTRING(REPLACE(C.HomePhone, '-', ''), 1, 3) + '-' + SUBSTRING(REPLACE(C.HomePhone, '-', ''), 4, 3) + '-' + SUBSTRING(REPLACE(C.HomePhone, '-', ''), 7, 4)) AS HomePhone
	,3 AS HomePhoneType
	,(SUBSTRING(REPLACE(C.CellPhone, '-', ''), 1, 3) + '-' + SUBSTRING(REPLACE(C.CellPhone, '-', ''), 4, 3) + '-' + SUBSTRING(REPLACE(C.CellPhone, '-', ''), 7, 4)) AS CellPhone
	,2 AS CellPhoneType
	,(SUBSTRING(REPLACE(C.WorkPhone, '-', ''), 1, 3) + '-' + SUBSTRING(REPLACE(C.WorkPhone, '-', ''), 4, 3) + '-' + SUBSTRING(REPLACE(C.WorkPhone, '-', ''), 7, 4)) AS WorkPhone
	,1 AS WorkPhoneType
	,EC.Email
	,EC.CreatedDate
	,EC.CreatedBy
FROM EntityContact EC
INNER JOIN Replace_Me_Staging.dbo.EntityContact C ON EC.LegacyID = C.ContactID
LEFT JOIN EntityContactPreference ECP ON ECP.EntityID = EC.EntityID
WHERE ECP.EntityID IS NULL

------------------------------------------------- ProviderReferralOther
IF NOT EXISTS (	SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
WHERE COLUMN_NAME = 'LegacyID' AND TABLE_NAME = 'ProviderReferralOther')
BEGIN
	ALTER TABLE dbo.ProviderReferralOther ADD LegacyID VARCHAR(20) NULL
END
GO

/* Note this uses the provider sheet to create ProviderReferralOther */
INSERT INTO ProviderReferralOther (OtherName
,Address,Address2,City,State,ZipCode,CreatedBy,CreatedDate,ProviderID,EIN,Email,Fax,Phone
,LastModifiedDate,LastModifiedBy,OwnedByOrgID,LegacyID)
SELECT P.ProviderName AS OtherName
,P.ADDRESS
,P.ADDRESS2
,P.City
,P.State
,P.ZipCode
,11 AS CreatedBy
,GETUTCDATE() AS CreatedDate
,P2.EntityID AS ProviderID
,NULL AS EIN
,P.Email
,P.FAX
,P.PHONE
,GETUTCDATE() AS LastModifiedDate
,11 AS LastModifiedBy
,P2.OrganizationID
,P.ProviderID AS LegacyID
FROM Replace_Me_Staging.[dbo].[Provider] P
INNER JOIN Provider P2 on P2.legacyid = P.ProviderID
LEFT JOIN ProviderReferralOther PR ON PR.LegacyID = P.ProviderID
WHERE PR.ReferralOtherID IS NULL
