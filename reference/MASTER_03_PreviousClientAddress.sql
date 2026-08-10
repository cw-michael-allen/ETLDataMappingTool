USE REPLACE_ME_ETL

--------------------------------------- AddressHistory --------------------------
IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE COLUMN_NAME = 'LegacyID' AND TABLE_NAME= 'ClientAddress')
BEGIN
	ALTER TABLE dbo.ClientAddress ADD LegacyID VARCHAR(30) NULL
END
GO

PRINT 'Client Address History'
INSERT INTO ClientAddress(
	ClientID
	,Address1
	,Address2
	,ZipCode
	,City
	,[State]
	,County
	,AddressType
	,BeginDate
	,EndDate
	,Restriction
	,CreatedBy
	,CreatedDate
	,OwnedByOrgID
	,County
	,LegacyID
)
SELECT
	C.EntityID
	,ISNULL(Address1,'') AS Address1
	,ISNULL(Address2,'') AS Address2
	,CASE WHEN LEFT(A.ZipCode,5) IN (SELECT ZipCode FROM ZipCode) THEN LEFT(A.ZipCode,5) ELSE '00000' END AS Zip
	,City
	,[State]
	,A.County
	,A.AddressType AS AddressType
	,BeginDate
	,EndDate
	,1 AS Restriction
	,11 AS CreatedBy
	,GETUTCDATE() AS CreatedDate
	,C.OwnedByOrgID
	,County
	,A.AddressID AS LegacyID
FROM REPLACE_ME_Staging.dbo.AddressHistory A
INNER JOIN Client C ON C.LegacyID = A.ClientID
LEFT JOIN ZipCode Z  ON ISNULL(C.Zip, '00000') = z.ZipCode
WHERE A.AddressID NOT IN (SELECT LegacyID FROM dbo.ClientAddress WHERE LegacyID IS NOT NULL)

--PRINT 'Add FamilyID to ClientAddress'
--UPDATE ClientAddress
--SET FamilyID = FM.FAMILYID
--FROM ClientAddress CA
--INNER JOIN FamilyMember FM ON FM.ClientID = CA.ClientID
--WHERE FM.FamilyID > 0
