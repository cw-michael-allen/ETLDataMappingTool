/* ====================================================================================
   Master Data Validation Script
   Version: 3
   
   INSTRUCTIONS:
     1. Replace "REPLACEME_ETL"     with the name of the destination (CaseWorthy) database.
     2. Replace "REPLACEME_Staging" with the name of your staging database.
     3. Run the full script.
     4. Review the results at the bottom — any rows returned indicate data issues
        that should be corrected in your staging spreadsheet before import.

   IMPORTANT: This script is for use with a SQL Staging Database.
              Do NOT use this script if your data is still in the Excel staging file.

   HOW TO READ THE RESULTS:
     - "Error"   = This issue MUST be fixed before the data can be imported.
     - "Warning" = This may be an issue worth reviewing, but it will not block the import.
     The "SheetName" column shows which table the issue is in.
     The "ElementID" column shows the unique ID of the record that has the issue.
     The "ColumnName" column shows which field on that record has the issue.
====================================================================================*/

USE REPLACEME_Staging
GO

DROP TABLE IF EXISTS [dbo].[ErrorLog]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[ErrorLog] (
    [ErrorID]      INT IDENTITY(1,1) NOT NULL,
    [TableName]    VARCHAR(256)      NULL,
    [ElementID]    VARCHAR(256)      NULL,
    [ColumnName]   VARCHAR(256)      NULL,
    [ErrorMessage] VARCHAR(MAX)      NULL,
    [ErrorType]    VARCHAR(256)      NULL
) ON [PRIMARY]
GO

/* ====================================================================================
   ORGANIZATION
   ================================================================================== */
IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'Organization')
BEGIN
    IF EXISTS (SELECT 1 FROM Organization)
    BEGIN
        PRINT 'Starting Organization'

        -- Duplicate OrganizationID
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Organization', OrganizationID, 'OrganizationID',
            CONCAT('"', OrganizationID, '" appears more than once. Each OrganizationID must be unique.')
        FROM Organization
        WHERE OrganizationID IN (
            SELECT OrganizationID FROM Organization GROUP BY OrganizationID HAVING COUNT(*) > 1
        )

        -- OrganizationID is blank
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Organization', OrganizationID, 'OrganizationID',
            'OrganizationID is blank. OrganizationID is required.'
        FROM Organization
        WHERE OrganizationID IS NULL OR OrganizationID = ''

        -- OrgName is blank (Required)
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Organization', OrganizationID, 'OrgName',
            'OrgName is blank. OrgName is required.'
        FROM Organization
        WHERE OrgName IS NULL OR OrgName = ''

        -- OrgName too long
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Organization', OrganizationID, 'OrgName',
            CONCAT('"', OrgName, '" is too long. OrgName cannot exceed 100 characters.')
        FROM Organization WHERE LEN(OrgName) > 100

        -- DefaultProviderID must be a valid numeric ID
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Organization', OrganizationID, 'DefaultProviderID',
            CONCAT('"', DefaultProviderID, '" is not a valid number. DefaultProviderID must be a numeric ID.')
        FROM Organization
        WHERE DefaultProviderID IS NOT NULL AND DefaultProviderID != ''
          AND TRY_CONVERT(FLOAT, DefaultProviderID) IS NULL

        -- PWChangeDays must be integer
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Organization', OrganizationID, 'PWChangeDays',
            CONCAT('"', PWChangeDays, '" is invalid. PWChangeDays must be a whole number (e.g., 45).')
        FROM Organization
        WHERE PWChangeDays IS NOT NULL AND PWChangeDays != ''
          AND TRY_CONVERT(INT, PWChangeDays) IS NULL

        -- AutoLogoutMinutes must be integer
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Organization', OrganizationID, 'AutoLogoutMinutes',
            CONCAT('"', AutoLogoutMinutes, '" is invalid. AutoLogoutMinutes must be a whole number (e.g., 30).')
        FROM Organization
        WHERE AutoLogoutMinutes IS NOT NULL AND AutoLogoutMinutes != ''
          AND TRY_CONVERT(INT, AutoLogoutMinutes) IS NULL

        -- AllowPrint must be 0 or 1
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Organization', OrganizationID, 'AllowPrint',
            CONCAT('"', AllowPrint, '" is invalid. AllowPrint must be 1 (Yes) or 0 (No).')
        FROM Organization
        WHERE AllowPrint IS NOT NULL AND AllowPrint != ''
          AND (TRY_CONVERT(FLOAT, AllowPrint) IS NULL OR AllowPrint NOT IN ('0','1'))

        -- AllowExcel must be 0 or 1
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Organization', OrganizationID, 'AllowExcel',
            CONCAT('"', AllowExcel, '" is invalid. AllowExcel must be 1 (Yes) or 0 (No).')
        FROM Organization
        WHERE AllowExcel IS NOT NULL AND AllowExcel != ''
          AND (TRY_CONVERT(FLOAT, AllowExcel) IS NULL OR AllowExcel NOT IN ('0','1'))

        -- EnableTimeLogging must be 0 or 1
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Organization', OrganizationID, 'EnableTimeLogging',
            CONCAT('"', EnableTimeLogging, '" is invalid. EnableTimeLogging must be 1 (Yes) or 0 (No).')
        FROM Organization
        WHERE EnableTimeLogging IS NOT NULL AND EnableTimeLogging != ''
          AND (TRY_CONVERT(FLOAT, EnableTimeLogging) IS NULL OR EnableTimeLogging NOT IN ('0','1'))

        -- LockoutAfterAttempts must be integer
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Organization', OrganizationID, 'LockoutAfterAttempts',
            CONCAT('"', LockoutAfterAttempts, '" is invalid. LockoutAfterAttempts must be a whole number (e.g., 3).')
        FROM Organization
        WHERE LockoutAfterAttempts IS NOT NULL AND LockoutAfterAttempts != ''
          AND TRY_CONVERT(INT, LockoutAfterAttempts) IS NULL

        -- CreatedDate must be a valid date
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Organization', OrganizationID, 'CreatedDate',
            CONCAT('"', CreatedDate, '" is not a valid date. CreatedDate is optional but must be a valid date if provided.')
        FROM Organization
        WHERE CreatedDate IS NOT NULL AND CreatedDate != ''
          AND TRY_CONVERT(DATE, CreatedDate) IS NULL

    END
END
GO

/* ====================================================================================
   PROVIDER
   ================================================================================== */
IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'Provider')
BEGIN
    IF EXISTS (SELECT 1 FROM [Provider])
    BEGIN
        PRINT 'Starting Provider'

        -- Duplicate ProviderID
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Provider', ProviderID, 'ProviderID',
            CONCAT('"', ProviderID, '" appears more than once. Each ProviderID must be unique.')
        FROM [Provider]
        WHERE ProviderID IN (
            SELECT ProviderID FROM [Provider] GROUP BY ProviderID HAVING COUNT(*) > 1
        )

        -- ProviderID is blank
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Provider', ProviderID, 'ProviderID',
            'ProviderID is blank. ProviderID is required.'
        FROM [Provider] WHERE ProviderID IS NULL OR ProviderID = ''

        -- ProviderName is blank (Required)
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Provider', ProviderID, 'ProviderName',
            'ProviderName is blank. ProviderName is required.'
        FROM [Provider] WHERE ProviderName IS NULL OR ProviderName = ''

        -- OrganizationID must be valid
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Provider', ProviderID, 'OrganizationID',
            CONCAT('"', OrganizationID, '" is invalid. OrganizationID is required and must match a value in the Organization sheet or an existing Organization in the destination database.')
        FROM [Provider]
        WHERE TRY_CONVERT(FLOAT, OrganizationID) IS NULL
           OR OrganizationID IS NULL
           OR (TRY_CONVERT(FLOAT, OrganizationID) IS NOT NULL
               AND OrganizationID NOT IN (SELECT OrganizationID FROM Organization WHERE OrganizationID IS NOT NULL)
               AND CONVERT(INT, OrganizationID) NOT IN (SELECT EntityID FROM REPLACEME_ETL.dbo.Organization))

        -- ProviderTypeCategoryTypeID from List 313
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Provider', ProviderID, 'ProviderTypeCategoryTypeID',
            CONCAT('"', ProviderTypeCategoryTypeID, '" is invalid. ProviderTypeCategoryTypeID must be a value from ListID 313.')
        FROM [Provider]
        WHERE ProviderTypeCategoryTypeID IS NOT NULL AND ProviderTypeCategoryTypeID != ''
          AND (TRY_CONVERT(FLOAT, ProviderTypeCategoryTypeID) IS NULL
               OR TRY_CONVERT(FLOAT, ProviderTypeCategoryTypeID) NOT IN (SELECT ProviderTypeCategoryTypeID FROM Goodwill_Ontario_GL_ETL.dbo.ProviderTypeCategoryType WHERE DeletedDate = '12/31/9999'))

        -- Address length check
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Provider', ProviderID, 'Address',
            CONCAT('"', Address, '" is too long. Address cannot exceed 100 characters.')
        FROM [Provider] WHERE LEN(Address) > 100

        -- Address2 length check
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Provider', ProviderID, 'Address2',
            CONCAT('"', Address2, '" is too long. Address2 cannot exceed 100 characters.')
        FROM [Provider] WHERE LEN(Address2) > 100

        -- City length check
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Provider', ProviderID, 'City',
            CONCAT('"', City, '" is too long. City cannot exceed 50 characters.')
        FROM [Provider] WHERE LEN(City) > 50

        -- State must be 2 characters, no digits
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Provider', ProviderID, 'State',
            CONCAT('"', [State], '" is invalid. State must be a valid 2-letter state code (e.g., CA, TX).')
        FROM [Provider]
        WHERE [State] IS NOT NULL AND [State] != ''
          AND ([State] LIKE '%[0-9]%' OR LEN([State]) > 2)

        -- ZipCode must be 5 digits
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Provider', ProviderID, 'ZipCode',
            CONCAT('"', ZipCode, '" is invalid. ZipCode must be exactly 5 numeric digits.')
        FROM [Provider]
        WHERE ZipCode IS NOT NULL AND ZipCode != ''
          AND (TRY_CONVERT(INT, ZipCode) IS NULL OR LEN(TRIM(ZipCode)) != 5)

        -- Phone must be 10 digits
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Provider', ProviderID, 'Phone',
            CONCAT('"', Phone, '" is invalid. Phone must be exactly 10 numeric digits.')
        FROM [Provider]
        WHERE Phone IS NOT NULL AND Phone != ''
          AND (LEN(TRIM(REPLACE(Phone, '-', ''))) NOT IN (10))

        -- Fax must be 10 digits
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Provider', ProviderID, 'Fax',
            CONCAT('"', Fax, '" is invalid. Fax must be exactly 10 numeric digits.')
        FROM [Provider]
        WHERE Fax IS NOT NULL AND Fax != ''
          AND (LEN(TRIM(REPLACE(Fax, '-', ''))) NOT IN (10))

        -- Email length check
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Provider', ProviderID, 'Email',
            CONCAT('"', Email, '" is too long. Email cannot exceed 100 characters.')
        FROM [Provider] WHERE LEN(Email) > 100

        -- Website length check
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Provider', ProviderID, 'Website',
            CONCAT('"', Website, '" is too long. Website cannot exceed 100 characters.')
        FROM [Provider] WHERE LEN(Website) > 100

        -- TaxType from List 343
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Provider', ProviderID, 'TaxType',
            CONCAT('"', TaxType, '" is invalid. TaxType must be a value from ListID 343 (1=Corporation, 5=Partnership, 10=Individual).')
        FROM [Provider]
        WHERE TaxType IS NOT NULL AND TaxType != ''
          AND (TRY_CONVERT(FLOAT, TaxType) IS NULL
               OR TRY_CONVERT(FLOAT, TaxType) NOT IN (SELECT ListValue FROM REPLACEME_ETL.dbo.ListItem WHERE ListID = 343))

        -- SiteConfigurationType from List 40
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Provider', ProviderID, 'SiteConfigurationType',
            CONCAT('"', SiteConfigurationType, '" is invalid. SiteConfigurationType must be a value from ListID 40.')
        FROM [Provider]
        WHERE SiteConfigurationType IS NOT NULL AND SiteConfigurationType != ''
          AND (TRY_CONVERT(FLOAT, SiteConfigurationType) IS NULL
               OR TRY_CONVERT(FLOAT, SiteConfigurationType) NOT IN (SELECT ListValue FROM REPLACEME_ETL.dbo.ListItem WHERE ListID = 40))

        -- PrincipleSite from List 194
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Provider', ProviderID, 'PrincipleSite',
            CONCAT('"', PrincipleSite, '" is invalid. PrincipleSite must be a value from ListID 194 (0=No, 1=Yes).')
        FROM [Provider]
        WHERE PrincipleSite IS NOT NULL AND PrincipleSite != ''
          AND (TRY_CONVERT(FLOAT, PrincipleSite) IS NULL
               OR TRY_CONVERT(FLOAT, PrincipleSite) NOT IN (SELECT ListValue FROM REPLACEME_ETL.dbo.ListItem WHERE ListID = 194))

        -- GeographyType from List 6845
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Provider', ProviderID, 'GeographyType',
            CONCAT('"', GeographyType, '" is invalid. GeographyType must be a value from ListID 6845 (1=Urban, 2=Suburban, 3=Rural).')
        FROM [Provider]
        WHERE GeographyType IS NOT NULL AND GeographyType != ''
          AND (TRY_CONVERT(FLOAT, GeographyType) IS NULL
               OR TRY_CONVERT(FLOAT, GeographyType) NOT IN (SELECT ListValue FROM REPLACEME_ETL.dbo.ListItem WHERE ListID = 6845))

        -- CreatedDate must be a valid date
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Provider', ProviderID, 'CreatedDate',
            CONCAT('"', CreatedDate, '" is not a valid date. CreatedDate is optional but must be a valid date if provided.')
        FROM [Provider]
        WHERE CreatedDate IS NOT NULL AND CreatedDate != ''
          AND TRY_CONVERT(DATE, CreatedDate) IS NULL

    END
END
GO

/* ====================================================================================
   USERS
   ================================================================================== */
IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'Users')
BEGIN
    IF EXISTS (SELECT 1 FROM Users)
    BEGIN
        PRINT 'Starting Users'

        -- Duplicate UserID
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Users', UserID, 'UserID',
            CONCAT('"', UserID, '" appears more than once. Each UserID must be unique.')
        FROM Users WHERE UserID IN (SELECT UserID FROM Users GROUP BY UserID HAVING COUNT(*) > 1)

        -- Duplicate UserName
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Users', UserID, 'UserName',
            CONCAT('"', UserName, '" appears more than once. Each UserName must be unique.')
        FROM Users WHERE UserName IN (SELECT UserName FROM Users GROUP BY UserName HAVING COUNT(*) > 1)

        -- Duplicate EmailAddress (warning)
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorType, ErrorMessage)
        SELECT DISTINCT 'Users', UserID, 'EmailAddress', 'Warning',
            CONCAT('"', EmailAddress, '" is used more than once. Multiple user accounts share this email address.')
        FROM Users WHERE EmailAddress IN (SELECT EmailAddress FROM Users GROUP BY EmailAddress HAVING COUNT(*) > 1)

        -- UserID blank
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Users', UserID, 'UserID',
            'UserID is blank. UserID is required.'
        FROM Users WHERE UserID IS NULL OR UserID = ''

        -- UserName required and max 50 chars
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Users', UserID, 'UserName',
            'UserName is blank. UserName is required.'
        FROM Users WHERE UserName IS NULL OR UserName = ''

        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Users', UserID, 'UserName',
            CONCAT('"', UserName, '" is too long. UserName cannot exceed 50 characters.')
        FROM Users WHERE LEN(UserName) > 50

        -- UserName already exists in destination database (warning)
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorType, ErrorMessage)
        SELECT DISTINCT 'Users', UserID, 'UserName', 'Warning',
            CONCAT('"', UserName, '" already exists in the destination database. This user will not be imported — the existing account will be used instead.')
        FROM Users WHERE UserName IN (SELECT UserName FROM REPLACEME_ETL.dbo.Users)

        -- FirstName required and max 50 chars
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Users', UserID, 'FirstName',
            'FirstName is blank. FirstName is required.'
        FROM Users WHERE FirstName IS NULL OR FirstName = ''

        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Users', UserID, 'FirstName',
            CONCAT('"', FirstName, '" is too long. FirstName cannot exceed 50 characters.')
        FROM Users WHERE LEN(FirstName) > 50

        -- LastName required and max 50 chars
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Users', UserID, 'LastName',
            'LastName is blank. LastName is required.'
        FROM Users WHERE LastName IS NULL OR LastName = ''

        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Users', UserID, 'LastName',
            CONCAT('"', LastName, '" is too long. LastName cannot exceed 50 characters.')
        FROM Users WHERE LEN(LastName) > 50

        -- EmailAddress required
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Users', UserID, 'EmailAddress',
            'EmailAddress is blank. EmailAddress is required.'
        FROM Users WHERE EmailAddress IS NULL OR EmailAddress = ''

        -- OrganizationID must be valid
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Users', UserID, 'OrganizationID',
            CONCAT('"', OrganizationID, '" is invalid. OrganizationID is required and must match a value in the Organization sheet or an existing Organization in the destination database.')
        FROM Users
        WHERE TRY_CONVERT(FLOAT, OrganizationID) IS NULL
           OR OrganizationID IS NULL
           OR (TRY_CONVERT(FLOAT, OrganizationID) IS NOT NULL
               AND OrganizationID NOT IN (SELECT OrganizationID FROM Organization WHERE OrganizationID IS NOT NULL)
               AND CONVERT(INT, OrganizationID) NOT IN (SELECT EntityID FROM REPLACEME_ETL.dbo.Organization))

        -- ProviderID must be valid
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Users', UserID, 'ProviderID',
            CONCAT('"', ProviderID, '" is invalid. ProviderID is required and must match a value in the Provider sheet or an existing Provider in the destination database.')
        FROM Users
        WHERE TRY_CONVERT(FLOAT, ProviderID) IS NULL
           OR ProviderID IS NULL
           OR (TRY_CONVERT(FLOAT, ProviderID) IS NOT NULL
               AND ProviderID NOT IN (SELECT ProviderID FROM [Provider])
               AND ProviderID NOT IN (SELECT CONVERT(VARCHAR, EntityID) FROM REPLACEME_ETL.dbo.[Provider]))

        -- DefaultRoleID must be valid (optional)
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Users', UserID, 'DefaultRoleID',
            CONCAT('"', DefaultRoleID, '" is invalid. DefaultRoleID must be a valid Role ID from the destination database.')
        FROM Users
        WHERE DefaultRoleID IS NOT NULL AND DefaultRoleID != ''
          AND DefaultRoleID NOT IN (SELECT CONVERT(VARCHAR(50), RoleID) FROM REPLACEME_ETL.dbo.RoleDefinition)

        -- UserTypeID from List 8
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Users', UserID, 'UserTypeID',
            CONCAT('"', UserTypeID, '" is invalid. UserTypeID must be a value from ListID 8 (2=Authenticated Users, 3=Alter Own Role, 4=Alter Any Role).')
        FROM Users
        WHERE UserTypeID IS NOT NULL AND UserTypeID != ''
          AND (TRY_CONVERT(FLOAT, UserTypeID) IS NULL
               OR TRY_CONVERT(FLOAT, UserTypeID) NOT IN (SELECT ListValue FROM REPLACEME_ETL.dbo.ListItem WHERE ListID = 8))

        -- isSupervisor must be 0 or 1
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Users', UserID, 'isSupervisor',
            CONCAT('"', isSupervisor, '" is invalid. isSupervisor must be 1 (Yes) or 0 (No).')
        FROM Users
        WHERE isSupervisor IS NOT NULL AND isSupervisor != ''
          AND (TRY_CONVERT(bit, isSupervisor) IS NULL OR isSupervisor NOT IN ('0','1','True','False'))

        -- isActive must be 0 or 1
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Users', UserID, 'isActive',
            CONCAT('"', isActive, '" is invalid. isActive must be 1 (Yes) or 0 (No).')
        FROM Users
        WHERE isActive IS NOT NULL AND isActive != ''
          AND (TRY_CONVERT(bit, isActive) IS NULL OR isActive NOT IN ('0','1','True','False'))

        -- PhoneExt max 4 digits
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Users', UserID, 'PhoneExt',
            CONCAT('"', PhoneExt, '" is invalid. PhoneExt must be numeric and no more than 4 digits.')
        FROM Users
        WHERE PhoneExt IS NOT NULL AND PhoneExt != ''
          AND (PhoneExt NOT LIKE '%[0-9]%' OR LEN(PhoneExt) > 4)

        -- EnableTimeLogging must be 0 or 1
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Users', UserID, 'EnableTimeLogging',
            CONCAT('"', EnableTimeLogging, '" is invalid. EnableTimeLogging must be 1 (Yes) or 0 (No).')
        FROM Users
        WHERE EnableTimeLogging IS NOT NULL AND EnableTimeLogging != ''
          AND (TRY_CONVERT(bit, EnableTimeLogging) IS NULL OR EnableTimeLogging NOT IN ('0','1','True','False'))

        -- AllowPrint must be 0 or 1
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Users', UserID, 'AllowPrint',
            CONCAT('"', AllowPrint, '" is invalid. AllowPrint must be 1 (Yes) or 0 (No).')
        FROM Users
        WHERE AllowPrint IS NOT NULL AND AllowPrint != ''
          AND (TRY_CONVERT(bit, AllowPrint) IS NULL OR AllowPrint NOT IN ('0','1','True','False'))

        -- AllowExcel must be 0 or 1
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Users', UserID, 'AllowExcel',
            CONCAT('"', AllowExcel, '" is invalid. AllowExcel must be 1 (Yes) or 0 (No).')
        FROM Users
        WHERE AllowExcel IS NOT NULL AND AllowExcel != ''
          AND (TRY_CONVERT(bit, AllowExcel) IS NULL OR AllowExcel NOT IN ('0','1','True','False'))

    END
END
GO

/* ====================================================================================
   PROGRAM
   ================================================================================== */
IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'Program')
BEGIN
    IF EXISTS (SELECT 1 FROM [Program])
    BEGIN
        PRINT 'Starting Program'

        -- Duplicate ProgramID
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Program', ProgramID, 'ProgramID',
            CONCAT('"', ProgramID, '" appears more than once. Each ProgramID must be unique.')
        FROM [Program] WHERE ProgramID IN (SELECT ProgramID FROM [Program] GROUP BY ProgramID HAVING COUNT(*) > 1)

        -- ProgramID blank
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Program', ProgramID, 'ProgramID',
            'ProgramID is blank. ProgramID is required.'
        FROM [Program] WHERE ProgramID IS NULL OR ProgramID = ''

        -- ProgramName required, max 50 chars
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Program', ProgramID, 'ProgramName',
            'ProgramName is blank. ProgramName is required.'
        FROM [Program] WHERE ProgramName IS NULL OR ProgramName = ''

        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Program', ProgramID, 'ProgramName',
            CONCAT('"', ProgramName, '" is too long. ProgramName cannot exceed 50 characters.')
        FROM [Program] WHERE LEN(ProgramName) > 50

        -- BeginDate must be valid date
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Program', ProgramID, 'BeginDate',
            CONCAT('"', BeginDate, '" is not a valid date. BeginDate is optional but must be a valid date if provided.')
        FROM [Program] WHERE BeginDate IS NOT NULL AND BeginDate != '' AND TRY_CONVERT(DATE, BeginDate) IS NULL

        -- EndDate must be valid date
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Program', ProgramID, 'EndDate',
            CONCAT('"', EndDate, '" is not a valid date. EndDate is optional but must be a valid date if provided.')
        FROM [Program] WHERE EndDate IS NOT NULL AND EndDate != '' AND TRY_CONVERT(DATE, EndDate) IS NULL

        -- EnrollmentsEnabled must be 0 or 1
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Program', ProgramID, 'EnrollmentsEnabled',
            CONCAT('"', EnrollmentsEnabled, '" is invalid. EnrollmentsEnabled must be 1 (Yes) or 0 (No).')
        FROM [Program]
        WHERE EnrollmentsEnabled IS NOT NULL AND EnrollmentsEnabled != ''
          AND (TRY_CONVERT(FLOAT, EnrollmentsEnabled) IS NULL OR EnrollmentsEnabled NOT IN ('0','1'))

        -- NotifyOnAutoExit from List 2893
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Program', ProgramID, 'NotifyOnAutoExit',
            CONCAT('"', NotifyOnAutoExit, '" is invalid. NotifyOnAutoExit must be a value from ListID 2893.')
        FROM [Program]
        WHERE NotifyOnAutoExit IS NOT NULL AND NotifyOnAutoExit != ''
          AND (TRY_CONVERT(FLOAT, NotifyOnAutoExit) IS NULL
               OR TRY_CONVERT(FLOAT, NotifyOnAutoExit) NOT IN (SELECT ListValue FROM REPLACEME_ETL.dbo.ListItem WHERE ListID = 2893))

    END
END
GO

/* ====================================================================================
   CLIENT
   ================================================================================== */
IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'Client')
BEGIN
    IF EXISTS (SELECT 1 FROM Client)
    BEGIN
        PRINT 'Starting Client'

        -- Duplicate ClientID
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Client', ClientID, 'ClientID',
            CONCAT('"', ClientID, '" appears more than once. Each ClientID must be unique.')
        FROM Client WHERE ClientID IN (SELECT ClientID FROM Client WHERE ClientID IS NOT NULL GROUP BY ClientID HAVING COUNT(*) > 1)

        -- ClientID blank
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Client', ClientID, 'ClientID',
            'ClientID is blank. ClientID is required.'
        FROM Client WHERE ClientID IS NULL OR ClientID = ''

        -- FirstName required, max 50 chars
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Client', ClientID, 'FirstName',
            'FirstName is blank. FirstName is required.'
        FROM Client WHERE FirstName IS NULL OR FirstName = ''

        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Client', ClientID, 'FirstName',
            CONCAT('"', FirstName, '" is too long. FirstName cannot exceed 50 characters.')
        FROM Client WHERE LEN(FirstName) > 50

        -- LastName required, max 50 chars
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Client', ClientID, 'LastName',
            'LastName is blank. LastName is required.'
        FROM Client WHERE LastName IS NULL OR LastName = ''

        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Client', ClientID, 'LastName',
            CONCAT('"', LastName, '" is too long. LastName cannot exceed 50 characters.')
        FROM Client WHERE LEN(LastName) > 50

        -- MiddleName max 50 chars
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Client', ClientID, 'MiddleName',
            CONCAT('"', MiddleName, '" is too long. MiddleName cannot exceed 50 characters.')
        FROM Client WHERE LEN(MiddleName) > 50

        -- HoHClientID required and must reference a valid ClientID
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Client', ClientID, 'HoHClientID',
            'HoHClientID is blank. HoHClientID is required. For clients without a family, set this equal to their own ClientID.'
        FROM Client WHERE HoHClientID IS NULL OR HoHClientID = ''

        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Client', ClientID, 'HoHClientID',
            CONCAT('"', HoHClientID, '" is invalid. HoHClientID must match a ClientID from the Client sheet.')
        FROM Client WHERE (HoHClientID IS NOT NULL AND HoHClientID != '')
          AND HoHClientID NOT IN (SELECT ClientID FROM Client WHERE ClientID IS NOT NULL)

        -- RelationToHoH required, from List 4
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Client', ClientID, 'RelationToHoH',
            CONCAT('"', ISNULL(RelationToHoH,'(blank)'), '" is invalid. RelationToHoH is required and must be a value from ListID 4 (e.g., 1=Self, 2=Spouse, 3=Child).')
        FROM Client
        WHERE TRY_CONVERT(FLOAT, RelationToHoH) IS NULL
           OR RelationToHoH IS NULL
           OR (TRY_CONVERT(FLOAT, RelationToHoH) IS NOT NULL
               AND RelationToHoH NOT IN (SELECT ListValue FROM REPLACEME_ETL.dbo.ListItem WHERE ListID = 4))

        -- RelationToHoH must = 1 where client is their own HoH
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Client', ClientID, 'RelationToHoH',
            CONCAT('"', RelationToHoH, '" is invalid. When a client is their own Head of Household (ClientID = HoHClientID), RelationToHoH must be 1 (Self).')
        FROM Client
        WHERE ClientID = HoHClientID AND TRY_CONVERT(FLOAT, RelationToHoH) != 1

        -- Only one HoH per household
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Client', HoHClientID, 'RelationToHoH',
            CONCAT('Multiple clients are marked as Head of Household for HoHClientID = ', HoHClientID, '. There can only be one Head of Household per family.')
        FROM Client
        WHERE HoHClientID IN (
            SELECT HoHClientID FROM Client
            WHERE CONVERT(NVARCHAR, RelationToHoH) = '1'
            GROUP BY HoHClientID HAVING COUNT(*) > 1
        )

        -- OrganizationID required and valid
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Client', ClientID, 'OrganizationID',
            CONCAT('"', ISNULL(OrganizationID,'(blank)'), '" is invalid. OrganizationID is required and must match a value in the Organization sheet or the destination database.')
        FROM Client
        WHERE TRY_CONVERT(FLOAT, OrganizationID) IS NULL
           OR OrganizationID IS NULL
           OR (TRY_CONVERT(FLOAT, OrganizationID) IS NOT NULL
               AND OrganizationID NOT IN (SELECT OrganizationID FROM Organization WHERE OrganizationID IS NOT NULL)
               AND CONVERT(INT, OrganizationID) NOT IN (SELECT EntityID FROM REPLACEME_ETL.dbo.Organization))

        -- BirthDate must be a valid date
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Client', ClientID, 'BirthDate',
            CONCAT('"', BirthDate, '" is not a valid date. BirthDate is optional but must be a valid date if provided.')
        FROM Client WHERE BirthDate IS NOT NULL AND TRY_CONVERT(DATE, BirthDate) IS NULL

        -- DOBDataQuality from List 620
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Client', ClientID, 'DOBDataQuality',
            CONCAT('"', DOBDataQuality, '" is invalid. DOBDataQuality must be a value from ListID 620.')
        FROM Client
        WHERE DOBDataQuality IS NOT NULL AND DOBDataQuality != ''
          AND (TRY_CONVERT(FLOAT, DOBDataQuality) IS NULL
               OR TRY_CONVERT(FLOAT, DOBDataQuality) NOT IN (SELECT ListValue FROM REPLACEME_ETL.dbo.ListItem WHERE ListID = 620))

        -- Suffix from List 714
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Client', ClientID, 'Suffix',
            CONCAT('"', Suffix, '" is invalid. Suffix must be a value from ListID 714 (1=Jr, 2=Sr, 3=II, 4=III, 5=IV).')
        FROM Client
        WHERE Suffix IS NOT NULL AND Suffix != ''
          AND (TRY_CONVERT(FLOAT, Suffix) IS NULL
               OR TRY_CONVERT(FLOAT, Suffix) NOT IN (SELECT ListValue FROM REPLACEME_ETL.dbo.ListItem WHERE ListID = 714))

        -- Gender from List 1
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Client', ClientID, 'Gender',
            CONCAT('"', Gender, '" is invalid. Gender must be a value from ListID 1.')
        FROM Client
        WHERE Gender IS NOT NULL AND Gender != ''
          AND (TRY_CONVERT(FLOAT, Gender) IS NULL
               OR CONVERT(FLOAT, Gender) NOT IN (SELECT ListValue FROM REPLACEME_ETL.dbo.ListItem WHERE ListID = 1))

        -- SexualOrientation from List 2910
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Client', ClientID, 'SexualOrientation',
            CONCAT('"', SexualOrientation, '" is invalid. SexualOrientation must be a value from ListID 2910.')
        FROM Client
        WHERE SexualOrientation IS NOT NULL AND SexualOrientation != ''
          AND (TRY_CONVERT(FLOAT, SexualOrientation) IS NULL
               OR CONVERT(FLOAT, SexualOrientation) NOT IN (SELECT ListValue FROM REPLACEME_ETL.dbo.ListItem WHERE ListID = 2910))

        -- PrimaryLanguage from List 133
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Client', ClientID, 'PrimaryLanguage',
            CONCAT('"', PrimaryLanguage, '" is invalid. PrimaryLanguage must be a value from ListID 133.')
        FROM Client
        WHERE PrimaryLanguage IS NOT NULL AND PrimaryLanguage != ''
          AND (TRY_CONVERT(FLOAT, PrimaryLanguage) IS NULL
               OR CONVERT(FLOAT, PrimaryLanguage) NOT IN (SELECT ListValue FROM REPLACEME_ETL.dbo.ListItem WHERE ListID = 133))

        -- EnglishProficiency from List 627
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Client', ClientID, 'EnglishProficiency',
            CONCAT('"', EnglishProficiency, '" is invalid. EnglishProficiency must be a value from ListID 627.')
        FROM Client
        WHERE EnglishProficiency IS NOT NULL AND EnglishProficiency != ''
          AND (TRY_CONVERT(FLOAT, EnglishProficiency) IS NULL
               OR CONVERT(FLOAT, EnglishProficiency) NOT IN (SELECT ListValue FROM REPLACEME_ETL.dbo.ListItem WHERE ListID = 627))

        -- Race from List 6
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Client', ClientID, 'Race',
            CONCAT('"', Race, '" is invalid. Race must be a value from ListID 6.')
        FROM Client
        WHERE Race IS NOT NULL AND Race != ''
          AND (TRY_CONVERT(FLOAT, Race) IS NULL
               OR CONVERT(FLOAT, Race) NOT IN (SELECT ListValue FROM REPLACEME_ETL.dbo.ListItem WHERE ListID = 6))

        -- Ethnicity from List 7
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Client', ClientID, 'Ethnicity',
            CONCAT('"', Ethnicity, '" is invalid. Ethnicity must be a value from ListID 7.')
        FROM Client
        WHERE Ethnicity IS NOT NULL AND Ethnicity != ''
          AND (TRY_CONVERT(FLOAT, Ethnicity) IS NULL
               OR CONVERT(FLOAT, Ethnicity) NOT IN (SELECT ListValue FROM REPLACEME_ETL.dbo.ListItem WHERE ListID = 7))

        -- SSN: valid length
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorType, ErrorMessage)
        SELECT 'Client', ClientID, 'SSN', 'Warning',
            'SSN has an unusual length. A valid SSN should be 4 digits (last 4), 9 digits (full), or 11 characters (with dashes, e.g. XXX-XX-1234).'
        FROM Client
        WHERE SSN IS NOT NULL AND TRIM(SSN) != ''
          AND LEN(TRIM(SSN)) NOT IN (4, 9, 11)

        -- SSN: valid characters (digits or X, with optional dashes)
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Client', ClientID, 'SSN',
            CONCAT('"', SSN, '" contains invalid characters. SSN may only contain digits (0-9), the letter X, and dashes.')
        FROM Client
        WHERE SSN IS NOT NULL AND SSN != ''
          AND (SSN LIKE '%[a-wA-Wy-zY-Z]%')

        -- Duplicate SSN (warning)
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorType, ErrorMessage)
        SELECT 'Client', ClientID, 'SSN', 'Warning',
            CONCAT('Duplicate SSN found: "', ISNULL(SSN,''), '". Multiple clients share this SSN.')
        FROM (
            SELECT SSN, ClientID,
                   ROW_NUMBER() OVER (PARTITION BY SSN ORDER BY SSN) AS RowNum
            FROM Client WHERE SSN IS NOT NULL AND SSN != ''
        ) X WHERE RowNum > 1

        -- SSNDataQuality from List 587
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Client', ClientID, 'SSNDataQuality',
            CONCAT('"', SSNDataQuality, '" is invalid. SSNDataQuality must be a value from ListID 587.')
        FROM Client
        WHERE SSNDataQuality IS NOT NULL AND SSNDataQuality != ''
          AND (TRY_CONVERT(FLOAT, SSNDataQuality) IS NULL
               OR SSNDataQuality NOT IN (SELECT ListValue FROM REPLACEME_ETL.dbo.ListItem WHERE ListID = 587))

        -- Potential duplicate client (warning)
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorType, ErrorMessage)
        SELECT 'Client', ClientID, 'ClientID', 'Warning',
            'Possible duplicate client: another record has the same First Name, Last Name, and Date of Birth.'
        FROM (
            SELECT BirthDate, FirstName, LastName, ClientID,
                   ROW_NUMBER() OVER (PARTITION BY BirthDate, FirstName, LastName ORDER BY BirthDate) AS RowNum
            FROM Client
        ) X WHERE RowNum > 1

        -- HomePhoneType from List 4073
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Client', ClientID, 'HomePhoneType',
            CONCAT('"', HomePhoneType, '" is invalid. HomePhoneType must be a value from ListID 4073 (1=Primary, 2=Secondary, 3=Tertiary).')
        FROM Client
        WHERE HomePhoneType IS NOT NULL AND HomePhoneType != ''
          AND (TRY_CONVERT(FLOAT, HomePhoneType) IS NULL
               OR CONVERT(FLOAT, HomePhoneType) NOT IN (SELECT ListValue FROM REPLACEME_ETL.dbo.ListItem WHERE ListID = 4073))

        -- WorkPhoneType from List 4073
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Client', ClientID, 'WorkPhoneType',
            CONCAT('"', WorkPhoneType, '" is invalid. WorkPhoneType must be a value from ListID 4073 (1=Primary, 2=Secondary, 3=Tertiary).')
        FROM Client
        WHERE WorkPhoneType IS NOT NULL AND WorkPhoneType != ''
          AND (TRY_CONVERT(FLOAT, WorkPhoneType) IS NULL
               OR CONVERT(FLOAT, WorkPhoneType) NOT IN (SELECT ListValue FROM REPLACEME_ETL.dbo.ListItem WHERE ListID = 4073))

        -- CellPhoneType from List 4073
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Client', ClientID, 'CellPhoneType',
            CONCAT('"', CellPhoneType, '" is invalid. CellPhoneType must be a value from ListID 4073 (1=Primary, 2=Secondary, 3=Tertiary).')
        FROM Client
        WHERE CellPhoneType IS NOT NULL AND CellPhoneType != ''
          AND (TRY_CONVERT(FLOAT, CellPhoneType) IS NULL
               OR CONVERT(FLOAT, CellPhoneType) NOT IN (SELECT ListValue FROM REPLACEME_ETL.dbo.ListItem WHERE ListID = 4073))

        -- PhoneVoiceOptIn from List 100
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Client', ClientID, 'PhoneVoiceOptIn',
            CONCAT('"', PhoneVoiceOptIn, '" is invalid. PhoneVoiceOptIn must be a value from ListID 100 (1=Yes, 2=No).')
        FROM Client
        WHERE PhoneVoiceOptIn IS NOT NULL AND PhoneVoiceOptIn != ''
          AND (TRY_CONVERT(FLOAT, PhoneVoiceOptIn) IS NULL
               OR CONVERT(FLOAT, PhoneVoiceOptIn) NOT IN (SELECT ListValue FROM REPLACEME_ETL.dbo.ListItem WHERE ListID = 100))

        -- PhoneTextOptIn from List 100
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Client', ClientID, 'PhoneTextOptIn',
            CONCAT('"', PhoneTextOptIn, '" is invalid. PhoneTextOptIn must be a value from ListID 100 (1=Yes, 2=No).')
        FROM Client
        WHERE PhoneTextOptIn IS NOT NULL AND PhoneTextOptIn != ''
          AND (TRY_CONVERT(FLOAT, PhoneTextOptIn) IS NULL
               OR CONVERT(FLOAT, PhoneTextOptIn) NOT IN (SELECT ListValue FROM REPLACEME_ETL.dbo.ListItem WHERE ListID = 100))

        -- EmailOptIn from List 100
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Client', ClientID, 'EmailOptIn',
            CONCAT('"', EmailOptIn, '" is invalid. EmailOptIn must be a value from ListID 100 (1=Yes, 2=No).')
        FROM Client
        WHERE EmailOptIn IS NOT NULL AND EmailOptIn != ''
          AND (TRY_CONVERT(FLOAT, EmailOptIn) IS NULL
               OR CONVERT(FLOAT, EmailOptIn) NOT IN (SELECT ListValue FROM REPLACEME_ETL.dbo.ListItem WHERE ListID = 100))

        -- Restriction from List 25
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Client', ClientID, 'Restriction',
            CONCAT('"', Restriction, '" is invalid. Restriction must be a value from ListID 25 (1=Shared, 2=Not Shared).')
        FROM Client
        WHERE Restriction IS NOT NULL AND Restriction != ''
          AND (TRY_CONVERT(FLOAT, Restriction) IS NULL
               OR Restriction NOT IN (SELECT ListValue FROM REPLACEME_ETL.dbo.ListItem WHERE ListID = 25))

        -- CitizenshipStatusID from List 127
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Client', ClientID, 'CitizenshipStatusID',
            CONCAT('"', CitizenshipStatusID, '" is invalid. CitizenshipStatusID must be a value from ListID 127.')
        FROM Client
        WHERE CitizenshipStatusID IS NOT NULL AND CitizenshipStatusID != ''
          AND (TRY_CONVERT(FLOAT, CitizenshipStatusID) IS NULL
               OR CitizenshipStatusID NOT IN (SELECT ListValue FROM REPLACEME_ETL.dbo.ListItem WHERE ListID = 127))

        -- Address max 100 chars
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Client', ClientID, 'Address',
            CONCAT('"', Address, '" is too long. Address cannot exceed 100 characters.')
        FROM Client WHERE LEN(Address) > 100

        -- Address2 max 100 chars
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Client', ClientID, 'Address2',
            CONCAT('"', Address2, '" is too long. Address2 cannot exceed 100 characters.')
        FROM Client WHERE LEN(Address2) > 100

        -- City max 25 chars
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Client', ClientID, 'City',
            CONCAT('"', City, '" is too long. City cannot exceed 25 characters.')
        FROM Client WHERE LEN(City) > 25

        -- StateCode must be 2-letter, no digits
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Client', ClientID, 'StateCode',
            CONCAT('"', StateCode, '" is invalid. StateCode must be a valid 2-letter state abbreviation (e.g., CA, TX).')
        FROM Client
        WHERE StateCode IS NOT NULL AND StateCode != ''
          AND (StateCode LIKE '%[0-9]%' OR LEN(StateCode) > 2)

        -- County max 100 chars
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Client', ClientID, 'County',
            CONCAT('"', County, '" is too long. County cannot exceed 100 characters.')
        FROM Client WHERE LEN(County) > 100

        -- VeteranStatus from List 37
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Client', ClientID, 'VeteranStatus',
            CONCAT('"', VeteranStatus, '" is invalid. VeteranStatus must be a value from ListID 37.')
        FROM Client
        WHERE VeteranStatus IS NOT NULL AND VeteranStatus != ''
          AND (TRY_CONVERT(FLOAT, VeteranStatus) IS NULL
               OR VeteranStatus NOT IN (SELECT ListValue FROM REPLACEME_ETL.dbo.ListItem WHERE ListID = 37))

        -- MaritalStatus from List 128
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Client', ClientID, 'MaritalStatus',
            CONCAT('"', MaritalStatus, '" is invalid. MaritalStatus must be a value from ListID 128.')
        FROM Client
        WHERE MaritalStatus IS NOT NULL AND MaritalStatus != ''
          AND (TRY_CONVERT(FLOAT, MaritalStatus) IS NULL
               OR CONVERT(FLOAT, MaritalStatus) NOT IN (SELECT ListValue FROM REPLACEME_ETL.dbo.ListItem WHERE ListID = 128))

    END
END
GO

/* ====================================================================================
   CLIENT RACE
   ================================================================================== */
IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'ClientRace')
BEGIN
    IF EXISTS (SELECT 1 FROM ClientRace)
    BEGIN
        PRINT 'Starting ClientRace'

        -- ClientID must reference a valid Client
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'ClientRace', ClientID, 'ClientID',
            CONCAT('"', ClientID, '" is invalid. ClientID must match a ClientID from the Client sheet.')
        FROM ClientRace WHERE ClientID NOT IN (SELECT ClientID FROM Client WHERE ClientID IS NOT NULL)

        -- Race from List 6 (0 is valid for multi-racial)
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'ClientRace', ClientID, 'Race',
            CONCAT('"', Race, '" is invalid. Race must be a value from ListID 6.')
        FROM ClientRace
        WHERE Race IS NOT NULL
          AND Race NOT IN (SELECT ListValue FROM REPLACEME_ETL.dbo.ListItem WHERE ListID = 6)

    END
END
GO

/* ====================================================================================
   ADDRESS HISTORY
   ================================================================================== */
IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'AddressHistory')
BEGIN
    IF EXISTS (SELECT 1 FROM AddressHistory)
    BEGIN
        PRINT 'Starting AddressHistory'

        -- Duplicate AddressID
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'AddressHistory', AddressID, 'AddressID',
            CONCAT('"', AddressID, '" appears more than once. Each AddressID must be unique.')
        FROM AddressHistory WHERE AddressID IN (SELECT AddressID FROM AddressHistory GROUP BY AddressID HAVING COUNT(*) > 1)

        -- AddressID blank
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'AddressHistory', AddressID, 'AddressID',
            'AddressID is blank. AddressID is required.'
        FROM AddressHistory WHERE AddressID IS NULL OR AddressID = ''

        -- ClientID must reference a valid Client
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'AddressHistory', AddressID, 'ClientID',
            CONCAT('"', ClientID, '" is invalid. ClientID must match a ClientID from the Client sheet.')
        FROM AddressHistory WHERE ClientID NOT IN (SELECT ClientID FROM Client WHERE ClientID IS NOT NULL)

        -- AddressType from List 5 (required: 2=Mailing, 3=Previous — not 1 which is current)
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'AddressHistory', AddressID, 'AddressType',
            CONCAT('"', ISNULL(AddressType,'(blank)'), '" is invalid. AddressType is required and must be 2 (Mailing Address) or 3 (Previous Address). Do not use 1 — current address goes on the Client sheet.')
        FROM AddressHistory
        WHERE TRY_CONVERT(FLOAT, AddressType) IS NULL
           OR AddressType IS NULL
           OR AddressType = '1'
           OR (TRY_CONVERT(FLOAT, AddressType) IS NOT NULL
               AND AddressType NOT IN (SELECT ListValue FROM REPLACEME_ETL.dbo.ListItem WHERE ListID = 5))

        -- StateCode check
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'AddressHistory', AddressID, 'StateCode',
            CONCAT('"', StateCode, '" is invalid. StateCode must be a valid 2-letter state abbreviation.')
        FROM AddressHistory
        WHERE StateCode IS NOT NULL AND StateCode != ''
          AND (StateCode LIKE '%[0-9]%' OR LEN(StateCode) > 2)

        -- City max 25 chars
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'AddressHistory', AddressID, 'City',
            CONCAT('"', City, '" is too long. City cannot exceed 25 characters.')
        FROM AddressHistory WHERE LEN(City) > 25

    END
END
GO

/* ====================================================================================
   ENTITY VETERAN ERA
   ================================================================================== */
IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'EntityVeteranEra')
BEGIN
    IF EXISTS (SELECT 1 FROM EntityVeteranEra)
    BEGIN
        PRINT 'Starting EntityVeteranEra'

        -- Duplicate EntityVeteranEraID
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'EntityVeteranEra', EntityVeteranEraID, 'EntityVeteranEraID',
            CONCAT('"', EntityVeteranEraID, '" appears more than once. Each EntityVeteranEraID must be unique.')
        FROM EntityVeteranEra WHERE EntityVeteranEraID IN (SELECT EntityVeteranEraID FROM EntityVeteranEra GROUP BY EntityVeteranEraID HAVING COUNT(*) > 1)

        -- EntityVeteranEraID blank
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'EntityVeteranEra', EntityVeteranEraID, 'EntityVeteranEraID',
            'EntityVeteranEraID is blank. EntityVeteranEraID is required.'
        FROM EntityVeteranEra WHERE EntityVeteranEraID IS NULL OR EntityVeteranEraID = ''

        -- ClientID must reference a valid Client
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'EntityVeteranEra', EntityVeteranEraID, 'ClientID',
            CONCAT('"', ClientID, '" is invalid. ClientID must match a ClientID from the Client sheet.')
        FROM EntityVeteranEra WHERE ClientID NOT IN (SELECT ClientID FROM Client WHERE ClientID IS NOT NULL)

        -- Score from List 37
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'EntityVeteranEra', EntityVeteranEraID, 'Score',
            CONCAT('"', ISNULL(Score,'(blank)'), '" is invalid. Score is required and must be a value from ListID 37 (1=Yes, 2=No, etc.).')
        FROM EntityVeteranEra
        WHERE TRY_CONVERT(FLOAT, Score) IS NULL
           OR Score IS NULL
           OR (TRY_CONVERT(FLOAT, Score) IS NOT NULL
               AND Score NOT IN (SELECT ListValue FROM REPLACEME_ETL.dbo.ListItem WHERE ListID = 37))

        -- VeteranEraTypeID must be valid
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'EntityVeteranEra', EntityVeteranEraID, 'VeteranEraTypeID',
            CONCAT('"', ISNULL(VeteranEraTypeID,'(blank)'), '" is invalid. VeteranEraTypeID is required and must be a valid value from the VeteranEraType table in the destination database.')
        FROM EntityVeteranEra
        WHERE TRY_CONVERT(FLOAT, VeteranEraTypeID) IS NULL
           OR VeteranEraTypeID IS NULL
           OR (TRY_CONVERT(FLOAT, VeteranEraTypeID) IS NOT NULL
               AND VeteranEraTypeID NOT IN (SELECT CONVERT(VARCHAR, VeteranEraTypeID) FROM REPLACEME_ETL.dbo.VeteranEraType))

    END
END
GO

/* ====================================================================================
   ENTITY VETERAN INFO
   ================================================================================== */
IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'EntityVeteranInfo')
BEGIN
    IF EXISTS (SELECT 1 FROM EntityVeteranInfo)
    BEGIN
        PRINT 'Starting EntityVeteranInfo'

        -- ClientID must reference a valid Client
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'EntityVeteranInfo', ClientID, 'ClientID',
            CONCAT('"', ClientID, '" is invalid. ClientID must match a ClientID from the Client sheet.')
        FROM EntityVeteranInfo WHERE ClientID NOT IN (SELECT ClientID FROM Client WHERE ClientID IS NOT NULL)

        -- VetServedWarZone from List 37
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'EntityVeteranInfo', ClientID, 'VetServedWarZone',
            CONCAT('"', VetServedWarZone, '" is invalid. VetServedWarZone must be a value from ListID 37.')
        FROM EntityVeteranInfo
        WHERE VetServedWarZone IS NOT NULL AND VetServedWarZone != ''
          AND (TRY_CONVERT(FLOAT, VetServedWarZone) IS NULL
               OR VetServedWarZone NOT IN (SELECT ListValue FROM REPLACEME_ETL.dbo.ListItem WHERE ListID = 37))

        -- VetWarZoneName from List 589
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'EntityVeteranInfo', ClientID, 'VetWarZoneName',
            CONCAT('"', VetWarZoneName, '" is invalid. VetWarZoneName must be a value from ListID 589.')
        FROM EntityVeteranInfo
        WHERE VetWarZoneName IS NOT NULL AND VetWarZoneName != ''
          AND (TRY_CONVERT(FLOAT, VetWarZoneName) IS NULL
               OR VetWarZoneName NOT IN (SELECT ListValue FROM REPLACEME_ETL.dbo.ListItem WHERE ListID = 589))

        -- VetReceivedFire from List 37
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'EntityVeteranInfo', ClientID, 'VetReceivedFire',
            CONCAT('"', VetReceivedFire, '" is invalid. VetReceivedFire must be a value from ListID 37.')
        FROM EntityVeteranInfo
        WHERE VetReceivedFire IS NOT NULL AND VetReceivedFire != ''
          AND (TRY_CONVERT(FLOAT, VetReceivedFire) IS NULL
               OR VetReceivedFire NOT IN (SELECT ListValue FROM REPLACEME_ETL.dbo.ListItem WHERE ListID = 37))

        -- VetBranch from List 66
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'EntityVeteranInfo', ClientID, 'VetBranch',
            CONCAT('"', VetBranch, '" is invalid. VetBranch must be a value from ListID 66.')
        FROM EntityVeteranInfo
        WHERE VetBranch IS NOT NULL AND VetBranch != ''
          AND (TRY_CONVERT(FLOAT, VetBranch) IS NULL
               OR VetBranch NOT IN (SELECT ListValue FROM REPLACEME_ETL.dbo.ListItem WHERE ListID = 66))

        -- VetDischargeStatus from List 65
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'EntityVeteranInfo', ClientID, 'VetDischargeStatus',
            CONCAT('"', VetDischargeStatus, '" is invalid. VetDischargeStatus must be a value from ListID 65.')
        FROM EntityVeteranInfo
        WHERE VetDischargeStatus IS NOT NULL AND VetDischargeStatus != ''
          AND (TRY_CONVERT(FLOAT, VetDischargeStatus) IS NULL
               OR VetDischargeStatus NOT IN (SELECT ListValue FROM REPLACEME_ETL.dbo.ListItem WHERE ListID = 65))

        -- DateEnteredService must be valid date
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'EntityVeteranInfo', ClientID, 'DateEnteredService',
            CONCAT('"', DateEnteredService, '" is not a valid date.')
        FROM EntityVeteranInfo
        WHERE DateEnteredService IS NOT NULL AND DateEnteredService != ''
          AND TRY_CONVERT(DATE, DateEnteredService) IS NULL

        -- DateSeparatedFromService must be valid date
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'EntityVeteranInfo', ClientID, 'DateSeparatedFromService',
            CONCAT('"', DateSeparatedFromService, '" is not a valid date.')
        FROM EntityVeteranInfo
        WHERE DateSeparatedFromService IS NOT NULL AND DateSeparatedFromService != ''
          AND TRY_CONVERT(DATE, DateSeparatedFromService) IS NULL

        -- ServiceConnectedDisability from List 37
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'EntityVeteranInfo', ClientID, 'ServiceConnectedDisability',
            CONCAT('"', ServiceConnectedDisability, '" is invalid. ServiceConnectedDisability must be a value from ListID 37.')
        FROM EntityVeteranInfo
        WHERE ServiceConnectedDisability IS NOT NULL AND ServiceConnectedDisability != ''
          AND (TRY_CONVERT(FLOAT, ServiceConnectedDisability) IS NULL
               OR ServiceConnectedDisability NOT IN (SELECT ListValue FROM REPLACEME_ETL.dbo.ListItem WHERE ListID = 37))

        -- DisabilityRewardLevel from List 702
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'EntityVeteranInfo', ClientID, 'DisabilityRewardLevel',
            CONCAT('"', DisabilityRewardLevel, '" is invalid. DisabilityRewardLevel must be a value from ListID 702.')
        FROM EntityVeteranInfo
        WHERE DisabilityRewardLevel IS NOT NULL AND DisabilityRewardLevel != ''
          AND (TRY_CONVERT(FLOAT, DisabilityRewardLevel) IS NULL
               OR DisabilityRewardLevel NOT IN (SELECT ListValue FROM REPLACEME_ETL.dbo.ListItem WHERE ListID = 702))

    END
END
GO

/* ====================================================================================
   ENROLLMENT
   ================================================================================== */
IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'Enrollment')
BEGIN
    IF EXISTS (SELECT 1 FROM Enrollment)
    BEGIN
        PRINT 'Starting Enrollment'

        -- Duplicate MemberID
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Enrollment', MemberID, 'MemberID',
            CONCAT('"', MemberID, '" appears more than once. Each MemberID must be unique.')
        FROM Enrollment WHERE MemberID IN (SELECT MemberID FROM Enrollment GROUP BY MemberID HAVING COUNT(*) > 1)

        -- Required fields are not blank
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT 'Enrollment', EnrollmentID,
            CASE WHEN MemberID IS NULL OR MemberID = ''      THEN 'MemberID'
                 WHEN EnrollmentID IS NULL OR EnrollmentID ='' THEN 'EnrollmentID'
                 WHEN ProgramID IS NULL OR ProgramID = ''    THEN 'ProgramID'
                 WHEN ClientID IS NULL OR ClientID = ''      THEN 'ClientID'
                 WHEN [Status] IS NULL OR [Status] = ''      THEN 'Status'
                 WHEN BeginDate IS NULL OR BeginDate = ''    THEN 'BeginDate'
            END,
            CASE WHEN MemberID IS NULL OR MemberID = ''      THEN 'MemberID is blank and is required.'
                 WHEN EnrollmentID IS NULL OR EnrollmentID ='' THEN 'EnrollmentID is blank and is required.'
                 WHEN ProgramID IS NULL OR ProgramID = ''    THEN 'ProgramID is blank and is required.'
                 WHEN ClientID IS NULL OR ClientID = ''      THEN 'ClientID is blank and is required.'
                 WHEN [Status] IS NULL OR [Status] = ''      THEN 'Status is blank and is required.'
                 WHEN BeginDate IS NULL OR BeginDate = ''    THEN 'BeginDate is blank and is required.'
            END
        FROM Enrollment
        WHERE MemberID IS NULL OR MemberID = ''
           OR EnrollmentID IS NULL OR EnrollmentID = ''
           OR ProgramID IS NULL OR ProgramID = ''
           OR ClientID IS NULL OR ClientID = ''
           OR [Status] IS NULL OR [Status] = ''
           OR BeginDate IS NULL OR BeginDate = ''

        -- ProgramID must be valid
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Enrollment', MemberID, 'ProgramID',
            CONCAT('"', ProgramID, '" is invalid. ProgramID must match a value in the Program sheet or the destination database.')
        FROM Enrollment
        WHERE TRY_CONVERT(FLOAT, ProgramID) IS NULL
           OR ProgramID IS NULL
           OR (ProgramID NOT IN (SELECT CONVERT(VARCHAR, ProgramID) FROM REPLACEME_ETL.dbo.[Program])
               AND ProgramID NOT IN (SELECT ProgramID FROM [Program]))

        -- ClientID must reference a valid Client
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Enrollment', MemberID, 'ClientID',
            CONCAT('"', Enrollment.ClientID, '" is invalid. ClientID must match a ClientID from the Client sheet.')
        FROM Enrollment
        LEFT JOIN Client C ON C.ClientID = Enrollment.ClientID
        WHERE C.ClientID IS NULL

        -- ProviderID must be valid
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Enrollment', MemberID, 'ProviderID',
            CONCAT('"', ProviderID, '" is invalid. ProviderID is required and must match a value in the Provider sheet or the destination database.')
        FROM Enrollment
        WHERE TRY_CONVERT(FLOAT, ProviderID) IS NULL
           OR ProviderID IS NULL
           OR (ProviderID IS NOT NULL
               AND ProviderID NOT IN (SELECT ProviderID FROM [Provider])
               AND ProviderID NOT IN (SELECT CONVERT(VARCHAR, EntityID) FROM REPLACEME_ETL.dbo.[Provider]))

        -- Status from List 52
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Enrollment', MemberID, 'Status',
            CONCAT('"', [Status], '" is invalid. Status must be a value from ListID 52 (e.g., 100=Enrolled, 200=Exited).')
        FROM Enrollment
        WHERE TRY_CONVERT(FLOAT, [Status]) IS NULL
           OR (TRY_CONVERT(FLOAT, [Status]) IS NOT NULL
               AND [Status] NOT IN (SELECT ListValue FROM REPLACEME_ETL.dbo.ListItem WHERE ListID = 52))

        -- BeginDate must be valid date
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Enrollment', MemberID, 'BeginDate',
            CONCAT('"', BeginDate, '" is not a valid date. BeginDate is required and must be a valid date.')
        FROM Enrollment WHERE TRY_CONVERT(DATE, BeginDate) IS NULL

        -- ExitDate must be valid date (optional)
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Enrollment', MemberID, 'ExitDate',
            CONCAT('"', ExitDate, '" is not a valid date. ExitDate is optional but must be a valid date if provided.')
        FROM Enrollment WHERE ExitDate IS NOT NULL AND ExitDate != '' AND TRY_CONVERT(DATE, ExitDate) IS NULL

        -- CreatedDate must be valid date (optional)
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Enrollment', MemberID, 'CreatedDate',
            CONCAT('"', CreatedDate, '" is not a valid date. CreatedDate is optional but must be a valid date if provided.')
        FROM Enrollment WHERE CreatedDate IS NOT NULL AND TRY_CONVERT(DATE, CreatedDate) IS NULL

        -- Duplicate EnrollmentID + ClientID combination
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT 'Enrollment', ClientID, 'ClientID',
            CONCAT('The combination of EnrollmentID "', EnrollmentID, '" and ClientID "', ClientID, '" appears more than once. A client can only be in the same enrollment once.')
        FROM (
            SELECT EnrollmentID, ClientID
            FROM Enrollment
            WHERE EnrollmentID IS NOT NULL AND ClientID IS NOT NULL
            GROUP BY EnrollmentID, ClientID
            HAVING COUNT(*) > 1
        ) X

        -- Restriction from List 25
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Enrollment', MemberID, 'Restriction',
            CONCAT('"', Restriction, '" is invalid. Restriction must be a value from ListID 25 (1=Shared, 2=Not Shared).')
        FROM Enrollment
        WHERE Restriction IS NOT NULL AND Restriction != ''
          AND (TRY_CONVERT(FLOAT, Restriction) IS NULL
               OR Restriction NOT IN (SELECT ListValue FROM REPLACEME_ETL.dbo.ListItem WHERE ListID = 25))

    END
END
GO

/* ====================================================================================
   ENROLLMENT SERVICE PLAN
   ================================================================================== */
IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'EnrollmentServicePlan')
BEGIN
    IF EXISTS (SELECT 1 FROM EnrollmentServicePlan)
    BEGIN
        PRINT 'Starting EnrollmentServicePlan'

        -- Duplicate EnrollmentServicePlanID
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'EnrollmentServicePlan', EnrollmentServicePlanID, 'EnrollmentServicePlanID',
            CONCAT('"', EnrollmentServicePlanID, '" appears more than once. Each EnrollmentServicePlanID must be unique.')
        FROM EnrollmentServicePlan WHERE EnrollmentServicePlanID IN (SELECT EnrollmentServicePlanID FROM EnrollmentServicePlan GROUP BY EnrollmentServicePlanID HAVING COUNT(*) > 1)

        -- EnrollmentServicePlanID blank
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'EnrollmentServicePlan', EnrollmentServicePlanID, 'EnrollmentServicePlanID',
            'EnrollmentServicePlanID is blank. EnrollmentServicePlanID is required.'
        FROM EnrollmentServicePlan WHERE EnrollmentServicePlanID IS NULL OR EnrollmentServicePlanID = ''

        -- EnrollmentID must be valid
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'EnrollmentServicePlan', EnrollmentServicePlanID, 'EnrollmentID',
            CONCAT('"', ISNULL(EnrollmentID,'(blank)'), '" is invalid. EnrollmentID is required and must match a value from the Enrollment sheet.')
        FROM EnrollmentServicePlan
        WHERE EnrollmentID IS NULL OR EnrollmentID = ''
           OR EnrollmentID NOT IN (SELECT EnrollmentID FROM Enrollment WHERE EnrollmentID IS NOT NULL)

        -- ClientID must reference a valid Client
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'EnrollmentServicePlan', EnrollmentServicePlanID, 'ClientID',
            CONCAT('"', ISNULL(ClientID,'(blank)'), '" is invalid. ClientID is required and must match a ClientID from the Client sheet.')
        FROM EnrollmentServicePlan
        WHERE ClientID IS NULL OR ClientID = ''
           OR ClientID NOT IN (SELECT ClientID FROM Client WHERE ClientID IS NOT NULL)

        -- PlanBeginDate required and valid
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'EnrollmentServicePlan', EnrollmentServicePlanID, 'PlanBeginDate',
            CONCAT('"', ISNULL(PlanBeginDate,'(blank)'), '" is not a valid date. PlanBeginDate is required and must be a valid date.')
        FROM EnrollmentServicePlan WHERE TRY_CONVERT(DATE, PlanBeginDate) IS NULL

        -- PlanEndDate optional but must be valid date
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'EnrollmentServicePlan', EnrollmentServicePlanID, 'PlanEndDate',
            CONCAT('"', PlanEndDate, '" is not a valid date. PlanEndDate is optional but must be a valid date if provided.')
        FROM EnrollmentServicePlan WHERE PlanEndDate IS NOT NULL AND PlanEndDate != '' AND TRY_CONVERT(DATE, PlanEndDate) IS NULL

        -- ActualCompletedDate optional, must be valid date
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'EnrollmentServicePlan', EnrollmentServicePlanID, 'ActualCompletedDate',
            CONCAT('"', ActualCompletedDate, '" is not a valid date. ActualCompletedDate is optional but must be a valid date if provided.')
        FROM EnrollmentServicePlan WHERE ActualCompletedDate IS NOT NULL AND ActualCompletedDate != '' AND TRY_CONVERT(DATE, ActualCompletedDate) IS NULL

    END
END
GO

/* ====================================================================================
   CASE MANAGER ASSIGNMENT
   ================================================================================== */
IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'CaseManagerAssignment')
BEGIN
    IF EXISTS (SELECT 1 FROM CaseManagerAssignment)
    BEGIN
        PRINT 'Starting CaseManagerAssignment'

        -- Duplicate AssignmentID
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'CaseManagerAssignment', AssignmentID, 'AssignmentID',
            CONCAT('"', AssignmentID, '" appears more than once. Each AssignmentID must be unique.')
        FROM CaseManagerAssignment WHERE AssignmentID IN (SELECT AssignmentID FROM CaseManagerAssignment GROUP BY AssignmentID HAVING COUNT(*) > 1)

        -- AssignmentID blank
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'CaseManagerAssignment', AssignmentID, 'AssignmentID',
            'AssignmentID is blank. AssignmentID is required.'
        FROM CaseManagerAssignment WHERE AssignmentID IS NULL OR AssignmentID = ''

        -- ClientID must be valid
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'CaseManagerAssignment', AssignmentID, 'ClientID',
            CONCAT('"', ISNULL(ClientID,'(blank)'), '" is invalid. ClientID is required and must match a ClientID from the Client sheet.')
        FROM CaseManagerAssignment
        WHERE ClientID IS NULL OR ClientID = ''
           OR ClientID NOT IN (SELECT ClientID FROM Client WHERE ClientID IS NOT NULL)

        -- UserID must be valid
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'CaseManagerAssignment', AssignmentID, 'UserID',
            CONCAT('"', ISNULL(UserID,'(blank)'), '" is invalid. UserID is required and must match a UserID from the Users sheet or the destination database.')
        FROM CaseManagerAssignment
        WHERE UserID IS NULL OR UserID = ''
           OR (TRY_CONVERT(FLOAT, UserID) IS NULL)
           OR (TRY_CONVERT(FLOAT, UserID) IS NOT NULL
               AND UserID NOT IN (SELECT UserID FROM Users WHERE UserID IS NOT NULL)
               AND UserID NOT IN (SELECT CONVERT(VARCHAR, EntityID) FROM REPLACEME_ETL.dbo.Users))

        -- EnrollmentID optional but must be valid if provided
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'CaseManagerAssignment', AssignmentID, 'EnrollmentID',
            CONCAT('"', EnrollmentID, '" is invalid. EnrollmentID must match a value from the Enrollment sheet if provided.')
        FROM CaseManagerAssignment
        WHERE EnrollmentID IS NOT NULL AND EnrollmentID != ''
          AND EnrollmentID NOT IN (SELECT EnrollmentID FROM Enrollment WHERE EnrollmentID IS NOT NULL)

        -- BeginDate required and valid
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'CaseManagerAssignment', AssignmentID, 'BeginDate',
            CONCAT('"', ISNULL(BeginDate,'(blank)'), '" is not a valid date. BeginDate is required.')
        FROM CaseManagerAssignment WHERE BeginDate IS NULL OR BeginDate = '' OR TRY_CONVERT(DATE, BeginDate) IS NULL

        -- EndDate optional, must be valid date
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'CaseManagerAssignment', AssignmentID, 'EndDate',
            CONCAT('"', EndDate, '" is not a valid date. EndDate is optional but must be a valid date if provided.')
        FROM CaseManagerAssignment WHERE EndDate IS NOT NULL AND EndDate != '' AND TRY_CONVERT(DATE, EndDate) IS NULL

        -- Restriction from List 25
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'CaseManagerAssignment', AssignmentID, 'Restriction',
            CONCAT('"', Restriction, '" is invalid. Restriction must be a value from ListID 25 (1=Shared, 2=Not Shared).')
        FROM CaseManagerAssignment
        WHERE Restriction IS NOT NULL AND Restriction != ''
          AND (TRY_CONVERT(FLOAT, Restriction) IS NULL
               OR Restriction NOT IN (SELECT ListValue FROM REPLACEME_ETL.dbo.ListItem WHERE ListID = 25))

    END
END
GO

/* ====================================================================================
   CASE NOTES
   ================================================================================== */
IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'CaseNotes')
BEGIN
    IF EXISTS (SELECT 1 FROM CaseNotes)
    BEGIN
        PRINT 'Starting CaseNotes'

        -- Duplicate CaseNoteID
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'CaseNotes', CaseNoteID, 'CaseNoteID',
            CONCAT('"', CaseNoteID, '" appears more than once. Each CaseNoteID must be unique.')
        FROM CaseNotes WHERE CaseNoteID IN (SELECT CaseNoteID FROM CaseNotes GROUP BY CaseNoteID HAVING COUNT(*) > 1)

        -- CaseNoteID blank
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'CaseNotes', CaseNoteID, 'CaseNoteID',
            'CaseNoteID is blank. CaseNoteID is required.'
        FROM CaseNotes WHERE CaseNoteID IS NULL OR CaseNoteID = ''

        -- CaseNoteSummary required, max 50 chars
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'CaseNotes', CaseNoteID, 'CaseNoteSummary',
            'CaseNoteSummary is blank. CaseNoteSummary is required.'
        FROM CaseNotes WHERE CaseNoteSummary IS NULL OR CaseNoteSummary = ''

        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'CaseNotes', CaseNoteID, 'CaseNoteSummary',
            CONCAT('"', CaseNoteSummary, '" is too long. CaseNoteSummary cannot exceed 50 characters.')
        FROM CaseNotes WHERE LEN(CaseNoteSummary) > 50

        -- Body required (warning if blank)
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorType, ErrorMessage)
        SELECT DISTINCT 'CaseNotes', CaseNoteID, 'Body', 'Warning',
            'Body (case note text) is blank. It is required — the note body will be set to a blank space if not provided.'
        FROM CaseNotes WHERE Body IS NULL OR Body = ''

        -- ClientID must be valid
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'CaseNotes', CaseNoteID, 'ClientID',
            CONCAT('"', CaseNotes.ClientID, '" is invalid. ClientID must match a ClientID from the Client sheet.')
        FROM CaseNotes
        LEFT JOIN Client CL ON CL.ClientID = CaseNotes.ClientID
        WHERE CL.ClientID IS NULL

        -- CreatedDate optional, must be valid date (warning)
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorType, ErrorMessage)
        SELECT DISTINCT 'CaseNotes', CaseNoteID, 'CreatedDate', 'Warning',
            CONCAT('"', CreatedDate, '" is not a valid date. Notes without a valid CreatedDate will be assigned the import date.')
        FROM CaseNotes WHERE (CreatedDate IS NOT NULL AND TRY_CONVERT(SMALLDATETIME, CreatedDate) IS NULL)

        -- Restriction from List 36
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'CaseNotes', CaseNoteID, 'Restriction',
            CONCAT('"', Restriction, '" is invalid. Restriction must be a value from ListID 36 (1=Shared, 2=Not Shared, 3=My Eyes Only).')
        FROM CaseNotes
        WHERE Restriction IS NOT NULL AND Restriction != ''
          AND (TRY_CONVERT(FLOAT, Restriction) IS NULL
               OR Restriction NOT IN (SELECT ListValue FROM REPLACEME_ETL.dbo.ListItem WHERE ListID = 36))

        -- CaseNoteTypeID from List 360
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'CaseNotes', CaseNoteID, 'CaseNoteTypeID',
            CONCAT('"', CaseNoteTypeID, '" is invalid. CaseNoteTypeID must be a value from ListID 360.')
        FROM CaseNotes
        WHERE CaseNoteTypeID IS NOT NULL AND CaseNoteTypeID != ''
          AND (TRY_CONVERT(FLOAT, CaseNoteTypeID) IS NULL
               OR CaseNoteTypeID NOT IN (SELECT ListValue FROM REPLACEME_ETL.dbo.ListItem WHERE ListID = 360))

        -- EnrollmentID optional, must be valid if provided
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'CaseNotes', CaseNoteID, 'EnrollmentID',
            CONCAT('"', EnrollmentID, '" is invalid. EnrollmentID must match a value from the Enrollment sheet if provided.')
        FROM CaseNotes
        WHERE EnrollmentID IS NOT NULL AND EnrollmentID != ''
          AND EnrollmentID NOT IN (SELECT EnrollmentID FROM Enrollment WHERE EnrollmentID IS NOT NULL)

    END
END
GO

/* ====================================================================================
   ENTITY CONTACT
   ================================================================================== */
IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'EntityContact')
BEGIN
    IF EXISTS (SELECT 1 FROM EntityContact)
    BEGIN
        PRINT 'Starting EntityContact'

        -- Duplicate ContactID
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'EntityContact', ContactID, 'ContactID',
            CONCAT('"', ContactID, '" appears more than once. Each ContactID must be unique.')
        FROM EntityContact WHERE ContactID IN (SELECT ContactID FROM EntityContact GROUP BY ContactID HAVING COUNT(*) > 1)

        -- ContactID blank
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'EntityContact', ContactID, 'ContactID',
            'ContactID is blank. ContactID is required.'
        FROM EntityContact WHERE ContactID IS NULL OR ContactID = ''

        -- EntityContextType required: must be 11 (Client) or 84 (Provider)
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'EntityContact', ContactID, 'EntityContextType',
            CONCAT('"', ISNULL(EntityContextType,'(blank)'), '" is invalid. EntityContextType is required and must be 11 (Client Contact) or 84 (Provider Contact).')
        FROM EntityContact
        WHERE EntityContextType IS NULL OR EntityContextType = ''
           OR EntityContextType NOT IN ('11','84')

        -- ParentEntityID required; must be a valid ClientID when EntityContextType = 11
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'EntityContact', ContactID, 'ParentEntityID',
            CONCAT('"', ISNULL(ParentEntityID,'(blank)'), '" is invalid. ParentEntityID must match a ClientID from the Client sheet when EntityContextType is 11 (Client Contact).')
        FROM EntityContact
        WHERE EntityContextType = '11'
          AND (ParentEntityID IS NULL OR ParentEntityID = ''
               OR ParentEntityID NOT IN (SELECT ClientID FROM Client WHERE ClientID IS NOT NULL))

        -- ParentEntityID must be valid ProviderID when EntityContextType = 84
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'EntityContact', ContactID, 'ParentEntityID',
            CONCAT('"', ISNULL(ParentEntityID,'(blank)'), '" is invalid. ParentEntityID must match a ProviderID from the Provider sheet when EntityContextType is 84 (Provider Contact).')
        FROM EntityContact
        WHERE EntityContextType = '84'
          AND (ParentEntityID IS NULL OR ParentEntityID = ''
               OR ParentEntityID NOT IN (SELECT ProviderID FROM [Provider] WHERE ProviderID IS NOT NULL))

        -- ContactLastName max 50 chars
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'EntityContact', ContactID, 'ContactLastName',
            CONCAT('"', ContactLastName, '" is too long. ContactLastName cannot exceed 50 characters.')
        FROM EntityContact WHERE LEN(ContactLastName) > 50

        -- ContactFirstName max 50 chars
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'EntityContact', ContactID, 'ContactFirstName',
            CONCAT('"', ContactFirstName, '" is too long. ContactFirstName cannot exceed 50 characters.')
        FROM EntityContact WHERE LEN(ContactFirstName) > 50

        -- BeginDate optional but must be valid date
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'EntityContact', ContactID, 'BeginDate',
            CONCAT('"', BeginDate, '" is not a valid date. BeginDate is optional but must be a valid date if provided.')
        FROM EntityContact WHERE BeginDate IS NOT NULL AND BeginDate != '' AND TRY_CONVERT(DATE, BeginDate) IS NULL

        -- EndDate optional but must be valid date
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'EntityContact', ContactID, 'EndDate',
            CONCAT('"', EndDate, '" is not a valid date. EndDate is optional but must be a valid date if provided.')
        FROM EntityContact WHERE EndDate IS NOT NULL AND EndDate != '' AND TRY_CONVERT(DATE, EndDate) IS NULL

        -- IsEmergencyContact must be 0 or 1
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'EntityContact', ContactID, 'IsEmergencyContact',
            CONCAT('"', IsEmergencyContact, '" is invalid. IsEmergencyContact must be 1 (Yes) or 0 (No).')
        FROM EntityContact
        WHERE IsEmergencyContact IS NOT NULL AND IsEmergencyContact != ''
          AND IsEmergencyContact NOT IN ('0','1')

        -- RelationshipTypeID from List 86
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'EntityContact', ContactID, 'RelationshipTypeID',
            CONCAT('"', RelationshipTypeID, '" is invalid. RelationshipTypeID must be a value from ListID 86 (see LookupValue tab for options).')
        FROM EntityContact
        WHERE RelationshipTypeID IS NOT NULL AND RelationshipTypeID != ''
          AND (TRY_CONVERT(FLOAT, RelationshipTypeID) IS NULL
               OR RelationshipTypeID NOT IN (SELECT ListValue FROM REPLACEME_ETL.dbo.ListItem WHERE ListID = 86))

        -- CreatedDate optional, must be valid date
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'EntityContact', ContactID, 'CreatedDate',
            CONCAT('"', CreatedDate, '" is not a valid date. CreatedDate is optional but must be a valid date if provided.')
        FROM EntityContact WHERE CreatedDate IS NOT NULL AND CreatedDate != '' AND TRY_CONVERT(DATE, CreatedDate) IS NULL

        -- AddressBeginDate optional, must be valid date
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'EntityContact', ContactID, 'AddressBeginDate',
            CONCAT('"', AddressBeginDate, '" is not a valid date. AddressBeginDate is optional but must be a valid date if provided.')
        FROM EntityContact WHERE AddressBeginDate IS NOT NULL AND AddressBeginDate != '' AND TRY_CONVERT(DATE, AddressBeginDate) IS NULL

        -- AddressEndDate optional, must be valid date
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'EntityContact', ContactID, 'AddressEndDate',
            CONCAT('"', AddressEndDate, '" is not a valid date. AddressEndDate is optional but must be a valid date if provided.')
        FROM EntityContact WHERE AddressEndDate IS NOT NULL AND AddressEndDate != '' AND TRY_CONVERT(DATE, AddressEndDate) IS NULL

    END
END
GO

/* ====================================================================================
   SERVICE TYPE
   ================================================================================== */
IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'ServiceType')
BEGIN
    IF EXISTS (SELECT 1 FROM ServiceType)
    BEGIN
        PRINT 'Starting ServiceType'

        -- Duplicate ServiceTypeID
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'ServiceType', ServiceTypeID, 'ServiceTypeID',
            CONCAT('"', ServiceTypeID, '" appears more than once. Each ServiceTypeID must be unique.')
        FROM ServiceType WHERE ServiceTypeID IN (SELECT ServiceTypeID FROM ServiceType GROUP BY ServiceTypeID HAVING COUNT(*) > 1)

        -- ServiceTypeID must be numeric
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'ServiceType', ServiceTypeID, 'ServiceTypeID',
            CONCAT('"', ServiceTypeID, '" is not a valid ID. ServiceTypeID must be a whole number.')
        FROM ServiceType WHERE TRY_CONVERT(FLOAT, ServiceTypeID) IS NULL

        -- Description required
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'ServiceType', ServiceTypeID, 'Description',
            'Description is blank. A description for the service type is required.'
        FROM ServiceType WHERE Description IS NULL OR Description = ''

        -- UnitOfMeasure required, from List 2 (1-6)
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'ServiceType', ServiceTypeID, 'UnitOfMeasure',
            CONCAT('"', ISNULL(UnitOfMeasure,'(blank)'), '" is invalid. UnitOfMeasure is required and must be a value from ListID 2 (1=Days, 2=Hours, 3=Minutes, 4=Each, 5=Dollar, 6=Mileage).')
        FROM ServiceType
        WHERE TRY_CONVERT(INT, UnitOfMeasure) IS NULL
           OR TRY_CONVERT(INT, UnitOfMeasure) NOT IN (SELECT ListValue FROM REPLACEME_ETL.dbo.ListItem WHERE ListID = 2)

        -- UnitValue required, must be numeric
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'ServiceType', ServiceTypeID, 'UnitValue',
            CONCAT('"', ISNULL(UnitValue,'(blank)'), '" is invalid. UnitValue is required and must be a decimal number.')
        FROM ServiceType WHERE TRY_CONVERT(FLOAT, UnitValue) IS NULL

        -- DuplicateMinutes must be integer if provided
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'ServiceType', ServiceTypeID, 'DuplicateMinutes',
            CONCAT('"', DuplicateMinutes, '" is invalid. DuplicateMinutes must be a whole number (use 0 for no limit).')
        FROM ServiceType WHERE DuplicateMinutes IS NOT NULL AND TRY_CONVERT(INT, DuplicateMinutes) IS NULL

        -- CreatedBy must reference a valid user
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'ServiceType', ServiceTypeID, 'CreatedBy',
            CONCAT('"', CreatedBy, '" is invalid. CreatedBy must be a UserID from the Users sheet or a User EntityID from the destination database.')
        FROM ServiceType
        WHERE CreatedBy IS NOT NULL AND CreatedBy != ''
          AND (TRY_CONVERT(INT, CreatedBy) IS NULL
               OR (TRY_CONVERT(INT, CreatedBy) NOT IN (SELECT UserID FROM Users WHERE UserID IS NOT NULL)
                   AND TRY_CONVERT(INT, CreatedBy) NOT IN (SELECT EntityID FROM REPLACEME_ETL.dbo.Users)))

        -- CreatedDate optional, must be valid date
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'ServiceType', ServiceTypeID, 'CreatedDate',
            CONCAT('"', CreatedDate, '" is not a valid date. CreatedDate is optional but must be a valid date if provided.')
        FROM ServiceType WHERE CreatedDate IS NOT NULL AND CreatedDate != '' AND TRY_CONVERT(DATE, CreatedDate) IS NULL

        -- EffectiveDate optional, must be valid date
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'ServiceType', ServiceTypeID, 'EffectiveDate',
            CONCAT('"', EffectiveDate, '" is not a valid date. EffectiveDate is optional but must be a valid date if provided.')
        FROM ServiceType WHERE EffectiveDate IS NOT NULL AND EffectiveDate != '' AND TRY_CONVERT(DATE, EffectiveDate) IS NULL

    END
END
GO

/* ====================================================================================
   SERVICE
   ================================================================================== */
IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'Service')
BEGIN
    IF EXISTS (SELECT 1 FROM Service)
    BEGIN
        PRINT 'Starting Service'

        -- Duplicate ServiceID
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT 'Service', ServiceID, 'ServiceID',
            CONCAT('"', ServiceID, '" appears more than once. Each ServiceID must be unique.')
        FROM (SELECT ServiceID FROM Service GROUP BY ServiceID HAVING COUNT(*) > 1) X

        -- ServiceID blank
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Service', ServiceID, 'ServiceID',
            'ServiceID is blank. ServiceID is required.'
        FROM Service WHERE ServiceID IS NULL OR ServiceID = ''

        -- ServiceTypeID required and must be valid
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Service', ServiceID, 'ServiceTypeID',
            CONCAT('"', ISNULL(ServiceTypeID,'(blank)'), '" is invalid. ServiceTypeID is required and must match a value from the ServiceType sheet or the destination database.')
        FROM Service
        WHERE ServiceTypeID IS NULL
           OR ((ServiceTypeID NOT IN (SELECT CONVERT(VARCHAR, ServiceTypeID) FROM REPLACEME_ETL.dbo.ServiceType))
               AND (ServiceTypeID NOT IN (SELECT ServiceTypeID FROM REPLACEME_Staging.dbo.ServiceType)))

        -- ProvidedToEntityID required and must be a valid ClientID
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Service', ServiceID, 'ProvidedToEntityID',
            CONCAT('"', ProvidedToEntityID, '" is invalid. ProvidedToEntityID is required and must match a ClientID from the Client sheet.')
        FROM Service WHERE ProvidedToEntityID NOT IN (SELECT ClientID FROM Client)

        -- ProvidedByEntityID must be valid User or Provider
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Service', ServiceID, 'ProvidedByEntityID',
            CONCAT('"', ISNULL(ProvidedByEntityID,'(blank)'), '" is invalid. ProvidedByEntityID must be a UserID or ProviderID from the staging sheets or the destination database.')
        FROM Service
        WHERE ProvidedByEntityID IS NOT NULL AND ProvidedByEntityID != ''
          AND (TRY_CONVERT(FLOAT, ProvidedByEntityID) NOT IN (SELECT CONVERT(FLOAT, EntityID) FROM REPLACEME_ETL.dbo.[Provider])
               AND TRY_CONVERT(FLOAT, ProvidedByEntityID) NOT IN (SELECT CONVERT(FLOAT, EntityID) FROM REPLACEME_ETL.dbo.Users)
               AND ProvidedByEntityID NOT IN (SELECT ProviderID FROM REPLACEME_Staging.dbo.[Provider])
               AND ProvidedByEntityID NOT IN (SELECT UserID FROM REPLACEME_Staging.dbo.Users))

        -- EnrollmentID required and must be valid
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Service', ServiceID, 'EnrollmentID',
            CONCAT('"', TRY_CONVERT(NVARCHAR, EnrollmentID), '" is invalid. EnrollmentID is required and must match a value from the Enrollment sheet.')
        FROM Service
        WHERE TRY_CONVERT(FLOAT, EnrollmentID) NOT IN (SELECT TRY_CONVERT(FLOAT, EnrollmentID) FROM Enrollment)
          AND Service.EnrollmentID NOT IN (SELECT EnrollmentID FROM REPLACEME_Staging.dbo.Enrollment)

        -- CreatedBy required and must be valid user
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Service', ServiceID, 'CreatedBy',
            CONCAT('"', ISNULL(CreatedBy,'(blank)'), '" is invalid. CreatedBy is required and must be a UserID from the Users sheet or a User EntityID from the destination database.')
        FROM Service
        WHERE CreatedBy IS NULL OR CreatedBy = ''
           OR (TRY_CONVERT(FLOAT, CreatedBy) NOT IN (SELECT CONVERT(FLOAT, EntityID) FROM REPLACEME_ETL.dbo.Users)
               AND CreatedBy NOT IN (SELECT UserID FROM REPLACEME_Staging.dbo.Users))

        -- UnitOfMeasure from List 2
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Service', ServiceID, 'UnitOfMeasure',
            CONCAT('"', ISNULL(UnitOfMeasure,'(blank)'), '" is invalid. UnitOfMeasure is required and must be a value from ListID 2.')
        FROM Service
        WHERE TRY_CONVERT(FLOAT, UnitOfMeasure) IS NULL
           OR UnitOfMeasure IS NULL
           OR (TRY_CONVERT(FLOAT, UnitOfMeasure) IS NOT NULL
               AND UnitOfMeasure NOT IN (SELECT ListValue FROM REPLACEME_ETL.dbo.ListItem WHERE ListID = 2))

        -- UnitValue required, must be numeric
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Service', ServiceID, 'UnitValue',
            CONCAT('"', UnitValue, '" is invalid. UnitValue is required and must be a decimal number.')
        FROM Service WHERE TRY_CONVERT(FLOAT, UnitValue) IS NULL AND UnitValue IS NOT NULL

        -- Units required, must be numeric
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Service', ServiceID, 'Units',
            CONCAT('"', Units, '" is invalid. Units is required and must be a decimal number.')
        FROM Service WHERE TRY_CONVERT(FLOAT, Units) IS NULL AND Units IS NOT NULL

        -- OwnedByOrgID must be valid
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Service', ServiceID, 'OwnedByOrgID',
            CONCAT('"', OwnedByOrgID, '" is invalid. OwnedByOrgID must match a value from the Organization sheet or the destination database.')
        FROM Service
        WHERE OwnedByOrgID IS NOT NULL AND OwnedByOrgID != ''
          AND (TRY_CONVERT(BIGINT, OwnedByOrgID) IS NULL
               OR (OwnedByOrgID NOT IN (SELECT CONVERT(NVARCHAR, EntityID) FROM REPLACEME_ETL.dbo.Organization)
                   AND OwnedByOrgID NOT IN (SELECT CONVERT(NVARCHAR, OrganizationID) FROM Organization))
              )

        -- BeginDate required and valid
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Service', ServiceID, 'BeginDate',
            CONCAT('"', BeginDate, '" is not a valid date. BeginDate is required.')
        FROM Service WHERE TRY_CONVERT(DATE, BeginDate) IS NULL

        -- EndDate optional, must be valid date
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Service', ServiceID, 'EndDate',
            CONCAT('"', EndDate, '" is not a valid date. EndDate is optional but must be a valid date if provided.')
        FROM Service WHERE EndDate IS NOT NULL AND EndDate != '' AND TRY_CONVERT(DATE, EndDate) IS NULL

        -- Restriction from List 25
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Service', ServiceID, 'Restriction',
            CONCAT('"', Restriction, '" is invalid. Restriction must be a value from ListID 25 (1=Shared, 2=Not Shared).')
        FROM Service
        WHERE Restriction IS NOT NULL AND Restriction != ''
          AND (TRY_CONVERT(FLOAT, Restriction) IS NULL
               OR Restriction NOT IN (SELECT ListValue FROM REPLACEME_ETL.dbo.ListItem WHERE ListID = 25))

    END
END
GO

/* ====================================================================================
   ISSUE
   ================================================================================== */
IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'Issue')
BEGIN
    IF EXISTS (SELECT 1 FROM Issue)
    BEGIN
        PRINT 'Starting Issue'

        -- Duplicate IssueID
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Issue', IssueID, 'IssueID',
            CONCAT('"', IssueID, '" appears more than once. Each IssueID must be unique.')
        FROM Issue WHERE IssueID IN (SELECT IssueID FROM Issue GROUP BY IssueID HAVING COUNT(*) > 1)

        -- IssueID blank
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Issue', IssueID, 'IssueID',
            'IssueID is blank. IssueID is required.'
        FROM Issue WHERE IssueID IS NULL OR IssueID = ''

        -- ClientID required and must be valid
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Issue', IssueID, 'ClientID',
            CONCAT('"', ISNULL(ClientID,'(blank)'), '" is invalid. ClientID is required and must match a ClientID from the Client sheet.')
        FROM Issue WHERE ClientID IS NULL OR ClientID NOT IN (SELECT ClientID FROM Client)

        -- IssueTypeID required and must be valid
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Issue', IssueID, 'IssueTypeID',
            CONCAT('"', ISNULL(IssueTypeID,'(blank)'), '" is invalid. IssueTypeID is required and must be a valid value from the IssueType table in the destination database.')
        FROM Issue
        WHERE TRY_CONVERT(FLOAT, IssueTypeID) IS NULL
           OR IssueTypeID IS NULL
           OR (TRY_CONVERT(FLOAT, IssueTypeID) IS NOT NULL
               AND IssueTypeID NOT IN (SELECT IssueTypeID FROM REPLACEME_ETL.dbo.IssueType))

        -- IdentifiedDate optional, must be valid date
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Issue', IssueID, 'IdentifiedDate',
            CONCAT('"', IdentifiedDate, '" is not a valid date. IdentifiedDate is optional but must be a valid date if provided.')
        FROM Issue WHERE IdentifiedDate IS NOT NULL AND TRY_CONVERT(DATE, IdentifiedDate) IS NULL

        -- IsChronic from List 37
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Issue', IssueID, 'IsChronic',
            CONCAT('"', IsChronic, '" is invalid. IsChronic must be a value from ListID 37 (1=Yes, 2=No, etc.).')
        FROM Issue
        WHERE IsChronic IS NOT NULL AND IsChronic != ''
          AND (TRY_CONVERT(FLOAT, IsChronic) IS NULL
               OR IsChronic NOT IN (SELECT ListValue FROM REPLACEME_ETL.dbo.ListItem WHERE ListID = 37))

        -- IsInTreatment from List 37
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Issue', IssueID, 'IsInTreatment',
            CONCAT('"', IsInTreatment, '" is invalid. IsInTreatment must be a value from ListID 37 (1=Yes, 2=No, etc.).')
        FROM Issue
        WHERE IsInTreatment IS NOT NULL AND IsInTreatment != ''
          AND (TRY_CONVERT(FLOAT, IsInTreatment) IS NULL
               OR IsInTreatment NOT IN (SELECT ListValue FROM REPLACEME_ETL.dbo.ListItem WHERE ListID = 37))

        -- EvalLevel from List 432
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Issue', IssueID, 'EvalLevel',
            CONCAT('"', EvalLevel, '" is invalid. EvalLevel must be a value from ListID 432.')
        FROM Issue
        WHERE EvalLevel IS NOT NULL AND EvalLevel != ''
          AND (TRY_CONVERT(FLOAT, EvalLevel) IS NULL
               OR EvalLevel NOT IN (SELECT ListValue FROM REPLACEME_ETL.dbo.ListItem WHERE ListID = 432))

        -- OwnedByOrgID must be valid (optional)
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Issue', IssueID, 'OwnedByOrgID',
            CONCAT('"', OwnedByOrgID, '" is invalid. OwnedByOrgID must match a value from the Organization sheet or the destination database.')
        FROM Issue
        WHERE OwnedByOrgID IS NOT NULL AND OwnedByOrgID != ''
          AND OwnedByOrgID NOT IN (SELECT OrganizationID FROM Organization)
          AND OwnedByOrgID NOT IN (SELECT CONVERT(VARCHAR, EntityID) FROM REPLACEME_ETL.dbo.Organization)

        -- CreatedDate optional, valid date
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Issue', IssueID, 'CreatedDate',
            CONCAT('"', CreatedDate, '" is not a valid date. CreatedDate is optional but must be a valid date if provided.')
        FROM Issue WHERE CreatedDate IS NOT NULL AND TRY_CONVERT(DATE, CreatedDate) IS NULL

        -- EndDate optional, valid date
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Issue', IssueID, 'EndDate',
            CONCAT('"', EndDate, '" is not a valid date. EndDate is optional but must be a valid date if provided.')
        FROM Issue WHERE EndDate IS NOT NULL AND TRY_CONVERT(DATE, EndDate) IS NULL

        -- Restriction from List 25
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Issue', IssueID, 'Restriction',
            CONCAT('"', Restriction, '" is invalid. Restriction must be a value from ListID 25 (1=Shared, 2=Not Shared).')
        FROM Issue
        WHERE Restriction IS NOT NULL AND Restriction != ''
          AND (TRY_CONVERT(FLOAT, Restriction) IS NULL
               OR Restriction NOT IN (SELECT ListValue FROM REPLACEME_ETL.dbo.ListItem WHERE ListID = 25))

    END
END
GO

/* ====================================================================================
   GOAL
   ================================================================================== */
IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'Goal')
BEGIN
    IF EXISTS (SELECT 1 FROM Goal)
    BEGIN
        PRINT 'Starting Goal'

        -- Duplicate GoalID
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Goal', GoalID, 'GoalID',
            CONCAT('"', GoalID, '" appears more than once. Each GoalID must be unique.')
        FROM Goal WHERE GoalID IN (SELECT GoalID FROM Goal GROUP BY GoalID HAVING COUNT(*) > 1)

        -- GoalID blank
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Goal', GoalID, 'GoalID',
            'GoalID is blank. GoalID is required.'
        FROM Goal WHERE GoalID IS NULL OR GoalID = ''

        -- ClientID required and must be valid
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Goal', GoalID, 'ClientID',
            CONCAT('"', ISNULL(ClientID,'(blank)'), '" is invalid. ClientID is required and must match a ClientID from the Client sheet.')
        FROM Goal WHERE ClientID IS NULL OR ClientID NOT IN (SELECT ClientID FROM Client)

        -- GoalTypeID required and must be valid
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Goal', GoalID, 'GoalTypeID',
            CONCAT('"', ISNULL(GoalTypeID,'(blank)'), '" is invalid. GoalTypeID is required and must be a valid value from the GoalType table in the destination database.')
        FROM Goal
        WHERE TRY_CONVERT(FLOAT, GoalTypeID) IS NULL
           OR GoalTypeID IS NULL
           OR (TRY_CONVERT(FLOAT, GoalTypeID) IS NOT NULL
               AND GoalTypeID NOT IN (SELECT CONVERT(VARCHAR, GoalTypeID) FROM REPLACEME_ETL.dbo.GoalType))

        -- EnrollmentServicePlanID optional, must be valid if provided
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Goal', GoalID, 'EnrollmentServicePlanID',
            CONCAT('"', EnrollmentServicePlanID, '" is invalid. EnrollmentServicePlanID must match a value from the EnrollmentServicePlan sheet if provided.')
        FROM Goal
        WHERE EnrollmentServicePlanID IS NOT NULL AND EnrollmentServicePlanID != ''
          AND EnrollmentServicePlanID NOT IN (SELECT EnrollmentServicePlanID FROM EnrollmentServicePlan WHERE EnrollmentServicePlanID IS NOT NULL)

        -- PlanAttainDate optional, valid date
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Goal', GoalID, 'PlanAttainDate',
            CONCAT('"', PlanAttainDate, '" is not a valid date. PlanAttainDate is optional but must be a valid date if provided.')
        FROM Goal WHERE PlanAttainDate IS NOT NULL AND TRY_CONVERT(DATE, PlanAttainDate) IS NULL

        -- ActualAttainDate optional, valid date
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Goal', GoalID, 'ActualAttainDate',
            CONCAT('"', ActualAttainDate, '" is not a valid date. ActualAttainDate is optional but must be a valid date if provided.')
        FROM Goal WHERE ActualAttainDate IS NOT NULL AND TRY_CONVERT(DATE, ActualAttainDate) IS NULL

        -- SetDate optional, valid date
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Goal', GoalID, 'SetDate',
            CONCAT('"', SetDate, '" is not a valid date. SetDate is optional but must be a valid date if provided.')
        FROM Goal WHERE SetDate IS NOT NULL AND TRY_CONVERT(DATE, SetDate) IS NULL

        -- CreatedDate optional, valid date
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Goal', GoalID, 'CreatedDate',
            CONCAT('"', CreatedDate, '" is not a valid date. CreatedDate is optional but must be a valid date if provided.')
        FROM Goal WHERE CreatedDate IS NOT NULL AND TRY_CONVERT(DATE, CreatedDate) IS NULL

        -- ResponsibleParty from List 415
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Goal', GoalID, 'ResponsibleParty',
            CONCAT('"', ResponsibleParty, '" is invalid. ResponsibleParty must be a value from ListID 415 (1=Client, 5=Staff, 10=Both).')
        FROM Goal
        WHERE ResponsibleParty IS NOT NULL AND ResponsibleParty != ''
          AND (TRY_CONVERT(FLOAT, ResponsibleParty) IS NULL
               OR ResponsibleParty NOT IN (SELECT ListValue FROM REPLACEME_ETL.dbo.ListItem WHERE ListID = 415))

    END
END
GO

/* ====================================================================================
   CREDENTIAL
   ================================================================================== */
IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'Credential')
BEGIN
    IF EXISTS (SELECT 1 FROM Credential)
    BEGIN
        PRINT 'Starting Credential'

        -- Duplicate CredentialID
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Credential', CredentialID, 'CredentialID',
            CONCAT('"', CredentialID, '" appears more than once. Each CredentialID must be unique.')
        FROM Credential WHERE CredentialID IN (SELECT CredentialID FROM Credential GROUP BY CredentialID HAVING COUNT(*) > 1)

        -- CredentialID blank
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Credential', CredentialID, 'CredentialID',
            'CredentialID is blank. CredentialID is required.'
        FROM Credential WHERE CredentialID IS NULL OR CredentialID = ''

        -- ClientID required and valid
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Credential', CredentialID, 'ClientID',
            CONCAT('"', ISNULL(ClientID,'(blank)'), '" is invalid. ClientID is required and must match a ClientID from the Client sheet.')
        FROM Credential WHERE ClientID IS NULL OR ClientID NOT IN (SELECT ClientID FROM Client)

        -- CredentialTypeID required
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Credential', CredentialID, 'CredentialTypeID',
            CONCAT('"', ISNULL(CredentialTypeID,'(blank)'), '" is invalid. CredentialTypeID is required and must be a valid value from the CredentialType table in the destination database.')
        FROM Credential
        WHERE CredentialTypeID IS NULL OR TRY_CONVERT(FLOAT, CredentialTypeID) IS NULL

        -- SkillTypeID required
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Credential', CredentialID, 'SkillTypeID',
            CONCAT('"', ISNULL(SkillTypeID,'(blank)'), '" is invalid. SkillTypeID is required and must be a valid value from the SkillType table in the destination database.')
        FROM Credential
        WHERE SkillTypeID IS NULL OR TRY_CONVERT(FLOAT, SkillTypeID) IS NULL

        -- IssuedDate optional, valid date
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Credential', CredentialID, 'IssuedDate',
            CONCAT('"', IssuedDate, '" is not a valid date. IssuedDate is optional but must be a valid date if provided.')
        FROM Credential WHERE IssuedDate IS NOT NULL AND IssuedDate != '' AND TRY_CONVERT(DATE, IssuedDate) IS NULL

        -- Restriction from List 25
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Credential', CredentialID, 'Restriction',
            CONCAT('"', Restriction, '" is invalid. Restriction must be a value from ListID 25 (1=Shared, 2=Not Shared).')
        FROM Credential
        WHERE Restriction IS NOT NULL AND Restriction != ''
          AND (TRY_CONVERT(FLOAT, Restriction) IS NULL
               OR Restriction NOT IN (SELECT ListValue FROM REPLACEME_ETL.dbo.ListItem WHERE ListID = 25))

    END
END
GO

/* ====================================================================================
   PROVIDER REFERRAL
   ================================================================================== */
IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'ProviderReferral')
BEGIN
    IF EXISTS (SELECT 1 FROM ProviderReferral)
    BEGIN
        PRINT 'Starting ProviderReferral'

        -- Duplicate ProviderReferralID
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'ProviderReferral', ProviderReferralID, 'ProviderReferralID',
            CONCAT('"', ProviderReferralID, '" appears more than once. Each ProviderReferralID must be unique.')
        FROM ProviderReferral WHERE ProviderReferralID IN (SELECT ProviderReferralID FROM ProviderReferral GROUP BY ProviderReferralID HAVING COUNT(*) > 1)

        -- ProviderReferralID blank
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'ProviderReferral', ProviderReferralID, 'ProviderReferralID',
            'ProviderReferralID is blank. ProviderReferralID is required.'
        FROM ProviderReferral WHERE ProviderReferralID IS NULL OR ProviderReferralID = ''

        -- ReferFromProviderID required and valid
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'ProviderReferral', ProviderReferralID, 'ReferFromProviderID',
            CONCAT('"', ISNULL(ReferFromProviderID,'(blank)'), '" is invalid. ReferFromProviderID is required and must match a value in the Provider sheet or the destination database.')
        FROM ProviderReferral
        WHERE TRY_CONVERT(FLOAT, ReferFromProviderID) IS NULL OR ReferFromProviderID IS NULL
           OR (TRY_CONVERT(FLOAT, ReferFromProviderID) IS NOT NULL
               AND ReferFromProviderID NOT IN (SELECT ProviderID FROM [Provider])
               AND ReferFromProviderID NOT IN (SELECT CONVERT(VARCHAR, EntityID) FROM REPLACEME_ETL.dbo.[Provider]))

        -- ReferToProviderID required and valid
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'ProviderReferral', ProviderReferralID, 'ReferToProviderID',
            CONCAT('"', ISNULL(ReferToProviderID,'(blank)'), '" is invalid. ReferToProviderID is required and must match a value in the Provider sheet or the destination database.')
        FROM ProviderReferral
        WHERE TRY_CONVERT(FLOAT, ReferToProviderID) IS NULL OR ReferToProviderID IS NULL
           OR (TRY_CONVERT(FLOAT, ReferToProviderID) IS NOT NULL
               AND ReferToProviderID NOT IN (SELECT ProviderID FROM [Provider])
               AND ReferToProviderID NOT IN (SELECT CONVERT(VARCHAR, EntityID) FROM REPLACEME_ETL.dbo.[Provider]))

        -- ClientID required and valid
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'ProviderReferral', ProviderReferralID, 'ClientID',
            CONCAT('"', ISNULL(ClientID,'(blank)'), '" is invalid. ClientID is required and must match a ClientID from the Client sheet.')
        FROM ProviderReferral WHERE ClientID IS NULL OR ClientID NOT IN (SELECT ClientID FROM Client WHERE ClientID IS NOT NULL)

        -- ServiceTypeID required and valid
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'ProviderReferral', ProviderReferralID, 'ServiceTypeID',
            CONCAT('"', ISNULL(ServiceTypeID,'(blank)'), '" is invalid. ServiceTypeID is required and must match a value from the ServiceType sheet or the destination database.')
        FROM ProviderReferral
        WHERE TRY_CONVERT(FLOAT, ServiceTypeID) IS NULL OR ServiceTypeID IS NULL
           OR (TRY_CONVERT(FLOAT, ServiceTypeID) IS NOT NULL
               AND ServiceTypeID NOT IN (SELECT CONVERT(VARCHAR, ServiceTypeID) FROM REPLACEME_ETL.dbo.ServiceType))

        -- ReferralDate required and valid date
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'ProviderReferral', ProviderReferralID, 'ReferralDate',
            CONCAT('"', ISNULL(ReferralDate,'(blank)'), '" is not a valid date. ReferralDate is required.')
        FROM ProviderReferral WHERE ReferralDate IS NULL OR TRY_CONVERT(DATE, ReferralDate) IS NULL

        -- ReferralStatus from List 132
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'ProviderReferral', ProviderReferralID, 'ReferralStatus',
            CONCAT('"', ISNULL(ReferralStatus,'(blank)'), '" is invalid. ReferralStatus is required and must be a value from ListID 132.')
        FROM ProviderReferral
        WHERE TRY_CONVERT(FLOAT, ReferralStatus) IS NULL OR ReferralStatus IS NULL
           OR (TRY_CONVERT(FLOAT, ReferralStatus) IS NOT NULL
               AND ReferralStatus NOT IN (SELECT ListValue FROM REPLACEME_ETL.dbo.ListItem WHERE ListID = 132))

        -- ReferToUserID optional, must be valid if provided
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'ProviderReferral', ProviderReferralID, 'ReferToUserID',
            CONCAT('"', ReferToUserID, '" is invalid. ReferToUserID must match a UserID from the Users sheet or the destination database if provided.')
        FROM ProviderReferral
        WHERE ReferToUserID IS NOT NULL AND LEN(ReferToUserID) > 0
          AND ((TRY_CONVERT(FLOAT, ReferToUserID) IS NOT NULL
                AND ReferToUserID NOT IN (SELECT UserID FROM Users)
                AND ReferToUserID NOT IN (SELECT CONVERT(VARCHAR, EntityID) FROM REPLACEME_ETL.dbo.Users))
               OR TRY_CONVERT(FLOAT, ReferToUserID) IS NULL)

        -- Outcome from List 2943
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'ProviderReferral', ProviderReferralID, 'Outcome',
            CONCAT('"', Outcome, '" is invalid. Outcome must be a value from ListID 2943 (1=Attained, 2=Not Attained, 3=Unknown).')
        FROM ProviderReferral
        WHERE Outcome IS NOT NULL AND Outcome != ''
          AND (TRY_CONVERT(FLOAT, Outcome) IS NULL
               OR Outcome NOT IN (SELECT ListValue FROM REPLACEME_ETL.dbo.ListItem WHERE ListID = 2943))

        -- EnrollmentID optional, must be valid if provided
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'ProviderReferral', ProviderReferralID, 'EnrollmentID',
            CONCAT('"', EnrollmentID, '" is invalid. EnrollmentID must match a value from the Enrollment sheet if provided.')
        FROM ProviderReferral
        WHERE EnrollmentID IS NOT NULL AND LEN(EnrollmentID) > 0
          AND ((TRY_CONVERT(FLOAT, EnrollmentID) IS NOT NULL
                AND EnrollmentID NOT IN (SELECT EnrollmentID FROM Enrollment WHERE EnrollmentID IS NOT NULL))
               OR TRY_CONVERT(FLOAT, EnrollmentID) IS NULL)

        -- CreatedDate optional, valid date
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'ProviderReferral', ProviderReferralID, 'CreatedDate',
            CONCAT('"', CreatedDate, '" is not a valid date. CreatedDate is optional but must be a valid date if provided.')
        FROM ProviderReferral WHERE CreatedDate IS NOT NULL AND CreatedDate != '' AND TRY_CONVERT(DATE, CreatedDate) IS NULL

    END
END
GO

/* ====================================================================================
   FILE DOCUMENT
   ================================================================================== */
IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'FileDocument')
BEGIN
    IF EXISTS (SELECT 1 FROM FileDocument)
    BEGIN
        PRINT 'Starting FileDocument'

        -- Duplicate FileDocumentID
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'FileDocument', FileDocumentID, 'FileDocumentID',
            CONCAT('"', FileDocumentID, '" appears more than once. Each FileDocumentID must be unique.')
        FROM FileDocument WHERE FileDocumentID IN (SELECT FileDocumentID FROM FileDocument GROUP BY FileDocumentID HAVING COUNT(*) > 1)

        -- FileDocumentID blank
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'FileDocument', FileDocumentID, 'FileDocumentID',
            'FileDocumentID is blank. FileDocumentID is required.'
        FROM FileDocument WHERE FileDocumentID IS NULL OR FileDocumentID = ''

        -- FileName required
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'FileDocument', FileDocumentID, 'FileName',
            'FileName is blank. FileName is required and must exactly match the file name uploaded to the FTP.'
        FROM FileDocument WHERE FileName IS NULL OR FileName = ''

        -- FileName max 100 chars
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'FileDocument', FileDocumentID, 'FileName',
            CONCAT('"', FileName, '" is too long. FileName cannot exceed 100 characters.')
        FROM FileDocument WHERE LEN(FileName) > 100

        -- ClientID required and valid
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'FileDocument', FileDocumentID, 'ClientID',
            CONCAT('"', ISNULL(ClientID,'(blank)'), '" is invalid. ClientID is required and must match a ClientID from the Client sheet.')
        FROM FileDocument WHERE ClientID IS NULL OR ClientID NOT IN (SELECT ClientID FROM Client WHERE ClientID IS NOT NULL)

        -- DocumentTypeID required
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'FileDocument', FileDocumentID, 'DocumentTypeID',
            CONCAT('"', ISNULL(DocumentTypeID,'(blank)'), '" is invalid. DocumentTypeID is required. Use a value from the LookUpValue tab where StagingTable = FileDocument.')
        FROM FileDocument WHERE DocumentTypeID IS NULL OR DocumentTypeID = ''

        -- FileClassification from List 84
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'FileDocument', FileDocumentID, 'FileClassification',
            CONCAT('"', FileClassification, '" is invalid. FileClassification must be a value from ListID 84 (0=None, 2=Client Photo, 3=Scanned Document, 4=Other File).')
        FROM FileDocument
        WHERE FileClassification IS NOT NULL AND FileClassification != ''
          AND (TRY_CONVERT(FLOAT, FileClassification) IS NULL
               OR FileClassification NOT IN (SELECT ListValue FROM REPLACEME_ETL.dbo.ListItem WHERE ListID = 84))

        -- VerificationMethodID from List 81
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'FileDocument', FileDocumentID, 'VerificationMethodID',
            CONCAT('"', VerificationMethodID, '" is invalid. VerificationMethodID must be a value from ListID 81.')
        FROM FileDocument
        WHERE VerificationMethodID IS NOT NULL AND VerificationMethodID != ''
          AND (TRY_CONVERT(FLOAT, VerificationMethodID) IS NULL
               OR VerificationMethodID NOT IN (SELECT ListValue FROM REPLACEME_ETL.dbo.ListItem WHERE ListID = 81))

        -- StorageMethodID from List 82
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'FileDocument', FileDocumentID, 'StorageMethodID',
            CONCAT('"', StorageMethodID, '" is invalid. StorageMethodID must be a value from ListID 82 (1=Paper File, 2=Electronic File).')
        FROM FileDocument
        WHERE StorageMethodID IS NOT NULL AND StorageMethodID != ''
          AND (TRY_CONVERT(FLOAT, StorageMethodID) IS NULL
               OR StorageMethodID NOT IN (SELECT ListValue FROM REPLACEME_ETL.dbo.ListItem WHERE ListID = 82))

        -- CreatedDate optional, valid date
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'FileDocument', FileDocumentID, 'CreatedDate',
            CONCAT('"', CreatedDate, '" is not a valid date. CreatedDate is optional but must be a valid date if provided.')
        FROM FileDocument WHERE CreatedDate IS NOT NULL AND CreatedDate != '' AND TRY_CONVERT(DATE, CreatedDate) IS NULL

        -- IssueDate optional, valid date
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'FileDocument', FileDocumentID, 'IssueDate',
            CONCAT('"', IssueDate, '" is not a valid date. IssueDate is optional but must be a valid date if provided.')
        FROM FileDocument WHERE IssueDate IS NOT NULL AND IssueDate != '' AND TRY_CONVERT(DATE, IssueDate) IS NULL

        -- ExpiresDate optional, valid date
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'FileDocument', FileDocumentID, 'ExpiresDate',
            CONCAT('"', ExpiresDate, '" is not a valid date. ExpiresDate is optional but must be a valid date if provided.')
        FROM FileDocument WHERE ExpiresDate IS NOT NULL AND ExpiresDate != '' AND TRY_CONVERT(DATE, ExpiresDate) IS NULL

    END
END
GO

/* ====================================================================================
   WORK HISTORY
   ================================================================================== */
IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'WorkHistory')
BEGIN
    IF EXISTS (SELECT 1 FROM WorkHistory)
    BEGIN
        PRINT 'Starting WorkHistory'

        -- Duplicate WorkHistoryID
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'WorkHistory', WorkHistoryID, 'WorkHistoryID',
            CONCAT('"', WorkHistoryID, '" appears more than once. Each WorkHistoryID must be unique.')
        FROM WorkHistory WHERE WorkHistoryID IN (SELECT WorkHistoryID FROM WorkHistory GROUP BY WorkHistoryID HAVING COUNT(*) > 1)

        -- WorkHistoryID blank
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'WorkHistory', WorkHistoryID, 'WorkHistoryID',
            'WorkHistoryID is blank. WorkHistoryID is required.'
        FROM WorkHistory WHERE WorkHistoryID IS NULL OR WorkHistoryID = ''

        -- ClientID required and valid
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'WorkHistory', WorkHistoryID, 'ClientID',
            CONCAT('"', ISNULL(ClientID,'(blank)'), '" is invalid. ClientID is required and must match a ClientID from the Client sheet.')
        FROM WorkHistory WHERE ClientID IS NULL OR ClientID NOT IN (SELECT ClientID FROM Client)

        -- ProviderID required and valid
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'WorkHistory', WorkHistoryID, 'ProviderID',
            CONCAT('"', ISNULL(ProviderID,'(blank)'), '" is invalid. ProviderID is required and must match a value from the Provider sheet or the destination database.')
        FROM WorkHistory
        WHERE ProviderID IS NULL
           OR (ProviderID NOT IN (SELECT ProviderID FROM [Provider])
               AND ProviderID NOT IN (SELECT CONVERT(VARCHAR, EntityID) FROM REPLACEME_ETL.dbo.[Provider]))

        -- EmploymentTypeID required from List 97
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'WorkHistory', WorkHistoryID, 'EmploymentTypeID',
            CONCAT('"', ISNULL(EmploymentTypeID,'(blank)'), '" is invalid. EmploymentTypeID is required and must be a value from ListID 97.')
        FROM WorkHistory
        WHERE TRY_CONVERT(FLOAT, EmploymentTypeID) IS NULL OR EmploymentTypeID IS NULL
           OR (TRY_CONVERT(FLOAT, EmploymentTypeID) IS NOT NULL
               AND EmploymentTypeID NOT IN (SELECT ListValue FROM REPLACEME_ETL.dbo.ListItem WHERE ListID = 97))

        -- BeginDate required and valid
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'WorkHistory', WorkHistoryID, 'BeginDate',
            CONCAT('"', ISNULL(BeginDate,'(blank)'), '" is not a valid date. BeginDate is required.')
        FROM WorkHistory WHERE BeginDate IS NULL OR TRY_CONVERT(DATE, BeginDate) IS NULL

        -- EndDate optional, valid date
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'WorkHistory', WorkHistoryID, 'EndDate',
            CONCAT('"', EndDate, '" is not a valid date. EndDate is optional but must be a valid date if provided.')
        FROM WorkHistory WHERE EndDate IS NOT NULL AND EndDate != '' AND TRY_CONVERT(DATE, EndDate) IS NULL

        -- PaymentTypeID from List 107
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'WorkHistory', WorkHistoryID, 'PaymentTypeID',
            CONCAT('"', PaymentTypeID, '" is invalid. PaymentTypeID must be a value from ListID 107.')
        FROM WorkHistory
        WHERE PaymentTypeID IS NOT NULL AND PaymentTypeID != ''
          AND (TRY_CONVERT(FLOAT, PaymentTypeID) IS NULL
               OR PaymentTypeID NOT IN (SELECT ListValue FROM REPLACEME_ETL.dbo.ListItem WHERE ListID = 107))

        -- PaymentIntervalID from List 2973
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'WorkHistory', WorkHistoryID, 'PaymentIntervalID',
            CONCAT('"', PaymentIntervalID, '" is invalid. PaymentIntervalID must be a value from ListID 2973.')
        FROM WorkHistory
        WHERE PaymentIntervalID IS NOT NULL AND PaymentIntervalID != ''
          AND (TRY_CONVERT(FLOAT, PaymentIntervalID) IS NULL
               OR PaymentIntervalID NOT IN (SELECT ListValue FROM REPLACEME_ETL.dbo.ListItem WHERE ListID = 2973))

        -- ExitReasonID from List 109
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'WorkHistory', WorkHistoryID, 'ExitReasonID',
            CONCAT('"', ExitReasonID, '" is invalid. ExitReasonID must be a value from ListID 109.')
        FROM WorkHistory
        WHERE ExitReasonID IS NOT NULL AND ExitReasonID != ''
          AND (TRY_CONVERT(FLOAT, ExitReasonID) IS NULL
               OR ExitReasonID NOT IN (SELECT ListValue FROM REPLACEME_ETL.dbo.ListItem WHERE ListID = 109))

        -- TerminationReasonID from List 108
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'WorkHistory', WorkHistoryID, 'TerminationReasonID',
            CONCAT('"', TerminationReasonID, '" is invalid. TerminationReasonID must be a value from ListID 108.')
        FROM WorkHistory
        WHERE TerminationReasonID IS NOT NULL AND TerminationReasonID != ''
          AND (TRY_CONVERT(FLOAT, TerminationReasonID) IS NULL
               OR TerminationReasonID NOT IN (SELECT ListValue FROM REPLACEME_ETL.dbo.ListItem WHERE ListID = 108))

        -- EndPaymentRate optional, must be numeric
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'WorkHistory', WorkHistoryID, 'EndPaymentRate',
            CONCAT('"', EndPaymentRate, '" is invalid. EndPaymentRate must be a decimal number.')
        FROM WorkHistory WHERE EndPaymentRate IS NOT NULL AND TRY_CONVERT(FLOAT, EndPaymentRate) IS NULL

        -- HealthBenefits must be 0 or 1
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'WorkHistory', WorkHistoryID, 'HealthBenefits',
            CONCAT('"', HealthBenefits, '" is invalid. HealthBenefits must be 1 (Yes) or 0 (No).')
        FROM WorkHistory
        WHERE HealthBenefits IS NOT NULL AND HealthBenefits != ''
          AND (TRY_CONVERT(FLOAT, HealthBenefits) IS NULL OR HealthBenefits NOT IN ('0','1'))

        -- WorkerPaysBenefits must be 0 or 1
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'WorkHistory', WorkHistoryID, 'WorkerPaysBenefits',
            CONCAT('"', WorkerPaysBenefits, '" is invalid. WorkerPaysBenefits must be 1 (Yes) or 0 (No).')
        FROM WorkHistory
        WHERE WorkerPaysBenefits IS NOT NULL AND WorkerPaysBenefits != ''
          AND (TRY_CONVERT(FLOAT, WorkerPaysBenefits) IS NULL OR WorkerPaysBenefits NOT IN ('0','1'))

    END
END
GO

/* ====================================================================================
   ASSESSMENT
   ================================================================================== */
IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'Assessment')
BEGIN
    IF EXISTS (SELECT 1 FROM Assessment)
    BEGIN
        PRINT 'Starting Assessment'

        -- Duplicate AssessmentID
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Assessment', AssessmentID, 'AssessmentID',
            CONCAT('"', AssessmentID, '" appears more than once. Each AssessmentID must be unique.')
        FROM (SELECT AssessmentID FROM Assessment GROUP BY AssessmentID HAVING COUNT(*) > 1) X

        -- AssessmentID blank
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Assessment', AssessmentID, 'AssessmentID',
            'AssessmentID is blank. AssessmentID is required.'
        FROM Assessment WHERE AssessmentID IS NULL OR AssessmentID = ''

        -- ClientID required and valid
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Assessment', A.AssessmentID, 'ClientID',
            CONCAT('"', A.ClientID, '" is invalid. ClientID must match a ClientID from the Client sheet.')
        FROM Assessment A
        LEFT JOIN Client CL ON CL.ClientID = A.ClientID
        WHERE CL.ClientID IS NULL

        -- EnrollmentID required and valid
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT 'Assessment', AssessmentID, 'EnrollmentID',
            CONCAT('"', A.EnrollmentID, '" is invalid. EnrollmentID is required and must match a value from the Enrollment sheet.')
        FROM Assessment A
        LEFT JOIN Enrollment E ON E.EnrollmentID = A.EnrollmentID
        WHERE E.EnrollmentID IS NULL OR A.EnrollmentID IS NULL

        -- ClientID + EnrollmentID must match (i.e., client is enrolled in that enrollment)
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT 'Assessment', AssessmentID, 'AssessmentID',
            'ClientID and EnrollmentID mismatch. The client is not enrolled in the referenced enrollment.'
        FROM Assessment
        LEFT JOIN Enrollment ON Enrollment.EnrollmentID = Assessment.EnrollmentID
                             AND Enrollment.ClientID = Assessment.ClientID
        WHERE Enrollment.EnrollmentID IS NULL OR Enrollment.ClientID IS NULL

        -- AssessmentBy required and valid
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Assessment', AssessmentID, 'AssessmentBy',
            CONCAT('"', ISNULL(AssessmentBy,'(blank)'), '" is invalid. AssessmentBy is required and must be a UserID from the Users sheet or a User EntityID from the destination database.')
        FROM Assessment
        WHERE AssessmentBy IS NULL OR AssessmentBy = ''
           OR (TRY_CONVERT(FLOAT, AssessmentBy) IS NULL)
           OR (TRY_CONVERT(FLOAT, AssessmentBy) IS NOT NULL
               AND AssessmentBy NOT IN (SELECT UserID FROM Users WHERE UserID IS NOT NULL)
               AND AssessmentBy NOT IN (SELECT CONVERT(VARCHAR, EntityID) FROM REPLACEME_ETL.dbo.Users))

        -- AssessmentEvent from List 27
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT 'Assessment', AssessmentID, 'AssessmentEvent',
            CONCAT('"', ISNULL(AssessmentEvent,'(blank)'), '" is invalid. AssessmentEvent is required and must be a value from ListID 27 (1=At Entry, 2=During, 3=At Exit, 5=Annual, 6=Post-Exit).')
        FROM Assessment A
        LEFT JOIN REPLACEME_ETL.dbo.ListItem L ON L.ListID = 27 AND CONVERT(VARCHAR, L.ListValue) = A.AssessmentEvent
        WHERE L.ListValue IS NULL

        -- BeginAssessment required and valid date
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Assessment', AssessmentID, 'BeginAssessment',
            CONCAT('"', ISNULL(BeginAssessment,'(blank)'), '" is not a valid date. BeginAssessment is required.')
        FROM Assessment WHERE BeginAssessment IS NULL OR TRY_CONVERT(DATE, BeginAssessment) IS NULL

        -- EndAssessment required and valid date
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Assessment', AssessmentID, 'EndAssessment',
            CONCAT('"', ISNULL(EndAssessment,'(blank)'), '" is not a valid date. EndAssessment is required.')
        FROM Assessment WHERE EndAssessment IS NULL OR TRY_CONVERT(DATE, EndAssessment) IS NULL

        -- CreatedBy required and valid
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Assessment', AssessmentID, 'CreatedBy',
            CONCAT('"', ISNULL(CreatedBy,'(blank)'), '" is invalid. CreatedBy is required and must be a UserID from the Users sheet or a User EntityID from the destination database.')
        FROM Assessment
        WHERE CreatedBy IS NULL OR CreatedBy = ''
           OR (TRY_CONVERT(FLOAT, CreatedBy) IS NULL)
           OR (TRY_CONVERT(FLOAT, CreatedBy) IS NOT NULL
               AND CreatedBy NOT IN (SELECT UserID FROM Users WHERE UserID IS NOT NULL)
               AND CreatedBy NOT IN (SELECT CONVERT(VARCHAR, EntityID) FROM REPLACEME_ETL.dbo.Users))

        -- OwnedByOrgID required and valid
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Assessment', AssessmentID, 'OwnedByOrgID',
            CONCAT('"', A.OwnedByOrgID, '" is invalid. OwnedByOrgID is required and must match a value from the Organization sheet or the destination database.')
        FROM Assessment A
        LEFT JOIN REPLACEME_ETL.dbo.Organization O ON CONVERT(VARCHAR, O.EntityID) = A.OwnedByOrgID
        LEFT JOIN Organization O2 ON O2.OrganizationID = A.OwnedByOrgID
        WHERE O2.OrganizationID IS NULL AND O.EntityID IS NULL

        -- Restriction from List 25
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Assessment', AssessmentID, 'Restriction',
            CONCAT('"', Restriction, '" is invalid. Restriction must be a value from ListID 25 (1=Shared, 2=Not Shared).')
        FROM Assessment
        WHERE Restriction IS NOT NULL AND Restriction != ''
          AND (TRY_CONVERT(FLOAT, Restriction) IS NULL
               OR Restriction NOT IN (SELECT ListValue FROM REPLACEME_ETL.dbo.ListItem WHERE ListID = 25))

        -- CreatedDate optional, valid date
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Assessment', AssessmentID, 'CreatedDate',
            CONCAT('"', CreatedDate, '" is not a valid date. CreatedDate is optional but must be a valid date if provided.')
        FROM Assessment WHERE CreatedDate IS NOT NULL AND CreatedDate != '' AND TRY_CONVERT(DATE, CreatedDate) IS NULL

    END
END
GO

/* ====================================================================================
   ASSESS FINANCIAL ITEM
   ================================================================================== */
IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'AssessFinancialItem')
BEGIN
    IF EXISTS (SELECT 1 FROM AssessFinancialItem)
    BEGIN
        PRINT 'Starting AssessFinancialItem'

        -- AssessmentID must be valid
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'AssessFinancialItem', AssessmentID, 'AssessmentID',
            CONCAT('"', AssessmentID, '" is invalid. AssessmentID must match an AssessmentID from the Assessment sheet.')
        FROM AssessFinancialItem WHERE AssessmentID NOT IN (SELECT AssessmentID FROM Assessment)

        -- AssessmentID blank
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'AssessFinancialItem', AssessmentID, 'AssessmentID',
            'AssessmentID is blank. AssessmentID is required.'
        FROM AssessFinancialItem WHERE AssessmentID IS NULL OR AssessmentID = ''

        -- IncomeBenefitType required: 0, 1, or 2
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'AssessFinancialItem', AssessmentID, 'IncomeBenefitType',
            CONCAT('"', ISNULL(IncomeBenefitType,'(blank)'), '" is invalid. IncomeBenefitType is required and must be 0 (Non-Cash Benefit), 1 (Cash Income Source), or 2 (Expense).')
        FROM AssessFinancialItem
        WHERE IncomeBenefitType IS NULL
           OR (TRY_CONVERT(FLOAT, IncomeBenefitType) IS NOT NULL
               AND IncomeBenefitType NOT IN ('0','1','2'))
           OR TRY_CONVERT(FLOAT, IncomeBenefitType) IS NULL

        -- FinancialItemTypeID required
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'AssessFinancialItem', AssessmentID, 'FinancialItemTypeID',
            CONCAT('"', ISNULL(FinancialItemTypeID,'(blank)'), '" is invalid. FinancialItemTypeID is required and must be a valid value from the FinancialType table in the destination database.')
        FROM AssessFinancialItem WHERE TRY_CONVERT(FLOAT, FinancialItemTypeID) IS NULL OR FinancialItemTypeID IS NULL

        -- Amount optional, must be numeric
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'AssessFinancialItem', AssessmentID, 'Amount',
            CONCAT('"', Amount, '" is invalid. Amount is optional but must be a number if provided.')
        FROM AssessFinancialItem WHERE Amount IS NOT NULL AND Amount != '' AND TRY_CONVERT(FLOAT, Amount) IS NULL

        -- CreatedBy required and valid
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'AssessFinancialItem', AssessmentID, 'CreatedBy',
            CONCAT('"', ISNULL(CreatedBy,'(blank)'), '" is invalid. CreatedBy is required and must be a UserID from the Users sheet or a User EntityID from the destination database.')
        FROM AssessFinancialItem
        WHERE CreatedBy IS NULL OR CreatedBy = ''
           OR (TRY_CONVERT(FLOAT, CreatedBy) IS NULL)
           OR (TRY_CONVERT(FLOAT, CreatedBy) IS NOT NULL
               AND CreatedBy NOT IN (SELECT UserID FROM Users WHERE UserID IS NOT NULL)
               AND CreatedBy NOT IN (SELECT CONVERT(VARCHAR, EntityID) FROM REPLACEME_ETL.dbo.Users))

    END
END
GO

/* ====================================================================================
   ASSESS EMPLOYMENT PLACEMENT
   ================================================================================== */
IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'AssessEmploymentPlacement')
BEGIN
    IF EXISTS (SELECT 1 FROM AssessEmploymentPlacement)
    BEGIN
        PRINT 'Starting AssessEmploymentPlacement'

        -- Duplicate AssessmentID
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'AssessEmploymentPlacement', AssessmentID, 'AssessmentID',
            CONCAT('"', AssessmentID, '" appears more than once. Each AssessmentID must be unique in this sheet.')
        FROM AssessEmploymentPlacement WHERE AssessmentID IN (SELECT AssessmentID FROM AssessEmploymentPlacement GROUP BY AssessmentID HAVING COUNT(*) > 1)

        -- AssessmentID must be valid
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'AssessEmploymentPlacement', AssessmentID, 'AssessmentID',
            CONCAT('"', AssessmentID, '" is invalid. AssessmentID must match an AssessmentID from the Assessment sheet.')
        FROM AssessEmploymentPlacement WHERE AssessmentID NOT IN (SELECT AssessmentID FROM Assessment WHERE AssessmentID IS NOT NULL)

        -- WorkHistoryID required and valid
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'AssessEmploymentPlacement', AssessmentID, 'WorkHistoryID',
            CONCAT('"', ISNULL(WorkHistoryID,'(blank)'), '" is invalid. WorkHistoryID is required and must match a value from the WorkHistory sheet.')
        FROM AssessEmploymentPlacement
        WHERE WorkHistoryID IS NULL OR WorkHistoryID = ''
           OR WorkHistoryID NOT IN (SELECT WorkHistoryID FROM WorkHistory WHERE WorkHistoryID IS NOT NULL)

        -- PlacementDate required and valid date
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'AssessEmploymentPlacement', AssessmentID, 'PlacementDate',
            CONCAT('"', ISNULL(PlacementDate,'(blank)'), '" is not a valid date. PlacementDate is required.')
        FROM AssessEmploymentPlacement WHERE PlacementDate IS NULL OR TRY_CONVERT(DATE, PlacementDate) IS NULL

        -- PlacementBy required and valid user
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'AssessEmploymentPlacement', AssessmentID, 'PlacementBy',
            CONCAT('"', ISNULL(PlacementBy,'(blank)'), '" is invalid. PlacementBy is required and must be a UserID from the Users sheet or a User EntityID from the destination database.')
        FROM AssessEmploymentPlacement
        WHERE PlacementBy IS NULL OR PlacementBy = ''
           OR (TRY_CONVERT(FLOAT, PlacementBy) IS NULL)
           OR (TRY_CONVERT(FLOAT, PlacementBy) IS NOT NULL
               AND PlacementBy NOT IN (SELECT UserID FROM Users WHERE UserID IS NOT NULL)
               AND PlacementBy NOT IN (SELECT CONVERT(VARCHAR, EntityID) FROM REPLACEME_ETL.dbo.Users))

        -- PlacementVerificationMethod from List 423
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'AssessEmploymentPlacement', AssessmentID, 'PlacementVerificationMethod',
            CONCAT('"', PlacementVerificationMethod, '" is invalid. PlacementVerificationMethod must be a value from ListID 423.')
        FROM AssessEmploymentPlacement
        WHERE PlacementVerificationMethod IS NOT NULL AND PlacementVerificationMethod != ''
          AND (TRY_CONVERT(FLOAT, PlacementVerificationMethod) IS NULL
               OR PlacementVerificationMethod NOT IN (SELECT ListValue FROM REPLACEME_ETL.dbo.ListItem WHERE ListID = 423))

        -- PlacementType from List 308
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'AssessEmploymentPlacement', AssessmentID, 'PlacementType',
            CONCAT('"', PlacementType, '" is invalid. PlacementType must be a value from ListID 308.')
        FROM AssessEmploymentPlacement
        WHERE PlacementType IS NOT NULL AND PlacementType != ''
          AND (TRY_CONVERT(FLOAT, PlacementType) IS NULL
               OR PlacementType NOT IN (SELECT ListValue FROM REPLACEME_ETL.dbo.ListItem WHERE ListID = 308))

        -- FollowUpType from List 152
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'AssessEmploymentPlacement', AssessmentID, 'FollowUpType',
            CONCAT('"', FollowUpType, '" is invalid. FollowUpType must be a value from ListID 152.')
        FROM AssessEmploymentPlacement
        WHERE FollowUpType IS NOT NULL AND FollowUpType != ''
          AND (TRY_CONVERT(FLOAT, FollowUpType) IS NULL
               OR FollowUpType NOT IN (SELECT ListValue FROM REPLACEME_ETL.dbo.ListItem WHERE ListID = 152))

    END
END
GO

/* ====================================================================================
   ASSESS HUD RHY
   ================================================================================== */
IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'AssessHUDRHY')
BEGIN
    IF EXISTS (SELECT 1 FROM AssessHUDRHY)
    BEGIN
        PRINT 'Starting AssessHUDRHY'

        -- AssessmentID must be valid
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'AssessHUDRHY', AssessmentID, 'AssessmentID',
            CONCAT('"', AssessmentID, '" is invalid. AssessmentID must match an AssessmentID from the Assessment sheet.')
        FROM AssessHUDRHY WHERE AssessmentID NOT IN (SELECT AssessmentID FROM Assessment)

        -- AssessmentID blank
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'AssessHUDRHY', AssessmentID, 'AssessmentID',
            'AssessmentID is blank. AssessmentID is required.'
        FROM AssessHUDRHY WHERE AssessmentID IS NULL OR AssessmentID = ''

        -- DateOfBCPDetermination optional, valid date
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'AssessHUDRHY', AssessmentID, 'DateOfBCPDetermination',
            CONCAT('"', DateOfBCPDetermination, '" is not a valid date.')
        FROM AssessHUDRHY WHERE DateOfBCPDetermination IS NOT NULL AND DateOfBCPDetermination != ''
          AND TRY_CONVERT(DATE, DateOfBCPDetermination) IS NULL

        -- FYSBYouth from List 100
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'AssessHUDRHY', AssessmentID, 'FYSBYouth',
            CONCAT('"', FYSBYouth, '" is invalid. FYSBYouth must be a value from ListID 100 (1=Yes, 2=No).')
        FROM AssessHUDRHY
        WHERE FYSBYouth IS NOT NULL AND FYSBYouth != ''
          AND (TRY_CONVERT(FLOAT, FYSBYouth) IS NULL
               OR FYSBYouth NOT IN (SELECT ListValue FROM REPLACEME_ETL.dbo.ListItem WHERE ListID = 100))

        -- ReasonNotFYSBYouth from List 2909
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'AssessHUDRHY', AssessmentID, 'ReasonNotFYSBYouth',
            CONCAT('"', ReasonNotFYSBYouth, '" is invalid. ReasonNotFYSBYouth must be a value from ListID 2909.')
        FROM AssessHUDRHY
        WHERE ReasonNotFYSBYouth IS NOT NULL AND ReasonNotFYSBYouth != ''
          AND (TRY_CONVERT(FLOAT, ReasonNotFYSBYouth) IS NULL
               OR ReasonNotFYSBYouth NOT IN (SELECT ListValue FROM REPLACEME_ETL.dbo.ListItem WHERE ListID = 2909))

        -- SexualOrientation from List 2910
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'AssessHUDRHY', AssessmentID, 'SexualOrientation',
            CONCAT('"', SexualOrientation, '" is invalid. SexualOrientation must be a value from ListID 2910.')
        FROM AssessHUDRHY
        WHERE SexualOrientation IS NOT NULL AND SexualOrientation != ''
          AND (TRY_CONVERT(FLOAT, SexualOrientation) IS NULL
               OR SexualOrientation NOT IN (SELECT ListValue FROM REPLACEME_ETL.dbo.ListItem WHERE ListID = 2910))

        -- SchoolStatus from List 2912
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'AssessHUDRHY', AssessmentID, 'SchoolStatus',
            CONCAT('"', SchoolStatus, '" is invalid. SchoolStatus must be a value from ListID 2912.')
        FROM AssessHUDRHY
        WHERE SchoolStatus IS NOT NULL AND SchoolStatus != ''
          AND (TRY_CONVERT(FLOAT, SchoolStatus) IS NULL
               OR SchoolStatus NOT IN (SELECT ListValue FROM REPLACEME_ETL.dbo.ListItem WHERE ListID = 2912))

        -- MentalHealthStatus from List 63
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'AssessHUDRHY', AssessmentID, 'MentalHealthStatus',
            CONCAT('"', MentalHealthStatus, '" is invalid. MentalHealthStatus must be a value from ListID 63.')
        FROM AssessHUDRHY
        WHERE MentalHealthStatus IS NOT NULL AND MentalHealthStatus != ''
          AND (TRY_CONVERT(FLOAT, MentalHealthStatus) IS NULL
               OR MentalHealthStatus NOT IN (SELECT ListValue FROM REPLACEME_ETL.dbo.ListItem WHERE ListID = 63))

        -- ReferralSource from List 2914
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'AssessHUDRHY', AssessmentID, 'ReferralSource',
            CONCAT('"', ReferralSource, '" is invalid. ReferralSource must be a value from ListID 2914.')
        FROM AssessHUDRHY
        WHERE ReferralSource IS NOT NULL AND ReferralSource != ''
          AND (TRY_CONVERT(FLOAT, ReferralSource) IS NULL
               OR ReferralSource NOT IN (SELECT ListValue FROM REPLACEME_ETL.dbo.ListItem WHERE ListID = 2914))

        -- WorkplaceViolenceThreats from List 37
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'AssessHUDRHY', AssessmentID, 'WorkplaceViolenceThreats',
            CONCAT('"', ISNULL(WorkplaceViolenceThreats,'(blank)'), '" is invalid. WorkplaceViolenceThreats must be a value from ListID 37.')
        FROM AssessHUDRHY
        WHERE WorkplaceViolenceThreats IS NOT NULL AND WorkplaceViolenceThreats != ''
          AND (TRY_CONVERT(FLOAT, WorkplaceViolenceThreats) IS NULL
               OR WorkplaceViolenceThreats NOT IN (SELECT ListValue FROM REPLACEME_ETL.dbo.ListItem WHERE ListID = 37))

        -- WorkPromiseDifference from List 37
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'AssessHUDRHY', AssessmentID, 'WorkPromiseDifference',
            CONCAT('"', ISNULL(WorkPromiseDifference,'(blank)'), '" is invalid. WorkPromiseDifference must be a value from ListID 37.')
        FROM AssessHUDRHY
        WHERE WorkPromiseDifference IS NOT NULL AND WorkPromiseDifference != ''
          AND (TRY_CONVERT(FLOAT, WorkPromiseDifference) IS NULL
               OR WorkPromiseDifference NOT IN (SELECT ListValue FROM REPLACEME_ETL.dbo.ListItem WHERE ListID = 37))

        -- Additional RHY list-checked columns (List 37)
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'AssessHUDRHY', AssessmentID, 'ExchangeForSex',
            CONCAT('"', ExchangeForSex, '" is invalid. ExchangeForSex must be a value from ListID 37.')
        FROM AssessHUDRHY
        WHERE ExchangeForSex IS NOT NULL AND ExchangeForSex != ''
          AND (TRY_CONVERT(FLOAT, ExchangeForSex) IS NULL
               OR ExchangeForSex NOT IN (SELECT ListValue FROM REPLACEME_ETL.dbo.ListItem WHERE ListID = 37))

        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'AssessHUDRHY', AssessmentID, 'FamilyReunificationAchieved',
            CONCAT('"', FamilyReunificationAchieved, '" is invalid. FamilyReunificationAchieved must be a value from ListID 37.')
        FROM AssessHUDRHY
        WHERE FamilyReunificationAchieved IS NOT NULL AND FamilyReunificationAchieved != ''
          AND (TRY_CONVERT(FLOAT, FamilyReunificationAchieved) IS NULL
               OR FamilyReunificationAchieved NOT IN (SELECT ListValue FROM REPLACEME_ETL.dbo.ListItem WHERE ListID = 37))

        -- WrittenAftercarePlan from List 1790
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'AssessHUDRHY', AssessmentID, 'WrittenAftercarePlan',
            CONCAT('"', WrittenAftercarePlan, '" is invalid. WrittenAftercarePlan must be a value from ListID 1790.')
        FROM AssessHUDRHY
        WHERE WrittenAftercarePlan IS NOT NULL AND WrittenAftercarePlan != ''
          AND (TRY_CONVERT(FLOAT, WrittenAftercarePlan) IS NULL
               OR WrittenAftercarePlan NOT IN (SELECT ListValue FROM REPLACEME_ETL.dbo.ListItem WHERE ListID = 1790))

    END
END
GO

/* ====================================================================================
   ASSESS DVS
   ================================================================================== */
IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'AssessDVS')
BEGIN
    IF EXISTS (SELECT 1 FROM AssessDVS)
    BEGIN
        PRINT 'Starting AssessDVS'

        -- AssessmentID must be valid
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'AssessDVS', AssessmentID, 'AssessmentID',
            CONCAT('"', AssessmentID, '" is invalid. AssessmentID must match an AssessmentID from the Assessment sheet.')
        FROM AssessDVS WHERE AssessmentID NOT IN (SELECT AssessmentID FROM Assessment)

        -- AssessmentID blank
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'AssessDVS', AssessmentID, 'AssessmentID',
            'AssessmentID is blank. AssessmentID is required.'
        FROM AssessDVS WHERE AssessmentID IS NULL OR AssessmentID = ''

        -- Duplicate AssessmentID
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'AssessDVS', AssessmentID, 'AssessmentID',
            CONCAT('"', AssessmentID, '" appears more than once. Each AssessmentID must be unique in this sheet.')
        FROM AssessDVS WHERE AssessmentID IN (SELECT AssessmentID FROM AssessDVS GROUP BY AssessmentID HAVING COUNT(*) > 1)

        -- MostRecentIncidentDate optional, valid date
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'AssessDVS', AssessmentID, 'MostRecentIncidentDate',
            CONCAT('"', MostRecentIncidentDate, '" is not a valid date. MostRecentIncidentDate is optional but must be a valid date if provided.')
        FROM AssessDVS WHERE MostRecentIncidentDate IS NOT NULL AND MostRecentIncidentDate != ''
          AND TRY_CONVERT(DATE, MostRecentIncidentDate) IS NULL

        -- MostRecentIncidentDesc max 2000 chars
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'AssessDVS', AssessmentID, 'MostRecentIncidentDesc',
            CONCAT('"', LEFT(MostRecentIncidentDesc,50), '..." is too long. MostRecentIncidentDesc cannot exceed 2000 characters.')
        FROM AssessDVS WHERE LEN(MostRecentIncidentDesc) > 2000

        -- DrugsAlcohol from List 100
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'AssessDVS', AssessmentID, 'DrugsAlcohol',
            CONCAT('"', DrugsAlcohol, '" is invalid. DrugsAlcohol must be a value from ListID 100 (1=Yes, 2=No).')
        FROM AssessDVS
        WHERE DrugsAlcohol IS NOT NULL AND DrugsAlcohol != ''
          AND (TRY_CONVERT(FLOAT, DrugsAlcohol) IS NULL
               OR DrugsAlcohol NOT IN (SELECT ListValue FROM REPLACEME_ETL.dbo.ListItem WHERE ListID = 100))

        -- VictimConsent from List 100
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'AssessDVS', AssessmentID, 'VictimConsent',
            CONCAT('"', VictimConsent, '" is invalid. VictimConsent must be a value from ListID 100 (1=Yes, 2=No).')
        FROM AssessDVS
        WHERE VictimConsent IS NOT NULL AND VictimConsent != ''
          AND (TRY_CONVERT(FLOAT, VictimConsent) IS NULL
               OR VictimConsent NOT IN (SELECT ListValue FROM REPLACEME_ETL.dbo.ListItem WHERE ListID = 100))

        -- PoliceInvolved from List 100
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'AssessDVS', AssessmentID, 'PoliceInvolved',
            CONCAT('"', PoliceInvolved, '" is invalid. PoliceInvolved must be a value from ListID 100 (1=Yes, 2=No).')
        FROM AssessDVS
        WHERE PoliceInvolved IS NOT NULL AND PoliceInvolved != ''
          AND (TRY_CONVERT(FLOAT, PoliceInvolved) IS NULL
               OR PoliceInvolved NOT IN (SELECT ListValue FROM REPLACEME_ETL.dbo.ListItem WHERE ListID = 100))

        -- ChargesFiled from List 100
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'AssessDVS', AssessmentID, 'ChargesFiled',
            CONCAT('"', ChargesFiled, '" is invalid. ChargesFiled must be a value from ListID 100 (1=Yes, 2=No).')
        FROM AssessDVS
        WHERE ChargesFiled IS NOT NULL AND ChargesFiled != ''
          AND (TRY_CONVERT(FLOAT, ChargesFiled) IS NULL
               OR ChargesFiled NOT IN (SELECT ListValue FROM REPLACEME_ETL.dbo.ListItem WHERE ListID = 100))

        -- MedAtt from List 100
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'AssessDVS', AssessmentID, 'MedAtt',
            CONCAT('"', MedAtt, '" is invalid. MedAtt must be a value from ListID 100 (1=Yes, 2=No).')
        FROM AssessDVS
        WHERE MedAtt IS NOT NULL AND MedAtt != ''
          AND (TRY_CONVERT(FLOAT, MedAtt) IS NULL
               OR MedAtt NOT IN (SELECT ListValue FROM REPLACEME_ETL.dbo.ListItem WHERE ListID = 100))

        -- AbuseToChildren from List 100
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'AssessDVS', AssessmentID, 'AbuseToChildren',
            CONCAT('"', AbuseToChildren, '" is invalid. AbuseToChildren must be a value from ListID 100 (1=Yes, 2=No).')
        FROM AssessDVS
        WHERE AbuseToChildren IS NOT NULL AND AbuseToChildren != ''
          AND (TRY_CONVERT(FLOAT, AbuseToChildren) IS NULL
               OR AbuseToChildren NOT IN (SELECT ListValue FROM REPLACEME_ETL.dbo.ListItem WHERE ListID = 100))

        -- ExitType from List 6864
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'AssessDVS', AssessmentID, 'ExitType',
            CONCAT('"', ExitType, '" is invalid. ExitType must be a value from ListID 6864 (1=Proper, 2=Improper).')
        FROM AssessDVS
        WHERE ExitType IS NOT NULL AND ExitType != ''
          AND (TRY_CONVERT(FLOAT, ExitType) IS NULL
               OR ExitType NOT IN (SELECT ListValue FROM REPLACEME_ETL.dbo.ListItem WHERE ListID = 6864))

        -- ExitDateRec from List 6870
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'AssessDVS', AssessmentID, 'ExitDateRec',
            CONCAT('"', ExitDateRec, '" is invalid. ExitDateRec must be a value from ListID 6870.')
        FROM AssessDVS
        WHERE ExitDateRec IS NOT NULL AND ExitDateRec != ''
          AND (TRY_CONVERT(FLOAT, ExitDateRec) IS NULL
               OR ExitDateRec NOT IN (SELECT ListValue FROM REPLACEME_ETL.dbo.ListItem WHERE ListID = 6870))

    END
END
GO

/* ====================================================================================
   OUTCOME
   ================================================================================== */
IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'Outcome')
BEGIN
    IF EXISTS (SELECT 1 FROM Outcome)
    BEGIN
        PRINT 'Starting Outcome'

        -- Duplicate OutcomeID
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Outcome', OutcomeID, 'OutcomeID',
            CONCAT('"', OutcomeID, '" appears more than once. Each OutcomeID must be unique.')
        FROM Outcome WHERE OutcomeID IN (SELECT OutcomeID FROM Outcome GROUP BY OutcomeID HAVING COUNT(*) > 1)

        -- OutcomeID blank
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Outcome', OutcomeID, 'OutcomeID',
            'OutcomeID is blank. OutcomeID is required.'
        FROM Outcome WHERE OutcomeID IS NULL OR OutcomeID = ''

        -- ClientID required and valid
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Outcome', OutcomeID, 'ClientID',
            CONCAT('"', ISNULL(ClientID,'(blank)'), '" is invalid. ClientID is required and must match a ClientID from the Client sheet.')
        FROM Outcome WHERE ClientID IS NULL OR ClientID NOT IN (SELECT ClientID FROM Client) 

        -- ContextTypeID required, must be 91 or 92
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Outcome', OutcomeID, 'ContextTypeID',
            CONCAT('"', ISNULL(ContextTypeID,'(blank)'), '" is invalid. ContextTypeID is required and must be 91 (Assessment) or 92 (Goal).')
        FROM Outcome WHERE ContextTypeID IS NULL OR ContextTypeID NOT IN ('91','92')

        -- ContextID required and must match referenced entity
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Outcome', OutcomeID, 'ContextID',
            CONCAT('"', ISNULL(ContextID,'(blank)'), '" is invalid. ContextID is required and must match an AssessmentID (if ContextTypeID=91) or a GoalID (if ContextTypeID=92).')
        FROM Outcome
        WHERE TRY_CONVERT(FLOAT, ContextID) IS NULL
           OR (ContextTypeID = '91' AND ContextID NOT IN (SELECT AssessmentID FROM Assessment WHERE AssessmentID IS NOT NULL))
           OR (ContextTypeID = '92' AND ContextID NOT IN (SELECT GoalID FROM Goal WHERE GoalID IS NOT NULL))

        -- DomainID required and must be valid
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Outcome', OutcomeID, 'DomainID',
            CONCAT('"', ISNULL(DomainID,'(blank)'), '" is invalid. DomainID is required and must be a valid value from the OutcomeDomain table in the destination database or from the OutcomeDomainScore tab of the staging document.')
        FROM Outcome
        WHERE TRY_CONVERT(FLOAT, DomainID) IS NULL
           OR DomainID IS NULL
           OR (TRY_CONVERT(FLOAT, DomainID) IS NOT NULL
               AND DomainID NOT IN (SELECT CONVERT(VARCHAR, DomainID) FROM REPLACEME_ETL.dbo.OutcomeDomain))

        -- ScoreID required and must be valid
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Outcome', OutcomeID, 'ScoreID',
            CONCAT('"', ISNULL(ScoreID,'(blank)'), '" is invalid. ScoreID is required and must be a valid value from the OutcomeScore table in the destination database or from the OutcomeDomainScore tab of the staging document.')
        FROM Outcome
        WHERE TRY_CONVERT(FLOAT, ScoreID) IS NULL
           OR ScoreID IS NULL
           OR (TRY_CONVERT(FLOAT, ScoreID) IS NOT NULL
               AND ScoreID NOT IN (SELECT CONVERT(VARCHAR, ScoreID) FROM REPLACEME_ETL.dbo.OutcomeScore))

        -- OutcomeDate optional, valid date
        INSERT INTO ErrorLog (TableName, ElementID, ColumnName, ErrorMessage)
        SELECT DISTINCT 'Outcome', OutcomeID, 'OutcomeDate',
            CONCAT('"', OutcomeDate, '" is not a valid date. OutcomeDate is optional but must be a valid date if provided.')
        FROM Outcome WHERE OutcomeDate IS NOT NULL AND TRY_CONVERT(DATE, OutcomeDate) IS NULL

    END
END
GO

/* ====================================================================================
   FINAL RESULTS
   Return all logged errors and warnings for review.
   "Error"   = Must be fixed before the data can be imported.
   "Warning" = Worth reviewing, but will not block the import.
   ================================================================================== */
SELECT
    TableName   AS [Sheet / Table],
    ElementID   AS [Record ID],
    ColumnName  AS [Column Name],
    CASE WHEN ErrorType IS NULL THEN 'Error' ELSE ErrorType END AS [Error Type],
    ErrorMessage AS [Description]
FROM ErrorLog
ORDER BY
    CASE WHEN ErrorType IS NULL THEN 1 ELSE 2 END,  -- Errors first, then Warnings
    TableName,
    ElementID,
    ColumnName
