USE REPLACE_ME_ETL
GO

----------------------------------- Insurance -------------------------------------
/* This is for non-HUD insurance. */
IF NOT EXISTS (SELECT * FROM INFORMATION_SCHEMA.COLUMNS WHERE COLUMN_NAME = 'LegacyID' AND TABLE_NAME = 'Insurance')
BEGIN
ALTER TABLE dbo.Insurance ADD LegacyID VARCHAR(25) NULL
END
GO

PRINT 'Insurance'
INSERT INTO Insurance (
	ProviderID,
	PatientEntityID,
	InsuranceType,
	PolicyID,
	CreatedBy,
	Restriction,
	OwnedByOrgID,
	LegacyID
	)
SELECT DISTINCT
	SC.ProviderInsurance AS ProviderID,
	C.EntityID AS PatientEntityID,
	1 AS InsuranceType,
	InsurancePolicyID AS PolicyID,
	11 AS CreatedBy,
	C.Restriction,
	C.OwnedByOrgID,
	SC.ClientID
FROM REPLACE_ME_Staging.dbo.Client SC
INNER JOIN Client C ON C.LegacyID = SC.ClientID
LEFT JOIN Provider P ON P.EntityID = SC.ProviderName
WHERE C.EntityID NOT IN (SELECT LegacyID FROM Insurance WHERE LegacyID IS NOT NULL)

select * from AssessHealthInsurance where Legacyid is not null
select * from Insurance where LegacyID is not null
------------------------- HUD Insurance ---------------------------
IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE COLUMN_NAME = 'LegacyID' AND TABLE_NAME = 'AssessHealthInsurance')
BEGIN
	ALTER TABLE dbo.AssessHealthInsurance ADD LegacyID VARCHAR(25) NULL
END
GO

PRINT 'AssessHealthInsurance'
INSERT INTO AssessHealthInsurance (
	AssessmentID
	,InsuranceTypeID
	,Results
	,NoReason
	,LegacyID
)
SELECT
	AE.AssessmentID
	,AHI.InsuranceTypeID
	,AHI.Results
	,AHI.NoReason
	,AHI.HealthInsuranceID
FROM REPLACE_ME_Staging.dbo.Insurance AHI	--
INNER JOIN Assessment AE ON AE.LegacyID = AHI.AssessmentID	--
INNER JOIN ListItem LI ON LI.ListValue = AHI.InsuranceTypeID AND LI.ListID = 1797
LEFT JOIN AssessHealthInsurance AHID
	ON AHID.AssessmentID = AE.AssessmentID
	AND AHID.InsuranceTypeID = AHI.InsuranceTypeID
	WHERE AHID.AssessmentID IS NULL

PRINT 'AssessHealthInsuranceOther'
INSERT INTO AssessHealthInsuranceOtherInfo (
	AssessHealthInsuranceID
	,HealthInsuranceOther
	)
SELECT DISTINCT
	AHI.AssessHealthInsuranceID
	,AHIO.HealthInsuranceOther
FROM REPLACE_ME_Staging.dbo.Insurance AHIO
INNER JOIN AssessHealthInsurance AHI ON AHI.LegacyID = AHIO.HealthInsuranceID
WHERE AHIO.HealthInsuranceOther IS NOT NULL


------------------------- HUD Insurance ---------------------------
-- First, enter the data for InsuranceTypeID != 20. REPLACE_ME uses 20 to indicate no insurance.
PRINT 'AssessHealthInsurance'
INSERT INTO AssessHealthInsurance (
	AssessmentID
	,InsuranceTypeID
	,DeletedDate
	,Results
	,NoReason
	,LastModifiedDate
	,LastModifiedBy
)
SELECT
	AssessmentID
	,InsuranceTypeID
	,Results
	,NoReason
	,LastModifiedDate
	,LastModifiedBy
	FROM (
		SELECT
		A.AssessmentID AS AssessmentID
		,SI.InsuranceTypeID AS InsuranceTypeID
		,SI.Results AS Results
		,NULL AS NoReason
		,ISNULL(SI.X_CreatedDate, GETDATE()) AS LastModifiedDate
		,ISNULL(SI.X_CreatedBy, 11) AS LastModifiedBy
		,ROW_NUMBER() OVER (PARTITION BY SI.AssessmentID, SI.InsuranceTypeID, SI.Results ORDER BY SI.X_CreatedDate DESC) AS RNUM
		FROM REPLACE_ME_Staging.dbo.Insurance SI
		INNER JOIN Assessment A ON A.LegacyID = SI.AssessmentID
		LEFT JOIN Users U ON U.LegacyID = SI.X_CreatedBy
		WHERE SI.Results IS NOT NULL
		AND SI.InsuranceTypeID != 20			-- When REPLACE_ME enters 20, it means no insurance. The next script will populate the table for this.
	) XYZ
WHERE RNUM = 1


-- Then make a list of all assessments. Add all assessment info for these and set to No insurance.
DECLARE @NumberRecords INT
DECLARE @RowCount INT
DECLARE @AssessmentID BIGINT

DROP TABLE IF EXISTS #InsuranceAssessments

CREATE TABLE #InsuranceAssessments (
	RowID INT IDENTITY(1,1)
	,AssessmentID BIGINT
	,InsuranceTypeID INT
	,Results INT
)

INSERT INTO #InsuranceAssessments (AssessmentID, InsuranceTypeID, Results)
SELECT DISTINCT
	A.AssessmentID AS AssessmentID
	,SI.InsuranceTypeID
	,SI.Results
FROM REPLACE_ME_Staging.dbo.Insurance SI
INNER JOIN Assessment A ON A.LegacyID = SI.AssessmentID
LEFT JOIN Users U ON U.LegacyID = SI.X_CreatedBy

-- Get the number of records in the temporary table
SET @NumberRecords = @@ROWCOUNT
SET @RowCount = 1

WHILE @RowCount <= @NumberRecords
BEGIN

SET @AssessmentID = (SELECT AssessmentID FROM #InsuranceAssessments WHERE RowID = @RowCount)

-- Insert No Insurance records if no record exists
INSERT INTO AssessHealthInsurance (AssessmentID,InsuranceTypeID,Results)
SELECT @AssessmentID, 1, 2
WHERE CAST(@AssessmentID AS VARCHAR)+CAST(1 AS VARCHAR) NOT IN (
SELECT CAST(AssessmentID AS VARCHAR)+CAST(InsuranceTypeID AS VARCHAR) FROM AssessHealthInsurance)

INSERT INTO AssessHealthInsurance (AssessmentID,InsuranceTypeID,Results)
SELECT @AssessmentID, 5, 2
WHERE CAST(@AssessmentID AS VARCHAR)+CAST(5 AS VARCHAR) NOT IN (
SELECT CAST(AssessmentID AS VARCHAR)+CAST(InsuranceTypeID AS VARCHAR) FROM AssessHealthInsurance)

INSERT INTO AssessHealthInsurance (AssessmentID,InsuranceTypeID,Results)
SELECT @AssessmentID, 7, 2
WHERE CAST(@AssessmentID AS VARCHAR)+CAST(7 AS VARCHAR) NOT IN (
SELECT CAST(AssessmentID AS VARCHAR)+CAST(InsuranceTypeID AS VARCHAR) FROM AssessHealthInsurance)

INSERT INTO AssessHealthInsurance (AssessmentID,InsuranceTypeID,Results)
SELECT @AssessmentID, 10, 2
WHERE CAST(@AssessmentID AS VARCHAR)+CAST(10 AS VARCHAR) NOT IN (
SELECT CAST(AssessmentID AS VARCHAR)+CAST(InsuranceTypeID AS VARCHAR) FROM AssessHealthInsurance)

INSERT INTO AssessHealthInsurance (AssessmentID,InsuranceTypeID,Results)
SELECT @AssessmentID, 12, 2
WHERE CAST(@AssessmentID AS VARCHAR)+CAST(12 AS VARCHAR) NOT IN (
SELECT CAST(AssessmentID AS VARCHAR)+CAST(InsuranceTypeID AS VARCHAR) FROM AssessHealthInsurance)

INSERT INTO AssessHealthInsurance (AssessmentID,InsuranceTypeID,Results)
SELECT @AssessmentID, 13, 2
WHERE CAST(@AssessmentID AS VARCHAR)+CAST(13 AS VARCHAR) NOT IN (
SELECT CAST(AssessmentID AS VARCHAR)+CAST(InsuranceTypeID AS VARCHAR) FROM AssessHealthInsurance)

INSERT INTO AssessHealthInsurance (AssessmentID,InsuranceTypeID,Results)
SELECT @AssessmentID, 14, 2
WHERE CAST(@AssessmentID AS VARCHAR)+CAST(14 AS VARCHAR) NOT IN (
SELECT CAST(AssessmentID AS VARCHAR)+CAST(InsuranceTypeID AS VARCHAR) FROM AssessHealthInsurance)

INSERT INTO AssessHealthInsurance (AssessmentID,InsuranceTypeID,Results)
SELECT @AssessmentID, 15, 2
WHERE CAST(@AssessmentID AS VARCHAR)+CAST(15 AS VARCHAR) NOT IN (
SELECT CAST(AssessmentID AS VARCHAR)+CAST(InsuranceTypeID AS VARCHAR) FROM AssessHealthInsurance)

INSERT INTO AssessHealthInsurance (AssessmentID,InsuranceTypeID,Results)
SELECT @AssessmentID, -1, 2
WHERE CAST(@AssessmentID AS VARCHAR)+CAST(-1 AS VARCHAR) NOT IN (
SELECT CAST(AssessmentID AS VARCHAR)+CAST(InsuranceTypeID AS VARCHAR) FROM AssessHealthInsurance)

INSERT INTO AssessHealthInsurance (AssessmentID,InsuranceTypeID,Results)
SELECT @AssessmentID, 25, 2
WHERE CAST(@AssessmentID AS VARCHAR)+CAST(25 AS VARCHAR) NOT IN (
SELECT CAST(AssessmentID AS VARCHAR)+CAST(InsuranceTypeID AS VARCHAR) FROM AssessHealthInsurance)

SET @RowCount = @RowCount + 1
END

--select * from  #InsuranceAssessments
DROP TABLE IF EXISTS #InsuranceAssessments

----------------------------------------

PRINT 'AssessHealthInsuranceOther'
INSERT INTO AssessHealthInsuranceOtherInfo (
	AssessHealthInsuranceID
	,HealthInsuranceOther
	)
SELECT
	AHI.AssessHealthInsuranceID
	,AHIO.HealthInsuranceOther
FROM REPLACE_ME_Staging.dbo.Insurance AHIO
INNER JOIN AssessHealthInsurance AHI ON AHI.LegacyID = AHIO.HealthInsuranceID
WHERE AHIO.HealthInsuranceOther IS NOT NULL
