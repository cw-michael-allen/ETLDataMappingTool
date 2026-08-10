----------------------------- FILES -----------------------------------------
USE REPLACE_ME_ETL
GO

IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
				WHERE COLUMN_NAME = 'LegacyID' AND TABLE_NAME = 'FILES')
BEGIN
	ALTER TABLE FILES ADD LegacyID VARCHAR(20)
END
GO

IF NOT EXISTS (SELECT 1 FROM REPLACE_ME_Staging.INFORMATION_SCHEMA.COLUMNS
				WHERE COLUMN_NAME = 'MimeType' AND TABLE_NAME = 'FileDocument')
BEGIN
	ALTER TABLE REPLACE_ME_Staging.dbo.FileDocument ADD MimeType VARCHAR(120)
END
GO

/** Add mimetypes - These are autopopulated now **/
----Added 11/2023
UPDATE FD
SET MimeType = CASE
	WHEN Filename like '%.pdf' THEN 'application/pdf'
	WHEN Filename like '%.PNG' THEN 'image/png'
	WHEN Filename like '%.docx' THEN 'application/vnd.openxmlformats-officedocument.word'
	WHEN Filename like '%.jpg' THEN 'image/jpeg'
	WHEN Filename like '%.tiff' THEN 'image/tiff'
	WHEN Filename like '%.tif' THEN 'image/tif'
	WHEN Filename like '%.jfif' THEN 'image/jpeg'
	WHEN Filename like '%.jpeg' THEN 'image/jpeg'
	WHEN Filename like '%.txt' THEN 'text/plain'
	WHEN Filename like '%.bmp' THEN 'image/bmp'
	WHEN Filename like '%.doc' THEN 'application/msword'
	WHEN Filename like '%.odt' THEN 'application/msword'
	WHEN Filename like '%.gif' THEN 'image/gif'
	WHEN Filename like '%.rtf' THEN 'application/msword'
	WHEN Filename like '%.xls' THEN 'application/vnd.ms-excel'
	WHEN Filename like '%.xlsx' THEN 'application/vnd.openxmlformats-officedocument.spre'
	WHEN Filename like '%.zip' THEN 'application/x-zip-compressed'
	WHEN Filename like '%.pjpeg' THEN 'image/pjpeg'
	WHEN Filename like '%.htm' THEN 'text/html'
	WHEN Filename like '%.html' THEN 'text/html'
	WHEN Filename like '%.msg' THEN 'application/octet-stream'
	WHEN Filename like '%.log' THEN 'application/octet-stream'
	WHEN Filename like '%.HEIC' THEN 'application/octet-stream'
	WHEN Filename like '%.smil' THEN 'application/octet-stream'
	WHEN Filename like '%.xps' THEN 'application/vnd.ms-xpsdocument'
	WHEN Filename like '%.mp3' THEN 'audio/mp3'
	WHEN Filename like '%.mp4' THEN 'audio/mp4'
	WHEN Filename like '%.wav' THEN 'audio/wav'
	WHEN Filename like '%.dotx' THEN 'application/vnd.openxmlformats-officedocument.wordprocessingml.template'
	WHEN Filename like '%.eml' THEN 'message/rfc822'
	WHEN Filename like '%.numbers' THEN 'application/x-iwork-numbers-sffnumbers'
	WHEN MimeType IS NOT NULL THEN MimeType
	ELSE 'application/octet-stream' --Default if nothing found.
	END
FROM REPLACE_ME_Staging.[dbo].[FileDocument] FD
WHERE MimeType IS NULL
GO

/** Run ALTER if FileNames are too long **/
--ALTER TABLE Files ALTER COLUMN FileDataLink varchar(100)

PRINT 'Files'
INSERT dbo.Files (
	ContextID
	,ContextTypeID
	,FileClassification
	,FileLabel
	,MimeType
	,[FileName]
	,FileDataLink
	,OwnedByOrgID
	,CreatedBy
	,CreatedDate
	,LegacyID
	)
SELECT DISTINCT EC.EntityID AS ClientID
	,10 AS ContextTypeID  -- 10 = Client
	,CASE WHEN FileClass.ListValue IN (1,2) THEN 2
		WHEN FileClass.ListValue IS NULL THEN 0
		ELSE 0
		END AS FileClassification --FileClassification not really needed unless client photo
	,LEFT(ISNULL(FD.[FileName], ''),100) AS FileLabel
	,FD.MimeType
	,LEFT(FD.FileName,100) AS FileName
	,FD.FileName AS FileDataLink
	,EC.OwnedByOrgID AS OwnedByOrgID
	,ISNULL(U.Createdby,11) AS CreatedBy
	,ISNULL(FD.CreatedDate,GETUTCDATE()) AS CreatedDate
	,FileDocumentID
FROM REPLACE_ME_Staging.[dbo].[FileDocument] FD
INNER JOIN Client EC ON EC.LegacyID = FD.ClientID
LEFT JOIN Users U on U.LegacyID = FD.CREATEDBY
LEFT JOIN FILES EF ON EF.LegacyID = FD.FileDocumentID
LEFT JOIN FILES EF2 ON EF2.FileDataLink = FD.[FileName]
LEFT JOIN ListItem FileClass on FileClass.listid = 84
	AND Convert(Varchar(10),FileClass.ListValue) = FD.FileClassification
WHERE EF.FileID IS NULL --Prevent dupe inserts
AND EF2.FileID IS NULL --Prevent dupe inserts x2
AND FD.FILEDOCUMENTID IS NOT NULL

PRINT 'ClientPrintPhoto'
INSERT INTO ClientPrintPhoto (ClientID,PrintPHotoFileID)
SELECT ABC.ContextID,ABC.FileID
FROM (SELECT
		F.ContextID
		,F.FileID
		,F.LegacyID
		,ROW_NUMBER() OVER (PARTITION BY ContextID ORDER BY FileID DESC) AS RNUM
	FROM Files F
	INNER JOIN REPLACE_ME_Staging.[dbo].[FileDocument] FD ON FD.FILEDOCUMENTID = F.LegacyID
	WHERE F.ContextID NOT IN (SELECT ClientID FROM ClientPrintPhoto)
	AND F.FileClassification IN (1,2)
	) ABC
WHERE RNUM = 1	-- only one photo file per client
AND ABC.LegacyID IS NOT NULL

----------------------------- DocumentCheck -----------------------------------------
IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
		WHERE COLUMN_NAME = 'LegacyID' AND TABLE_NAME = 'DocumentCheck')
BEGIN
	ALTER TABLE DocumentCheck ADD LegacyID VARCHAR(20)
END
GO

PRINT 'DocumentCheck'
INSERT dbo.DocumentCheck (
	ClientID
	,DocumentTypeID
	,VerificationMethodID
	,[Description]
	,StorageMethodID
	,IssuedDate
	,ExpiresDate
	,CreatedBy
	,CreatedDate
	,Restriction
	,OwnedByOrgID
	,LegacyID
	)
SELECT DISTINCT EC.EntityID
	,FD.DocumentTypeID
	,ISNULL(FD.VerificationMethodID, 1) 'VerificationMethodID'
	,LEFT(ISNULL(FD.[Description], ''),100) AS [Description]
	,ISNULL(FD.StorageMethodID, 1) 'StorageMethodID'
	,IssueDate
	,FD.ExpiresDate
	,11 AS CreatedBy
	,ISNULL(FD.CreatedDate,GETDATE()) 'CreatedDate'
	,ISNULL(FD.Restriction, 1) AS Restriction
	,EC.OwnedByOrgID
	,FileDocumentID 'LegacyID'
FROM REPLACE_ME_Staging.[dbo].[FileDocument] FD
INNER JOIN Client EC ON EC.LegacyID = FD.ClientID
INNER JOIN Files F on F.LegacyID = FD.FileDocumentID
LEFT JOIN DocumentCheck EDC ON EDC.LegacyID = FD.FileDocumentID
WHERE EDC.DocumentCheckID IS NULL
	AND FD.DocumentTypeID IS NOT NULL

PRINT 'JunctionFile'
INSERT INTO JunctionFile (
	ContextID
	,ContextTypeID
	,FileID
	)
SELECT DISTINCT DocumentCheck.DocumentCheckID
	,12 AS ContextID
	,Files.FileID
FROM Files
INNER JOIN DocumentCheck ON Files.LegacyID = DocumentCheck.LegacyID
	AND Files.ContextID = DocumentCheck.ClientID
	AND Files.LegacyID IS NOT NULL
INNER JOIN Client C on C.EntityID = DocumentCheck.ClientID
INNER JOIN REPLACE_ME_Staging.[dbo].[FileDocument] FD ON FD.FileDocumentID = DocumentCheck.LegacyID
LEFT JOIN JunctionFile JF on JF.FileID = Files.FileID
	AND JF.ContextTypeID = 12
WHERE JF.JunctionFileID IS NULL
