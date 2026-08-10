USE REPLACE_ME_ETL
GO

--------------------- Assessment --------------------------------------
IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE COLUMN_NAME = 'LegacyID' AND TABLE_NAME = 'Assessment')
BEGIN
	ALTER TABLE dbo.Assessment ADD LegacyID VARCHAR(20) NULL
END
GO

PRINT 'Assessment'
INSERT Assessment (
	EnrollmentID
	,ClientID
	,AssessmentBy
	,AssessmentEvent
	,BeginAssessment
	,CreatedBy
	,OwnedByOrgID
	,CreatedDate
	,Restriction
	,LegacyID
	)
SELECT DISTINCT EnrollmentID
	,ClientID
	,AssessmentBy
	,AssessmentEvent
	,BeginAssessment
	,CreatedBy
	,OwnedByOrgID
	,CreatedDate
	,Restriction
	,LegacyID
FROM (
	SELECT DISTINCT EnrollmentID
		,ClientID
		,AssessmentBy
		,AssessmentEvent
		,BeginAssessment
		,CreatedBy
		,OwnedByOrgID
		,CreatedDate
		,Restriction
		,LegacyID
		,ROW_NUMBER() OVER (
			PARTITION BY BeginAssessment
			,LegacyID
			,OwnedByOrgID
			,AssessmentEvent ORDER BY BeginAssessment
				,LegacyID
				,OwnedByOrgID
				,AssessmentEvent
			) AS RNUM
	FROM (
		SELECT DISTINCT SA.EnrollmentID AS EnrollmentID
			,C.EntityID AS ClientID
			,CASE WHEN U2.EntityID IS NOT NULL THEN U2.EntityID
				WHEN U.EntityID IS NOT NULL THEN U.EntityID
				ELSE 11 END AS AssessmentBy
			,ISNULL(A.AssessmentEvent, 1) AS AssessmentEvent
			,ISNULL(A.BeginAssessment, GETDATE()) AS BeginAssessment
			,ISNULL(EU2.EntityID, 11) AS CreatedBy
			,ISNULL(O.EntityID, 12) AS OwnedByOrgID
			,A.CreatedDate
			,A.Restriction AS Restriction
			,A.AssessmentID AS LegacyID
		FROM REPLACE_ME_Staging.dbo.Assessment A
		INNER JOIN Enrollment SA ON A.EnrollmentID = SA.LegacyID -- AND A.ClientID = SA.ClientID
			--INNER JOIN Enrollment E ON E.LegacyID = CAST(CONVERT(numeric,SA.EnrollmentID) AS VARCHAR)
			--AND E.ProgramID = P.ProgramID --AND E.BeginDate =SA.BeginDate --AND E.BeginDate = A.BeginAssessment
		INNER JOIN Client C ON C.LegacyID = A.ClientID
		LEFT JOIN Users EU2 ON EU2.LegacyID = A.CreatedBy	-- LEFT JOIN Users EU2 ON CONVERT(numeric,EU2.LegacyID) = A.CreatedBy
		LEFT JOIN Users U ON U.LegacyID = A.AssessmentBy --For imported users
		LEFT JOIN Users U2 ON Convert(varchar,U2.EntityID) = A.AssessmentBy --For existing users
		LEFT JOIN Organization O ON O.LegacyID = A.OwnedByOrgID
		LEFT JOIN Assessment A2 on A2.legacyid = A.AssessmentID
		WHERE A2.AssessmentID IS NULL -- Prevent Dupes
		) ABC
	) XYZ
WHERE XYZ.RNUM = 1

---------------------------------------- AssessHUDUniversal -------------------------------------
ALTER TABLE AssessHUDUniversal DISABLE TRIGGER ALL
GO

IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE COLUMN_NAME = 'LegacyID'	AND TABLE_NAME = 'AssessHUDUniversal')
BEGIN
	ALTER TABLE dbo.AssessHUDUniversal ADD LegacyID VARCHAR(20) NULL
END
GO

PRINT 'AssessHUDUniversal'
INSERT AssessHUDUniversal (
	AssessmentID
	--,VeteranStatus
	,DisablingCondition
	,HealthInsurance
	,PriorResidence
	,LengthOfStay
	,HousingStatus
	,PriorZipCode
	,CreatedBy
	,CreatedDate
	,ZipCodeQuality
	--,DisablingConditionServices
	--,ReceivedDisablingConditionServices
	,HIVServices
	--,ReceivedHIVServices
	,OutreachEngagementDate
	,LocationOfContact
	,DatetimeOfContact
	,HIVAIDSStatus
	,ClientLocation
	,ClientLocationDate
	--,ContinouslyHomeless
	,HmlssEpisodes3Years
	,HmlssMonths3Years
	--,HmlssStatusDocument
	--,MonthsContinuouslyHmlss
	,ChronicallyHomeless
	,LegacyID
	)
SELECT DISTINCT EA.AssessmentID
	--,SA.VeteranStatus
	,SA.DisablingCondition
	,ISNULL(SA.HealthInsurance, 3)
	,SA.PriorResidence
	,SA.LengthOfStay
	,SA.HousingStatus
	,SA.PriorZipCode
	,EA.CreatedBy
	,SA.CreatedDate
	,SA.ZipCodeQuality
	--,SA.DisablingConditionServices Cameron Removed this column on 9/11, it wasn't present in Staging DB anymore.
	--,SA.ReceivedDisablingConditionServices
	,SA.HIVServices
	--,SA.ReceivedHIVServices
	,SA.OutreachEngagementDate
	,SA.LocationOfContact
	,SA.DatetimeOfContact
	,SA.HIVAIDSStatus
	--,SA.ClientLocation
	,ISNULL(P.EntityID, 14) AS ClientLocation
	,SA.ClientLocationDate
	--,SA.ContinouslyHomelessLastYear
	--,SA.FourHomelessEpisodesInThreeYears--cam removed this from going into universal, and moved it down to go into AssessChornicHomeless.
	,SA.HmlssEpisodes3Years
	,SA.HmlssMonths3Years
	--,SA.HmlssStatusDocument
	--,SA.MonthsContinuouslyHmlss
	,SA.ChronicallyHomeless
	,SA.AssessmentID AS LegacyID
FROM REPLACE_ME_Staging.DBO.AssessHUDUniversal SA
INNER JOIN Assessment EA  ON EA.LegacyID = SA.AssessmentID
LEFT JOIN Provider P ON P.LegacyID = SA.ClientLocation
LEFT JOIN AssessHUDUniversal AExisting on AExisting.AssessmentID = EA.AssessmentID
WHERE AExisting.assessmentid is null

--------- WHERE SA.AssessmentEvent IN (1,3)
/* If the user has not entered a value for EnteringFromStreets, use the value for PriorResidence. */
PRINT 'UPDATE AssessHUDUniversal'

UPDATE AssessHUDUniversal
SET EnteringFromStreets = CASE
		WHEN PriorResidence IS NULL
			THEN NULL
		WHEN PriorResidence IN (
				14
				,1
				,16
				)
			THEN 1 --Place not meant for habitation = 14, ES=1, SH=16
				--ELSE Leave it the way it is.
		END
WHERE EnteringFromStreets IS NULL --Only update if user or other hasn't entered a value.
	AND LegacyID IS NOT NULL

ALTER TABLE AssessHUDUniversal ENABLE TRIGGER ALL
GO

---------------------------------------------AssessHUDProgram-------------------------
/* Has not been tested - I added the new columns 10/9/17
For this version, all columns are in the Assessment staging table. */
IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE COLUMN_NAME = 'LegacyID' AND TABLE_NAME = 'AssessHUDProgram')
BEGIN
	ALTER TABLE dbo.AssessHUDProgram ADD LegacyID VARCHAR(20) NULL
END
GO

ALTER TABLE AssessHUDProgram DISABLE TRIGGER ALL
GO

PRINT 'AssessHUDProgram'
INSERT AssessHUDProgram
WITH (TABLOCKX) (
		AssessmentID
		,NonCashBenefit
		,DomesticViolence
		,DVWhen
		,Farmer
		,Employed
		,HoursWorkedLastWk
		,EmploymentTenure
		,LookingForWork
		,EduInSchool
		,EduVocational
		,EduHighestGrade
		,EduCollegeLevel
		,GeneralHealthStatus
		,MaritalStatusID
		,PregnancyStatus
		,PregnancyDueDate
		,ChildEnrollment
		,ChildSchoolName
		,ChildMCV
		,ChildSchoolType
		,ChildLastEnrollDate
		,ChildEnrollProblem
		,ExitDestination
		,CreatedBy
		,CreatedDate
		,ReasonForLeaving
		,HousingStatus
		,HealthInsurance
		,SubstanceAbuse
		,SubstanceAbuseContinue
		,SubstanceAbuseServices
		,MentalIllness
		,MentalIllnessContinue
		,MentalIllnessServices
		,ChronicIllness
		,ChronicIllnessServices
		,HIVAIDS
		,HIVAIDSServices
		,PhysicalDisability
		,PhysicalDisabilityServices
		,DevelopmentalDisabled
		,DevelopmentalDisabledServices
		,FleeingDV
		,HPScreeningScore
		,VAMCStationNo
		,ReferredbyCoordEntry
		,HousingLossExpected
		,IncomeZero
		,IncomeZeroToFourteen
		,HouseholdChange
		,RentalEvictions
		,RiskLosingSubsidy
		,LiteralHomelessHistory
		,CriminalRecord
		,SexOffender
		,DependentsUnderSix
		,SingleParent
		,HouseholdFivePlus
		,VetServedIraqAfg
		,FemaleVet
		,HPTotalPoints
		,GranteeThresholdScore
		,ERVisits
		,NightsinJail
		,NightsinMedFacility
		,SuddenIncomeDecrease
		,LegacyID
		)
SELECT DISTINCT EA.AssessmentID
	,SA.NonCashBenefit
	,SA.DomesticViolence
	,SA.DVWhen
	,SA.Farmer
	,SA.Employed
	,SA.HoursWorkedLastWk
	,SA.EmploymentTenure
	,SA.LookingForWork
	,SA.EduInSchool
	,SA.EduVocational
	,SA.EduHighestGrade
	,SA.EduCollegeLevel
	,SA.GeneralHealthStatus
	,SA.MaritalStatusID
	,SA.PregnancyStatus
	,SA.PregnancyDueDate
	,SA.ChildEnrollment
	,SA.ChildSchoolName
	,SA.ChildMCV
	,SA.ChildSchoolType
	,SA.ChildLastEnrollDate
	,SA.ChildEnrollProblem
	,SA.ExitDestination
	,ISNULL(U.EntityID,11) AS CreatedBy
	,SA.CreatedDate
	,SA.ReasonForLeaving
	,SA.HousingStatus
	,SA.HealthInsurance
	,SA.SubstanceAbuse
	,SA.SubstanceAbuseContinue
	,SA.SubstanceAbuseServices
	,SA.MentalIllness
	,SA.MentalIllnessContinue
	,SA.MentalIllnessServices
	,SA.ChronicIllness
	,SA.ChronicIllnessServices
	,SA.HIVAIDSStatus
	,SA.HIVServices
	,SA.PhysicalDisability
	,SA.PhysicalDisabilityServices
	,SA.DevelopmentalDisabled
	,SA.DevelopmentalDisabledServices
	,SA.FleeingDV
	,SA.HPScreeningScore
	,SA.VAMCStationNo
	,SA.ReferredbyCoordEntry
	,SA.HousingLossExpected
	,SA.IncomeZero
	,SA.IncomeZeroToFourteen
	,SA.HouseholdChange
	,SA.RentalEvictions
	,SA.RiskLosingSubsidy
	,SA.LiteralHomelessHistory
	,SA.CriminalRecord
	,SA.SexOffender
	,SA.DependentsUnderSix
	,SA.SingleParent
	,SA.HouseholdFivePlus
	,SA.VetServedIraqAfg
	,SA.FemaleVet
	,SA.HPScreeningScore
	,SA.GranteeThresholdScore
	,SA.ERVisits
	,SA.NightsinJail
	,SA.NightsinMedFacility
	,SA.SuddenIncomeDecrease
	,SA.AssessmentID
FROM REPLACE_ME_Staging.DBO.AssessHUDProgram SA
INNER JOIN Assessment EA ON EA.LegacyID = SA.AssessmentID
LEFT JOIN AssessHUDProgram AExisting on AExisting.AssessmentID = EA.AssessmentID
LEFT JOIN Users U on SA.CREATEDBY = U.LegacyID
WHERE AExisting.assessmentid is null
GO

ALTER TABLE AssessHUDProgram ENABLE TRIGGER ALL
GO

-------------------------------- AssessNonCashBenefits -------------------------------------
INSERT dbo.AssessNonCashBenefits (
	[BenefitID]
	,[AssessmentID]
	)
SELECT -- DISTINCT
	FinancialItemTypeID
	,EA.AssessmentID
FROM REPLACE_ME_Staging.dbo.AssessFinancialItem AS AFI --SELECT * FROM REPLACE_ME_Staging .dbo. AssessFinancialItem WHERE IncomeBenefitType =0
INNER JOIN Assessment EA ON EA.LegacyID = AFI.AssessmentID
WHERE IncomeBenefitType = 0
	AND FinancialItemTypeID IS NOT NULL
	AND AFI.AssessmentID NOT IN (
		SELECT EA.LegacyID
		FROM AssessNonCashBenefits ANCB
		INNER JOIN Assessment EA2 ON ANCB.AssessmentID = EA2.AssessmentID
		WHERE EA2.LegacyID IS NOT NULL
		)
GO

/*
 --If a Assessment has two noncash benefits with a different amount on each, the SELECT Distinct turns it into effectively one record
 SELECT  DISTINCT --this returns 43774
FinancialItemTypeID
,AFI.AssessmentID
,AFI.Amount
 FROM  RELACE_ME_Staging .dbo. AssessFinancialItem AS AFI --SELECT * FROM RELACE_ME_Staging .dbo. AssessFinancialItem WHERE AssessmentID IN (SELECT AssessmentID FROM RELACE_ME_Staging .dbo. AssessFinancialItem GROUP BY AssessmentID, FinancialItemTypeID HAVING Count(Amount) > 1) ORDER BY AssessmentID
 WHERE IncomeBenefitType =0 AND FinancialItemTypeID IS NOT NULL
*/
-------------------------- AssessFinancialItem ------------------------------------
IF NOT EXISTS (
		SELECT *
		FROM INFORMATION_SCHEMA.COLUMNS
		WHERE COLUMN_NAME = 'FinancialTypeOther'
			AND TABLE_NAME = 'AssessFinancialItem'
		)
BEGIN
	ALTER TABLE AssessFinancialItem ADD FinancialTypeOther NVARCHAR(1000)
END
GO

PRINT 'AssessFinancialItem'
INSERT dbo.AssessFinancialItem (
	[AssessmentID]
	,[FinancialItemTypeID]
	,[Amount]
	,[CreatedBy]
	,[CreatedDate]
	,TransactionType --an update to the Trigger requires this element
	,Interval
	,IntervalAmount
	)
SELECT
	EA.AssessmentID
	,FinancialItemTypeID
	,ISNULL(Amount, 0) AS [Amount]
	,EA.CreatedBy
	,ISNULL(AFI.CreatedDate,GETUTCDATE()) AS CreatedDate
	,2 AS TransactionType --an update to the Trigger requires this element
	,5 AS Interval --Default is monthly, if customer wants to provide other interval type, !!! YOU must calculate the interval amt column !!!
	,ISNULL(Amount, 0) AS IntervalAmount
FROM REPLACE_ME_Staging.dbo.AssessFinancialItem AFI --SELECT * FROM REPLACE_ME_Staging .dbo. AssessFinancialItem WHERE FinancialTypeOther IS NOT NULL
INNER JOIN Assessment EA ON EA.LegacyID = AFI.AssessmentID
WHERE IncomeBenefitType IN (1,2)
	AND FinancialItemTypeID IS NOT NULL
	AND AFI.AssessmentID NOT IN (
		SELECT EA.LegacyID
		FROM AssessFinancialItem ANCB
		INNER JOIN Assessment EA ON ANCB.AssessmentID = EA.AssessmentID
		WHERE EA.LegacyID IS NOT NULL
		)

PRINT 'AssessFinancialItemOtherInfo'
INSERT INTO [dbo].[AssessFinancialItemOtherInfo] (
	[FinancialItemID]
	,[FinancialTypeOther]
	)
SELECT FinancialItemID
	,[FinancialTypeOther]
FROM AssessFinancialItem
WHERE [FinancialTypeOther] IS NOT NULL
	AND AssessmentID IN (
		SELECT AssessmentID
		FROM Assessment
		WHERE AssessmentID IS NOT NULL
		)
GO

IF EXISTS (
		SELECT *
		FROM INFORMATION_SCHEMA.COLUMNS
		WHERE COLUMN_NAME = 'FinancialTypeOther'
			AND TABLE_NAME = 'AssessFinancialItem'
		)
BEGIN
	ALTER TABLE AssessFinancialItem
	DROP COLUMN FinancialTypeOther
END
GO

-------------- AssessFinancialSummary ------------------------------
PRINT 'AssessFinancialSummary'
UPDATE AFS
SET AFS.HUD30DayIncomeQuality = A.HUD30DayIncomeQuality
--AFS.[AMIID] = A.AMIID
--SELECT AFS.HUD30DayIncomeQuality, A.HUD30DayIncomeQuality
FROM REPLACE_ME_Staging.dbo.Assessment A --SELECT DISTINCT HUD30DayIncomeQuality FROM REPLACE_ME_Staging.dbo.Assessment A
INNER JOIN Assessment EA ON A.AssessmentID = EA.LegacyID
INNER JOIN AssessFinancialSummary AFS ON AFS.AssessmentID = EA.AssessmentID
GO
