USE REPLACE_ME_ETL
GO

--------------------- Organization -----------------------------------------------
IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'Organization' AND COLUMN_NAME = 'LegacyID')
BEGIN
	ALTER TABLE dbo.Organization ADD LegacyID VARCHAR(20) NULL;
END
GO

PRINT 'Organization Entity'
INSERT dbo.Entity (
	EntityTypeID
	,EntityName
	,CreatedBy
	,CreatedDate
	)
SELECT DISTINCT
	2 AS EntityTypeID
	,OrganizationID
	,11 AS CreatedBy
	,GETUTCDATE() AS CreatedDate
FROM REPLACE_ME_STAGING.dbo.Organization
WHERE OrganizationID NOT IN (
		SELECT LegacyID
		FROM Organization
		WHERE LegacyID IS NOT NULL
		)
GO

PRINT 'Organization'
INSERT INTO dbo.Organization (
	EntityID
	,CreatedBy
	,CreatedDate
	,OrgName
	,PWChangeDays
	,AllowExcel
	,AllowPrint
	,EnableTimeLogging
	,AutoLogoutMinutes
	,[LockoutAfterAttempts]
	--,[DefaultProviderID]
	,LegacyID
	)
SELECT DISTINCT E.EntityID
	,11 AS Createdby
	,O.CreatedDate
	,O.OrgName
	,ISNULL(O.PWChangeDays,45) 'PWChangeDays'
	,ISNULL(O.AllowExcel,1) 'AllowExcel'
	,ISNULL(O.AllowPrint,1) 'AllowPrint'
	,ISNULL(O.EnableTimeLogging,0) 'EnableTimeLogging'
	,ISNULL(O.AutoLogoutMinutes,30) 'AutoLogoutMinutes'
	,O.[LockoutAfterAttempts]
	--,[DefaultProviderID]
	,CAST(CONVERT(NUMERIC, O.OrganizationID) AS VARCHAR) AS LegacyID -- O.OrganizationID AS LegacyID
FROM dbo.Entity E
INNER JOIN REPLACE_ME_STAGING.dbo.Organization O  ON E.EntityName = Cast(OrganizationID AS VARCHAR)
LEFT JOIN Organization EO ON EO.LegacyID = O.OrganizationID
WHERE EntityTypeID = 2
	AND EO.LegacyID IS NULL

--Update ClientId of Entity Table to LastName, FirstName combination
PRINT 'Update EntityName'
UPDATE E
SET E.EntityName = OrgName
FROM dbo.Entity E
INNER JOIN REPLACE_ME_STAGING.dbo.Organization U ON E.EntityName = Cast(OrganizationID AS VARCHAR)
WHERE E.EntityTypeID = 2
GO

----------------------- PROVIDER ----------------------
IF NOT EXISTS (	SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE COLUMN_NAME = 'LegacyID' AND TABLE_NAME = 'Provider')
BEGIN
	ALTER TABLE dbo.Provider ADD LegacyID VARCHAR(20) NULL
END
GO


PRINT 'Provider Entity'
INSERT Entity (
	EntityTypeID
	,EntityName
	,CreatedBy
	,CreatedDate
	,OwnedByOrgID
	)
SELECT DISTINCT
	4 AS EntityTypeID
	,ProviderID
	,11 AS CreatedBy
	,GETUTCDATE() AS CreatedDate
FROM REPLACE_ME_STAGING.[dbo].[Provider] SP
LEFT JOIN Provider P ON P.LegacyID = SP.ProviderID
INNER JOIN Organization O ON O.LegacyID = SP.ORGANIZATIONID --Must change to O.EntityID if org already exists.
WHERE SP.ProviderID IS NOT NULL
	and P.EntityID IS NULL --Make sure legacyID is not match

/* Clean up phone # and Fax by removing special characters
	Removing: - ) ( and whitespace */
UPDATE P
SET [Phone] =  REPLACE(  REPLACE(  REPLACE(  REPLACE([Phone], '-', '') ,'(','') ,')','') ,' ','')
,[Fax] = REPLACE(  REPLACE(  REPLACE(  REPLACE([Fax], '-', '') ,'(','') ,')','') ,' ','')
FROM REPLACE_ME_STAGING.dbo.[Provider] P

/* Run this is customer has international +1 in their phone numbers */
--UPDATE C
--SET Phone =  REPLACE(Phone, '+1', '')
--FROM REPLACE_ME_STAGING.[dbo].[Provider] C
--WHERE LEFT(Phone,2) = '+1'
--GO

PRINT 'Provider'
INSERT INTO [dbo].[Provider] (
	[EntityID]
	,OrganizationID
	,[ProviderName]
	,[Address]
	,[Address2]
	,[City]
	,[State]
	,[ZipCode]
	,[Phone]
	,[Fax]
	,[Email]
	,[Website]
	,CreatedDate
	,EIN
	,SSN
	,TaxType
	,Latitude
	,Longitude
	,LegacyID
	,LastModifiedDate
	,LastModifiedBy
	)
SELECT DISTINCT E.EntityID AS EntityID
	,O.EntityID
	,LEFT(P.[ProviderName], 256) AS [ProviderName]
	,LEFT(P.[Address], 100) AS [Address]
	,LEFT(P.[Address2], 100) AS Address2
	,LEFT(P.[City], 50) AS [City]
	,LEFT(P.[State], 2) AS [State]
	,ISNULL(P.[ZipCode], '00000') AS [ZipCode]
	--,CASE WHEN LEFT(A.[Zip Code],5) IN (SELECT ZipCode FROM ZipCode) THEN LEFT(A.[Zip Code],5) ELSE '00000' END AS Zip
	,P.[Phone]
	,P.[Fax]
	,LEFT(P.[Email], 100) AS Email
	,LEFT(P.[Website], 100) AS Website
	,GETUTCDATE() AS CreatedDate
	,P.EIN
	,P.SSN
	,P.TaxType
	,P.Latitude
	,P.Longitude
	,P.ProviderID AS LegacyID
	,GETUTCDATE() AS LastModifiedDate
	,11 AS LastModifiedBy
FROM dbo.Entity E
INNER JOIN REPLACE_ME_STAGING.[dbo].[Provider] P ON E.EntityName = Convert(varchar,P.ProviderID)
INNER JOIN Organization O ON O.LegacyID = P.OrganizationID --Must change to O.EntityID if org already exists.
LEFT JOIN [Provider] P2 ON P2.LegacyID = P.ProviderID
WHERE P2.EntityID IS NULL
AND P.[ProviderName] IS NOT NULL
GO

/* Add Provider phone number */
PRINT 'EntityContactPreference - Provider'
INSERT INTO EntityContactPreference (
	EntityID
	,WorkPhone
	,Email
	,FaxNumber
	,CreatedDate
	,CreatedBy
	,LastModifiedDate
	,LastModifiedBy
	)
SELECT DISTINCT P.EntityID
	,CASE WHEN LEN(SU.Phone) = 10 THEN SUBSTRING(REPLACE(SU.Phone, '-', ''), 1, 3) + '-' + SUBSTRING(SU.Phone, 4, 3) + '-' + SUBSTRING(SU.Phone, 7, 4)
		WHEN LEN(SU.Phone) = 7 THEN '000-' + SUBSTRING(SU.Phone, 1, 3) + '-' + SUBSTRING(REPLACE(SU.Phone, '-', ''), 4, 4)
		END AS Phone
	,LEFT(SU.Email, 100) AS Email
	,CASE WHEN LEN(SU.Fax) = 10 THEN SUBSTRING(REPLACE(SU.Fax, '-', ''), 1, 3) + '-' + SUBSTRING(SU.Fax, 4, 3) + '-' + SUBSTRING(SU.Fax, 7, 4)
		WHEN LEN(SU.Fax) = 7 THEN '000-' + SUBSTRING(SU.Fax, 1, 3) + '-' + SUBSTRING(REPLACE(SU.Fax, '-', ''), 4, 4)
		END AS Fax
	,E.CreatedDate
	,11 AS CreatedBy
	,GETUTCDATE() AS LastModifiedDate
	,11 AS LastModifiedBy
FROM Provider P
INNER JOIN REPLACE_ME_STAGING.dbo.Provider SU ON P.LegacyID = SU.ProviderID
INNER JOIN Entity E ON E.EntityID = P.EntityID
LEFT JOIN EntityContactPreference ECP ON ECP.EntityID = E.EntityID
WHERE ECP.EntityID IS NULL

------------------------ ProviderTypeCategory ----------------------------------
PRINT 'ProviderTypeCategory'
INSERT ProviderTypeCategory (EntityID, ProviderTypeCategoryTypeID)
SELECT DISTINCT EP.EntityID , ISNULL(SP.ProviderTypeCategoryTypeID,4)
FROM REPLACE_ME_STAGING.[dbo].[Provider] SP
INNER JOIN Provider EP ON SP.ProviderID = EP.LegacyID
WHERE EP.EntityID NOT IN (SELECT EntityID FROM ProviderTypeCategory)
--AND SP.ProviderTypeCategoryTypeID IS NOT NULL --Uncomment if you don't want them defaulted as 4/provider

/* Add Master Providers to ProviderTypeCategory
PRINT 'ProviderTypeCategoryType = Master Provider'
INSERT ProviderTypeCategory
SELECT DISTINCT
P.EntityID
,1000 AS ProviderTypeCategorytypeID		-- type = Master Provider
FROM Provider P
WHERE LegacyID in (
SELECT DISTINCT OrgNo FROM REPLACE_ME_STAGING.dbo.Provider
WHERE  --------------------------------------- This needs work. See ParentEntityID in the Staging db. Don't think there is an equivalent in the spreadsheet.
)
*/
-------------------------- ProviderHMIS ------------------------------------------
----PRINT 'ProviderHMIS'
----INSERT ProviderHMIS (
----	ProviderID
----	,SiteConfigurationType
----	,GeoCode
----	,SiteType
----	,PrimaryHousingType
----	,GranteeIndentifier
----	,GeographyType
----	)
----SELECT DISTINCT EP.EntityID
----	,SiteConfigurationType
----	,GeoCode
----	,SiteType
----	,PrimaryHousingType
----	,GranteeIndentifier
----	,GeographyType
----FROM REPLACE_ME_STAGING.DBO.[Provider] P
----INNER JOIN Provider EP ON P.ProviderID = EP.LegacyID
----WHERE GeoCode IS NOT NULL
----	AND SiteConfigurationType IS NOT NULL
----	AND SiteType IS NOT NULL
----	AND EP.EntityID NOT IN (
----		SELECT ProviderID
----		FROM ProviderHMIS
----		)

-------- Update Organization.DefaultProviderID -----------------------
Print 'Update Organization.DefaultProviderID'
UPDATE EO
SET EO.DefaultProviderID = P.EntityID
FROM Provider P
INNER JOIN REPLACE_ME_STAGING.DBO.Organization O ON O.DefaultProviderID = P.LegacyID
INNER JOIN Organization EO ON EO.LegacyID = O.OrganizationID		--Must change to OE.EntityID if org already exists.
WHERE O.DefaultProviderID IS NOT NULL

---------------------------------- USERS ------------------------------------
IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE COLUMN_NAME = 'LegacyID' AND TABLE_NAME = 'Users')
BEGIN
	ALTER TABLE Users ADD LegacyID VARCHAR(20) NULL
END
GO

PRINT 'Update LegacyIDs for existing users, match by username'
UPDATE U
SET LegacyID = UserID
FROM Users U
INNER JOIN REPLACE_ME_STAGING.dbo.Users U2 ON U2.UserName = U.UserName
WHERE LegacyID IS NULL

PRINT 'Entity - Users'
INSERT dbo.Entity (
	EntityTypeID
	,EntityName
	,CreatedBy
	,CreatedDate
	,OwnedByOrgID
	)
SELECT 1 AS EntityTypeID
	,UserID AS  'EntityName'
	,11 'CreatedBy'
	,GETUTCDATE() 'CreatedDate'
	,O.EntityID 'OwnedByOrgID'
FROM REPLACE_ME_STAGING.dbo.Users U1
LEFT JOIN Users U2 on U2.LegacyID = U1.UserID
INNER JOIN Organization O on O.EntityID = U1.ORGANIZATIONID --If uploading orgs, change join to legacyID
WHERE U2.EntityID IS NULL

/* DEFAULT PASSWORD: TGP,12345cw (Already hashed)
 If using a custom user password, you'll need to create a dummy user on the front end w/ that pw
 and copy that user's pw to other users using an update script. */
PRINT 'Users'
INSERT INTO dbo.Users (
	EntityID
	,UserName
	,Password
	,FirstName
	,LastName
	,EmailAddress
	,OrganizationID
	,DefaultOrganizationID
	,ProviderID
	,DefaultProviderID
	,RoleID
	,UserTypeID
	,isActive
	,EnableTimeLogging
	,AllowPrint
	,AllowExcel
	,AccountLockOut
	,LoginFailedCount
	,DefaultRoleID
	,isSupervisor
	,LegacyID
	,IsChangePW
	--,PortalRoleID				--If using portal, uncomment
	--,DefaultPortalRoleID		--If using portal, uncomment
	)
SELECT DISTINCT E.EntityID
	,CASE
		WHEN U.UserName IS NULL
		THEN SUBSTRING(U.FirstName, 1, 1) + ISNULL(U.LastName, '')
		ELSE U.UserName
	END AS UserName
	,0xBA6F4DCD59D6180656831EDFBB95497200B10F4E3AA9EBFAC2FE358579C5945E75CDC99F922EEC045B4860F7FDBAC669A8E99FF5D8D47524A75DD1684CA241133DCE2D3C23235DBC50FBDA87B6C980B7000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000 AS [Password]
	,U.FirstName AS Firstname
	,U.LastName AS LastName
	,U.EmailAddress
	,O.EntityID AS OrganizationID
	,O.EntityID AS DefaultOrganizationID
	,P.EntityID AS ProviderID
	,P.EntityID AS DefaultProviderID
	,ISNULL(R.RoleID, 2) AS DefaultRoleID
	,TRY_CONVERT(INT,ISNULL(U.UserTypeID, 2)) AS UserTypeID
	,TRY_CONVERT(bit,ISNULL(U.isActive, 1)) AS IsActive
	,ISNULL(TRY_CONVERT(bit,U.EnableTimeLogging), 0) AS EnableTimeLogging
	,ISNULL(TRY_CONVERT(bit,U.AllowPrint), 1) AS AllowPrint
	,ISNULL(TRY_CONVERT(bit,U.AllowExcel), 1) AS AllowExcel
	,0 AS AccountLockOut
	,0 AS LoginFailedCount
	,ISNULL(R.RoleID, 2) AS DefaultRoleID
	,ISNULL(TRY_CONVERT(bit,isSupervisor),0) AS isSupervisor
	,U.UserID AS LegacyID
	,1 AS IsChangePW
	--,ISNULL(R.RoleID, 2) AS PortalRoleID			--If using portal, uncomment
	--,ISNULL(R.RoleID, 2) AS DefaultPortalRoleID	--If using portal, uncomment
FROM dbo.Entity E
INNER JOIN REPLACE_ME_STAGING.dbo.Users U ON E.EntityName = Convert(varchar,U.UserID)
INNER JOIN Organization O on U.OrganizationID = O.LegacyID 	---Change to legacyID if customer importing orgs
INNER JOIN Provider P on U.ProviderID = P.EntityID 	---Change to legacyID if customer importing orgs
LEFT JOIN RoleDefinition R on Convert(varchar(100),R.RoleID) = U.DefaultRoleID
WHERE (EMAILADDRESS LIKE '%@%' OR EMAILADDRESS IS NULL) --Remove invalid email rows

/* Insert User addresses so the zip code won't be blank */
PRINT 'User Address'
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
	,CreatedDate
	,OwnedByOrgID
	)
SELECT 84 AS ContextType
	,U.EntityID AS ContextID
	,'' AS Address1
	,'00000' AS ZipCode
	,1 AS AddressType
	,E.CreatedDate
	,'9999-12-31' AS EndDate
	,1 AS Restriction
	,E.CreatedBy
	,E.CreatedDate
	,U.OrganizationID
FROM Users U
INNER JOIN REPLACE_ME_STAGING.dbo.Users C ON U.LegacyID = C.UserID
INNER JOIN Entity E ON E.EntityID = U.EntityID
WHERE U.LegacyID IS NOT NULL
AND U.EntityID NOT IN (SELECT ContextID FROM Address WHERE ContextType = 84)

/* Add Users phone number and email address */
PRINT 'EntityContactPreference - User'
INSERT INTO EntityContactPreference (
	EntityID
	,WorkPhone
	,CellPhone
	,Email
	,CreatedDate
	,DeletedDate
	,CreatedBy
	)
SELECT U.EntityID
	,SU.OfficePhone
	,SU.CellPhone
	,SU.EmailAddress
	,E.CreatedDate
	,'9999-12-31' AS DeletedDate
	,E.CreatedBy
FROM Users U
INNER JOIN REPLACE_ME_STAGING.dbo.Users SU ON U.LegacyID = SU.UserID
INNER JOIN Entity E ON E.EntityID = U.EntityID
AND U.EntityID NOT IN (SELECT EntityID FROM EntityContactPreference)
AND SU.UserID NOT IN (SELECT CLIENTID FROM REPLACE_ME_STAGING.dbo.Client
					WHERE ISPORTALCLIENT = '1') --Client ECP will be created below

/* Need to set supervisors after the fact because they need the EntityIDs that were
created when users where imported. *****/
PRINT 'UPDATE SupervisorUserID'
UPDATE U
SET SupervisorUserID = SuperU.EntityID
FROM Users U
INNER JOIN REPLACE_ME_STAGING.dbo.Users SU ON SU.UserID = U.LegacyID
INNER JOIN Users SuperU ON SuperU.LegacyID = SU.SupervisorUserID

PRINT 'UserSupervisorHistory'
INSERT INTO UserSupervisorHistory (
	UserID
	,SupervisorID
	,SupervisorType
	,BeginDate
	,EndDate
	,CreatedBy
	,CreatedDate
	,OwnedByOrgID
)
SELECT
	U.EntityID AS UserID
	,U.SupervisorUserID AS SupervisorID
	,1 AS SupervisorType
	,GETUTCDATE() AS BeginDate
	,'9999-12-31' AS EndDate
	,11 AS CreatedBy
	,GETUTCDATE() AS CreatedDate
	,U.OrganizationID AS OwnedByOrgID
FROM Users U
WHERE LegacyID IS NOT NULL
AND SupervisorUserID IS NOT NULL


/** Insert ids into UserProviders
PRINT 'Add UserProviders'
INSERT INTO UserProviders (UserID,OrganizationID,ProviderID)
SELECT EntityID, OrganizationID, ProviderID
FROM Users
WHERE EntityID+OrganizationID+ProviderID
NOT IN (SELECT EntityID+OrganizationID+ProviderID
FROM UserProviders)

---- Then, from the staging spreadsheet if the customer provides a UserProvider table
INSERT INTO UserProviders (UserID,OrganizationID,ProviderID)
SELECT
	U.EntityID
	,P.OrganizationID
	,UP.ProviderID
FROM REPLACE_ME_STAGING.dbo.UserProviders UP
INNER JOIN Users U ON U.LegacyID = UP.UserID
INNER JOIN Provider P ON P.EntityID = UP.ProviderID
WHERE EntityID+OrganizationID+ProviderID
NOT IN (SELECT EntityID+OrganizationID+ProviderID
FROM UserProviders)
*/

---------------------------------------- Client --------------------------------------
IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE COLUMN_NAME = 'LegacyID'	AND TABLE_NAME = 'Entity')
BEGIN
	ALTER TABLE dbo.Entity ADD LegacyID VARCHAR(20) NULL
END
GO
IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE COLUMN_NAME = 'LegacyID'	AND TABLE_NAME = 'Client')
BEGIN
	ALTER TABLE dbo.Client ADD LegacyID VARCHAR(20) NULL
END
GO

PRINT 'Client Entity Non-Portal Clients'
INSERT dbo.Entity (
	EntityTypeID
	,EntityName
	,CreatedBy
	,CreatedDate
	,DeletedDate
	,OwnedByOrgID
	,LegacyID
	)
SELECT DISTINCT
	3 'EntityTypeID'
	,C.ClientID
	,11 AS CreatedBy
	,GETUTCDATE() AS CreatedDate
	,'9999-12-31' AS DeletedDate
	,C.OrganizationID
	,C.ClientID AS LegacyID
FROM REPLACE_ME_STAGING.dbo.Client C
LEFT JOIN Client CT ON CT.LegacyID = C.ClientID
LEFT JOIN REPLACE_ME_STAGING.dbo.Users U2 ON U2.UserID = C.ClientID
	AND C.IsPortalClient = '1'
LEFT JOIN Entity E ON E.LegacyID = C.ClientID
WHERE CT.LegacyID IS NULL
	AND U2.UserID IS NULL --This is for excluding portal users, who should have an entity record already
	AND C.ClientID IS NOT NULL
	AND E.EntityID IS NULL

PRINT 'Replace dashes and white space in SSN'
/* Valid SSNs should be either 4, 9, or 11 (with dashes) characters */
UPDATE C
SET SSN = TRIM(REPLACE(C.SSN, '-', ''))
FROM REPLACE_ME_STAGING.dbo.Client C

PRINT 'Fix SSN if missing leading zeroes'
UPDATE C
SET SSN = CASE
	WHEN LEN(C.SSN) < 9 AND C.SSNDATAQUALITY = 1 THEN RIGHT('000000000' + C.SSN,9)
	WHEN LEN(C.SSN) < 9 AND C.SSNDATAQUALITY IS NULL THEN RIGHT('000000000' + C.SSN,9)
	ELSE C.SSN END
FROM REPLACE_ME_STAGING.dbo.Client C
WHERE LEN(C.SSN) NOT IN (9,4)

PRINT 'Clients w/ No Portal Account'
INSERT INTO Client (
	EntityID
	,FirstName
	,MiddleName
	,LastName
	,BirthDate
	,DOBDataQuality
	,Gender
	,Pronouns
	,PrimaryLanguage
	,Race
	,Ethnicity
	,VeteranStatus
	,SSN
	,SSNDataQuality
	,CreatedDate
	,CreatedBy
	,OwnedByOrgID
	,Restriction
	,Suffix
	,ScanCardID
	,MaritalStatus
	,CitizenshipStatusID
	,EnglishProficiency
	,LegacyID
	)
SELECT DISTINCT E.EntityId
	,ISNULL(LEFT(C.FirstName, 50), 'FirstName') AS FirstName --Changed to 49chars since entityname will only allow 98 chars
	,LEFT(C.MiddleName, 50) AS MiddleName
	,ISNULL(LEFT(C.LastName, 50), 'LastName') AS LastName --Changed to 49chars since entityname will only allow 98 chars
	,C.BirthDate
	,CASE WHEN C.DOBDataQuality IN (1,2,3,4,5,99) THEN C.DOBDataQuality
		WHEN TRY_CONVERT(Date,C.BIRTHDATE) IS NOT NULL THEN 1
		ELSE NULL
		END AS DOBDataQuality
	,C.Gender
	,C.Pronouns
	,C.PrimaryLanguage
	,C.Race
	,C.Ethnicity
	,C.VeteranStatus
	,CASE
		WHEN C.SSN = '' OR C.SSN IS NULL THEN NULL
		WHEN LEN(C.SSN) = 9 THEN SUBSTRING(C.SSN, 1, 3) + '-' + SUBSTRING(C.SSN, 4, 2) + '-' + SUBSTRING(C.SSN, 6, 4)
		WHEN LEN(C.SSN) = 4 THEN 'XXX-XX-' + C.SSN
		ELSE NULL
		END AS SSN
	,CASE
		WHEN C.SSNDataQuality IN ('99','1','2') THEN C.SSNDataQuality
		WHEN C.SSN = '' OR C.SSN IS NULL THEN 99 --Unknown
		WHEN C.SSN LIKE '%X%' THEN 2 --Partial, SSNs containing X must be partial
		WHEN LEN(C.SSN) = 9 THEN 1 --Full
		WHEN LEN(C.SSN) = 4 THEN 2 --Partial
		WHEN C.SSNDataQuality IS NULL THEN 99 --Unknown
		END  AS SSNDataQuality
	,GETUTCDATE() AS CreatedDate
	,11 AS CreatedBy
	,C.OrganizationID AS OwnedByOrgID
	,ISNULL(C.Restriction,1) AS Restriction
	,C.Suffix
	,C.ScanCardID
	,C.MaritalStatus
	,C.CitizenshipStatusID
	,C.EnglishProficiency
	,CAST(C.ClientID AS VARCHAR) AS LegacyID
FROM Entity E
INNER JOIN REPLACE_ME_STAGING.dbo.Client C ON E.EntityName = C.ClientID
	AND ISNULL(C.IsPortalClient,'') != '1'	--Exclude portal clients
LEFT JOIN Client C2 on C2.LegacyID = C.ClientID
WHERE E.EntityTypeID = 3
AND C2.EntityID IS NULL --Prevent dupes
AND (ISNULL(C.SSN,'') = '' OR LEN(C.SSN) IN (4,9)) --Check for valid or blank SSN

PRINT 'Client table for clients w/ Portal User Account'
INSERT INTO dbo.Client (
	EntityID
	,FirstName
	,MiddleName
	,LastName
	,BirthDate
	,DOBDataQuality
	,Gender
	,Pronouns
	,PrimaryLanguage
	,Race
	,Ethnicity
	,VeteranStatus
	,SSN
	,SSNDataQuality
	,CreatedDate
	,CreatedBy
	,OwnedByOrgID
	,Restriction
	,Suffix
	,ScanCardID
	,MaritalStatus
	,CitizenshipStatusID
	,EnglishProficiency
	,LegacyID
	,LastModifiedDate
	,LastModifiedBy
	)
SELECT DISTINCT
	E.EntityID
	,ISNULL(LEFT(C.FirstName, 50), 'FirstName') AS FirstName --Changed to 49chars since entityname will only allow 98 chars
	,LEFT(C.MiddleName, 50) AS MiddleName
	,ISNULL(LEFT(C.LastName, 50), 'LastName') AS LastName --Changed to 49chars since entityname will only allow 98 chars
	,BirthDate
	,CASE WHEN C.DOBDataQuality IN (1,2,3,4,5,99) THEN C.DOBDataQuality
		WHEN TRY_CONVERT(Date,C.BIRTHDATE) IS NOT NULL THEN 1
		ELSE NULL
		END AS DOBDataQuality
	,Gender
	,Pronouns
	,PrimaryLanguage
	,Race
	,Ethnicity
	,VeteranStatus
	,CASE
		WHEN C.SSN = '' OR C.SSN IS NULL THEN NULL
		WHEN LEN(C.SSN) = 9 THEN SUBSTRING(C.SSN, 1, 3) + '-' + SUBSTRING(C.SSN, 4, 2) + '-' + SUBSTRING(C.SSN, 6, 4)
		WHEN LEN(C.SSN) = 4 THEN 'XXX-XX-' + C.SSN
		ELSE NULL
		END AS SSN
	,CASE
		WHEN C.SSNDataQuality IN ('99','1','2') THEN C.SSNDataQuality
		WHEN C.SSN = '' OR C.SSN IS NULL THEN 99 --Unknown
		WHEN C.SSN LIKE '%X%' THEN 2 --Partial, SSNs containing X must be partial
		WHEN LEN(C.SSN) = 9 THEN 1 --Full
		WHEN LEN(C.SSN) = 4 THEN 2 --Partial
		WHEN C.SSNDataQuality IS NULL THEN 99 --Unknown
		END  AS SSNDataQuality
	,GETUTCDATE() AS CreatedDate
	,11 AS CreatedBy
	,C.OrganizationID AS OwnedByOrgID
	,ISNULL(C.Restriction,1) AS Restriction
	,C.Suffix
	,C.ScanCardID
	,C.MaritalStatus
	,C.CitizenshipStatusID
	,C.EnglishProficiency
	,C.ClientID AS LegacyID
	,GETUTCDATE() AS LastModifiedDate
	,11 AS LastModifiedBy
FROM Entity E
INNER JOIN Users U2 on U2.EntityID = E.EntityID --Get entityid for userID
INNER JOIN REPLACE_ME_STAGING.dbo.Client C ON U2.LegacyID = C.ClientID
	AND ISNULL(C.IsPortalClient,'') = '1'	--Portal clients only
------LEFT JOIN Users U ON U.LegacyID = C.CreatedBy
LEFT JOIN Client C2 on C2.LegacyID = C.ClientID
WHERE EntityTypeID = 1 --User account
AND C2.EntityID IS NULL --Prevent dupes
AND (ISNULL(C.SSN,'') = '' OR LEN(C.SSN) IN (4,9)) --Check for valid or blank SSN
GO

--Clean up Phone numbers by removing special characters
--Removing: - ) ( and whitespace
UPDATE C
SET
HomePhone =  REPLACE(  REPLACE(  REPLACE(  REPLACE(HomePhone, '-', '') ,'(','') ,')','') ,' ','')
,CellPhone = REPLACE(  REPLACE(  REPLACE(  REPLACE(CellPhone, '-', '') ,'(','') ,')','') ,' ','')
,WorkPhone = REPLACE(  REPLACE(  REPLACE(  REPLACE(WorkPhone, '-', '') ,'(','') ,')','') ,' ','')
FROM REPLACE_ME_STAGING.dbo.Client C

PRINT 'EntityContactPreference - Client'
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
	,WorkPhoneExt
	,FaxNumber
	,LastModifiedDate
	,LastModifiedBy
	)
SELECT DISTINCT
	C.EntityID
	,DC.PhoneVoiceOptIn
	,DC.PhoneTextOptIn
	,DC.EmailOptIn
	,CASE WHEN LEN(DC.HomePhone) = 10 THEN SUBSTRING(REPLACE(DC.HomePhone, '-', ''), 1, 3) + '-' + SUBSTRING(DC.HomePhone, 4, 3) + '-' + SUBSTRING(DC.HomePhone, 7, 4)
		WHEN LEN(DC.HomePhone) = 7 THEN '000-' + SUBSTRING(DC.HomePhone, 1, 3) + '-' + SUBSTRING(REPLACE(DC.HomePhone, '-', ''), 4, 4)
		END AS HomePhone
	,ISNULL(DC.HomePhoneType, 1) AS HomePhoneType
	,CASE WHEN LEN(DC.CellPhone) = 10 THEN SUBSTRING(DC.CellPhone, 1, 3) + '-' + SUBSTRING(DC.CellPhone, 4, 3) + '-' + SUBSTRING(DC.CellPhone, 7, 4)
		WHEN LEN(DC.CellPhone) = 7 THEN '000-' + SUBSTRING(DC.CellPhone, 1, 3) + '-' + SUBSTRING(DC.CellPhone, 4, 4)
		END AS CellPhone
	,ISNULL(DC.CellPhoneType, 2) AS CellPhoneType
	,CASE WHEN LEN(DC.WorkPhone) = 10 THEN SUBSTRING(DC.WorkPhone, 1, 3) + '-' + SUBSTRING(DC.WorkPhone, 4, 3) + '-' + SUBSTRING(DC.WorkPhone, 7, 4)
		WHEN LEN(DC.WorkPhone) = 7 THEN '000-' + SUBSTRING(DC.WorkPhone, 1, 3) + '-' + SUBSTRING(DC.WorkPhone, 4, 4)
		END AS WorkPhone
	,ISNULL(DC.WorkPhoneType, 3) AS WorkPhoneType
	,DC.Email
	,C.CreatedDate
	,C.CreatedBy
	,NULL AS WorkPhoneExt
	,NULL AS FaxNumber
	,GETUTCDATE() AS LastModifiedDate
	,11 AS LastModifiedBy
FROM Client C
INNER JOIN REPLACE_ME_STAGING.dbo.Client DC ON DC.ClientID = C.LegacyID
LEFT JOIN EntityContactPreference ECP ON ECP.EntityID = C.EntityID
WHERE ECP.EntityID IS NULL


PRINT 'ClientSummaryInfo - Client'
INSERT INTO ClientSummaryInfo (
	ClientID
	,CreatedBy
	,SexualOrientation
	--,MedicaidID
	--,MedicareID
	)
SELECT DISTINCT
	C.EntityID
	,C.CreatedBy
	,DC.SexualOrientation
	--,DC.MedicaidID
	--,DC.MedicareID
FROM Client C
INNER JOIN REPLACE_ME_STAGING.dbo.Client DC ON DC.ClientID = C.LegacyID
LEFT JOIN ClientSummaryInfo CSI ON CSI.ClientID = C.EntityID
WHERE CSI.Clientid IS NULL


PRINT 'Client Alias'
INSERT INTO ClientAlias (
	ClientID
	,CreatedBy
	,Alias
	,ownedbyorgid
	,restriction
	,createddate
	)
SELECT
	C.EntityID
	,C.CreatedBy
	,DC.Alias
	,C.OwnedbyOrgID
	,1 'Restriction'
	,C.CreatedDate
FROM Client C
INNER JOIN REPLACE_ME_STAGING.dbo.Client DC ON DC.ClientID = C.LegacyID
WHERE LegacyID IS NOT NULL
	AND EntityID NOT IN (SELECT ClientID FROM ClientAlias)
	AND DC.Alias IS NOT NULL AND DC.Alias != ''

------------------ ClientRace -------------------------------------------------------
PRINT 'ClientRace'
INSERT ClientRace
(ClientID ,RaceID )
SELECT DISTINCT
EC.EntityID AS ClientID
,CR.Race
FROM REPLACE_ME_STAGING.DBO.ClientRace CR
INNER JOIN Client EC ON EC.LegacyID = CR.ClientID
WHERE EC.EntityID NOT IN (SELECT ClientID FROM ClientRace)
AND CR.Race IS NOT NULL

---in case they don't hit the clientRace table
---SELECT * FROM ListItem WHERE ListID = 6 --Baseline Race list
PRINT 'ClientRace'
INSERT INTO ClientRace (ClientID,RaceID	)
SELECT EntityID ,Race
FROM Client
WHERE LegacyID IS NOT NULL
	AND Race <> 0
	AND EntityID NOT IN (SELECT ClientID FROM ClientRace)
GO

------------------ ClientGender -------------------------------------------------------
PRINT 'ClientGender'
INSERT INTO ClientGender (ClientID,GenderID)
SELECT DISTINCT
	C.EntityID
	,StagingClient.Gender
FROM REPLACE_ME_STAGING.dbo.Client StagingClient
INNER JOIN Client C on C.LegacyID = StagingClient.ClientID
LEFT JOIN ClientGender CG ON CG.ClientID = C.EntityID
	AND CG.GenderID = StagingClient.Gender
WHERE StagingClient.Gender <> 0
	AND StagingClient.Gender IS NOT NULL
	AND CG.GenderID IS NULL --Prevent Dupes
GO


----------------------------------------- FAMILY -------------------------------------------
IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE COLUMN_NAME = 'LegacyID' AND TABLE_NAME = 'Family')
BEGIN
	ALTER TABLE dbo.Family ADD LegacyID VARCHAR(20) NULL
END
GO

/* Find families w/ more than 1 HoH */
IF EXISTS(
	Select * From (
	Select HohClientid,RelationToHoH,count(clientid) 'TotalFamilyMembersHoH'
	From REPLACE_ME_STAGING.dbo.client where RelationToHoH = 1
	Group by HohClientid,RelationToHoH
	) X
	WHERE TotalFamilyMembersHoH > 1
	)
BEGIN
	PRINT 'WARNING - Families w/ more than 1 HoH'
	Select * From (
	Select HohClientid,RelationToHoH,count(clientid) 'TotalFamilyMembersHoH'
	From REPLACE_ME_STAGING.dbo.client where RelationToHoH = 1
	Group by HohClientid,RelationToHoH
	) X
	WHERE TotalFamilyMembersHoH > 1
END


PRINT 'Family'
INSERT dbo.Family (
	FamilyName
	,CreatedDate
	,CreatedBy
	,FamilyPrimaryLang
	,LegacyID
	)
SELECT HoHClientID
	,XYZ.CreatedDate
	,XYZ.CreatedBy
	,XYZ.PrimaryLanguage
	,XYZ.LegacyID
FROM (
	SELECT DISTINCT HoHClientID
		,ISNULL(MAX(CreatedDate), GETUTCDATE()) AS CreatedDate
		,CreatedBy
		,PrimaryLanguage
		,LegacyID
		,ROW_NUMBER() OVER (PARTITION BY HoHClientID ORDER BY HoHClientID) AS RNUM
	FROM (
			SELECT DISTINCT HoHClientID
			,GETUTCDATE() AS CreatedDate
			,11 AS CreatedBy
			,PrimaryLanguage
			,HoHClientID AS LegacyID
			FROM REPLACE_ME_STAGING.dbo.Client
		) ABC
	GROUP BY HoHClientID
		,CreatedBy
		,PrimaryLanguage
		,LegacyID
	) XYZ
LEFT JOIN Family EF ON EF.LegacyID = XYZ.HoHClientID
INNER JOIN Client C2 on C2.LegacyID = XYZ.HoHClientID
WHERE XYZ.RNUM = 1
	AND EF.LegacyID IS NULL

------------------------ FamilyMember ---- INSERT HOH -----------------------------------------------------------
IF EXISTS (SELECT 1 FROM sys.triggers
		WHERE object_id = OBJECT_ID(N'[dbo].[tiu_FamilyMember_OneCurrent]')
		) DISABLE TRIGGER [tiu_FamilyMember_OneCurrent] ON FamilyMember

PRINT 'FamilyMember HoH'
INSERT dbo.FamilyMember (
	FamilyID
	,ClientID
	,RelationToHoH
	,DateAdded
	,DateRemoved
	)
SELECT DISTINCT
	F.FamilyID
	,C2.EntityID
	,C.RelationToHoH  --1 AS HoHClientID -- Self
	,CASE WHEN C2.BirthDate IS NOT NULL AND C2.BirthDate >= '1/1/1753' THEN C2.BirthDate
		ELSE '1/1/1753'
		END AS DateAdded
	,'12/31/9999' AS DateRemoved
FROM dbo.Family F
INNER JOIN REPLACE_ME_STAGING.dbo.Client C  ON F.FamilyName = C.HoHClientID
INNER JOIN dbo.Client C2  ON C2.LegacyID = C.HoHClientID
LEFT JOIN FamilyMember FM ON F.FamilyID = FM.FamilyID
	AND FM.ClientID = C2.EntityID
WHERE C.RelationToHoH = 1
	AND FM.FamilyMemberID IS NULL

------------------------------- INSERT OTHER FAMILY MEMBERS -------------------------------------------------
PRINT 'FamilyMember Non-HOH members'
INSERT dbo.FamilyMember (
	FamilyID
	,ClientID
	,RelationToHoH
	,DateAdded
	,DateRemoved
	)
SELECT DISTINCT
	F.FamilyID
	,C2.EntityID
	,C.RelationToHoH
	,ISNULL(C2.BirthDate, '01/01/1960') AS DateAdded --Needs to be before the lowest Enrollment.EndDate
	,'12/31/9999' AS DateRemoved
FROM REPLACE_ME_STAGING.dbo.Client C
--INNER JOIN Family F  ON F.FamilyName =CAST (C.HoHClientID  AS VARCHAR(50))
INNER JOIN Family F ON F.LegacyID = C.HoHClientID
INNER JOIN Client C2 ON C2.LegacyID = C.ClientID
LEFT JOIN FamilyMember FM ON F.FamilyID = FM.FamilyID
	AND FM.ClientID = C2.EntityID
WHERE C.RelationToHoH != 1
AND FM.FamilyMemberID IS NULL


----------- Update Family Name -----------------------
PRINT 'UPDATE FamilyName'
UPDATE F
SET F.FamilyName = CASE
		WHEN LEN(ISNULL(C2.LastName, 'LastName') + ',' + ISNULL(C2.FirstName, 'FirstName') + '-' + ISNULL(REPLACE(CONVERT(VARCHAR(20), C2.BirthDate, 102), '.', '-'), '')) > 50
			THEN SUBSTRING(ISNULL(C2.LastName, 'LastName') + ',' + ISNULL(C2.FirstName, 'FirstName') + '-' + ISNULL(REPLACE(CONVERT(VARCHAR(20), C2.BirthDate, 102), '.', '-'), ''), 1, 50)
		ELSE ISNULL(ISNULL(C2.LastName, 'LastName') + ',' + ISNULL(C2.FirstName, 'FirstName') + '-' + ISNULL(REPLACE(CONVERT(VARCHAR(20), C2.BirthDate, 102), '.', '-'), ''), 'FamilyName')
		END
FROM dbo.Family F
INNER JOIN REPLACE_ME_STAGING.dbo.Client C  ON F.FamilyName = C.ClientID
INNER JOIN Client C2 on C2.LegacyID = C.ClientID

GO

IF EXISTS (SELECT 1 FROM sys.triggers
		WHERE object_id = OBJECT_ID(N'[dbo].[tiu_FamilyMember_OneCurrent]')
		) ENABLE TRIGGER [tiu_FamilyMember_OneCurrent] ON FamilyMember

------------------------------------ ClientAddress -----------------------------------------------
/* Turn off this constraint. This will allow you to import whatever the customer uses.
ZipCode Data type = char(10) */
ALTER TABLE [dbo].[ClientAddress] NOCHECK CONSTRAINT [FK_ClientAddress_ZipCode]
GO

ALTER TABLE [ClientAddress] DISABLE TRIGGER ALL
GO

PRINT 'ClientAddress'
INSERT dbo.ClientAddress (
	ClientId
	,Address1
	,Address2
	,BuildingApartmentDesc
	,ZipCode
	,City
	,[STATE]
	,AddressType
	,BeginDate
	,EndDate
	,Restriction
	,FamilyID
	,CreatedBy
	,CreatedDate
	,County
	,OwnedByOrgID
	,LastModifiedDate
	,LastModifiedBy
	)
SELECT DISTINCT
	NC.EntityID
	,LEFT(ISNULL(C.[Address], ''), 100) AS [Address]
	,LEFT(ISNULL(C.[Address2], ''), 100) AS Address2
	,C.BuildingApartmentDesc
	,CASE
		WHEN C.Zip IS NULL OR C.Zip = '' THEN '00000'
		ELSE LEFT(C.Zip, 10)
		END AS Zip
	,LEFT(ISNULL(C.City, ''), 25) City
	,LEFT(C.StateCode, 2)
	,1 AS AddressType
	,GETUTCDATE() AS BeginDate
	,'9999-12-31' AS EndDate
	,1 AS Restriction
	,FM.FamilyID AS FamilyID
	,11 AS CreatedBy
	,GETUTCDATE() AS CreatedDate
	,LEFT(ISNULL(C.County, ''), 100)
	,NC.OwnedByOrgID
	,GETUTCDATE() AS LastModifiedDate
	,11 AS LastModifiedBy
FROM REPLACE_ME_STAGING.dbo.Client C
INNER JOIN Client NC  ON C.ClientID = NC.LegacyID
INNER JOIN FamilyMember FM ON FM.ClientID = NC.EntityID
LEFT JOIN ZipCode Z  ON ISNULL(C.Zip, '00000') = z.ZipCode
LEFT JOIN ClientAddress CA ON CA.ClientID = NC.EntityID
	AND CA.DeletedDate = '12/31/9999'
WHERE CA.AddressID IS NULL
GO

/* These next two are required to backfill the City and State based on the zip code. */
-- PRINT 'UPDATE Address - City'

-- UPDATE A
-- SET City = CityName
-- FROM ZipCode Z
-- INNER JOIN Address A ON A.ZipCode = Z.ZipCode
-- INNER JOIN EntityContact EC ON EC.EntityID = A.ContextID
-- WHERE EC.LegacyID IS NOT NULL

-- PRINT 'UPDATE Address - State'

-- UPDATE A
-- SET STATE = Z.STATE
-- FROM ZipCode Z
-- INNER JOIN Address A ON A.ZipCode = Z.ZipCode
-- INNER JOIN EntityContact EC ON EC.EntityID = A.ContextID
-- WHERE EC.LegacyID IS NOT NULL

ALTER TABLE [dbo].[ClientAddress] CHECK CONSTRAINT [FK_ClientAddress_ZipCode]
GO

ALTER TABLE [ClientAddress] ENABLE TRIGGER ALL
GO

------------------------- EntityVeteranInfo ---------------------
/* Check for Vet data */
IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE COLUMN_NAME = 'LegacyID'AND TABLE_NAME = 'EntityVeteranInfo')
BEGIN
	ALTER TABLE dbo.EntityVeteranInfo ADD LegacyID VARCHAR(20) NULL;
END
GO

PRINT 'EntityVeteranInfo'
INSERT INTO EntityVeteranInfo (
	EntityID
	,VetDuration
	,VetServedWarZone
	,VetWarZoneName
	,VetNumMonthsWarZone
	,VetReceivedFire
	,VetBranch
	,VetDischargeStatus
	,DateEnteredService
	,DateSeparatedFromService
	,ServiceConnectedDisability
	,DisabilityRewardLevel
	,CampaignBadgeVeteran
	,StandDownEvent
	,CreatedBy
	,CreatedDate
	,DeletedDate
	,DD214orderDate
	,DD214ReceiveDate
	,OwnedByOrgID
	,LegacyID
	)
SELECT DISTINCT C.EntityID
	,VetDuration
	,VetServedWarZone
	,VetWarZoneName
	,VetNumMonthsWarZone
	,VetReceivedFire
	,VetBranch
	,VetDischargeStatus
	,DateEnteredService
	,DateSeparatedFromService
	,ServiceConnectedDisability
	,DisabilityRewardLevel
	,CampaignBadgeVeteran
	,StandDownEvent
	,C.CreatedBy
	,C.CreatedDate AS CreatedDate
	,'9999-12-31' AS DeletedDate
	,DD214orderDate
	,DD214ReceiveDate
	,C.OwnedByOrgID
	,C.LegacyID
FROM REPLACE_ME_STAGING.dbo.EntityVeteranInfo CA
INNER JOIN Client C ON C.LegacyID = CA.ClientID
WHERE CA.ClientID NOT IN (
		SELECT LegacyID
		FROM EntityVeteranInfo
		WHERE LegacyID IS NOT NULL
		)

------------------------- EntityVeteranEra ---------------------------------
IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE COLUMN_NAME = 'LegacyID' AND TABLE_NAME = 'EntityVeteranEra')
BEGIN
	ALTER TABLE dbo.EntityVeteranEra ADD LegacyID VARCHAR(20) NULL
END
GO

PRINT 'EntityVeteranEra'
INSERT EntityVeteranEra (
	EntityID
	,Score
	,VeteranEraTypeID
	,CreatedBy
	,CreatedDate
	,DeletedDate
	,OwnedByOrgID
	,LegacyID
	)
SELECT C.EntityID
	,Score -- EntityVeteranEra.Score	list 37	default 2
	,VeteranEraTypeID -- VeteranEraType table
	,C.CreatedBy
	,C.CreatedDate
	,'9999-12-31' AS DeletedDate
	,C.OwnedByOrgID
	,CA.EntityVeteranEraID
FROM REPLACE_ME_STAGING.dbo.EntityVeteranEra CA
INNER JOIN Client C ON C.LegacyID = CA.ClientID
WHERE CA.ClientID NOT IN (
		SELECT LegacyID
		FROM dbo.EntityVeteranEra
		WHERE LegacyID IS NOT NULL
		)
