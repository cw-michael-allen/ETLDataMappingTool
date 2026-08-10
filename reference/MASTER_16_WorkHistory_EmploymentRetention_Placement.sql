USE REPLACE_ME_ETL

----------------------------- WorkHistory -----------------------------------------
IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE COLUMN_NAME = 'LegacyID'	AND TABLE_NAME = 'WorkHistory')
BEGIN
	ALTER TABLE WorkHistory ADD LegacyID VARCHAR(20)
END
GO

PRINT 'WorkHistory'
INSERT INTO WorkHistory (
	ClientID
	,BeginDate
	,EndDate
	,EmploymentTypeID
	,PaymentTypeID
	,PaymentIntervalID
	,JobTitle
	,AvgHoursPerWeek
	,HealthBenefits
	,WorkerPaysBenefits
	,ExitReasonID
	,TerminationReasonID
	,EndPaymentRate
	,Restriction
	,OwnedByOrgID
	,PayRate
	,ProviderID
	,YearlySalary
	,LegacyID
	)
SELECT C.EntityID
	,WH.BeginDate
	,ISNULL(WH.EndDate,'12/31/9999') AS EndDate
	,WH.EmploymentTypeID
	,WH.PaymentTypeID
	,WH.PaymentIntervalID
	,WH.JobTitle
	,WH.AvgHoursPerWeek
	,WH.HealthBenefits
	,WH.WorkerPaysBenefits
	,WH.ExitReasonID
	,WH.TerminationReasonID
	,ISNULL(WH.EndPaymentRate,0.00) 'EndPaymentRate'
	,1 AS 'Restriction'
	,C.OwnedByOrgID AS OwnedByOrgID
	,ISNULL(WH.PayRate,ISNULL(WH.EndPaymentRate,0.00)) 'PayRate'
	,P.EntityID AS ProviderID
	,CASE
		--WHEN WH.YearlySalary IS NOT NULL THEN WH.YearlySalary
		WHEN WH.PaymentTypeID=1 AND WH.AvgHoursPerWeek <= 40 THEN 52.0 * WH.AvgHoursPerWeek * WH.PayRate
		WHEN WH.PaymentTypeID=1 AND WH.AvgHoursPerWeek > 40 THEN (WH.AvgHoursPerWeek - 40.0 * WH.PayRate * 1.5) + (40.0 * WH.PayRate)
		WHEN WH.PaymentTypeID=5 THEN WH.PayRate
		END AS YearlySalary
	,WH.WorkHistoryID AS LegacyID
FROM REPLACE_ME_Staging.DBO.WorkHistory WH
INNER JOIN Client C ON C.LegacyID = WH.ClientID
INNER JOIN Provider P ON P.LegacyID = WH.ProviderID
LEFT JOIN WorkHistory WH2 on WH2.LegacyID = WH.WorkHistoryID
WHERE WH2.WorkHistoryID IS NULL

------------------------ EmploymentRetention -----------------------------------
IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE COLUMN_NAME = 'LegacyID' AND TABLE_NAME = 'EmploymentRetention')
BEGIN
	ALTER TABLE dbo.EmploymentRetention ADD LegacyID VARCHAR(20)
END
GO

PRINT 'EmploymentRetention'
INSERT INTO EmploymentRetention (
	AssessmentID
	,FollowUp
	,FollowUpType
	,AreYouStillWorking
	,VerificationMethod
	,VerificationBy
	,CaseNoteID
	,CreatedDate
	,CreatedBy
	,WorkHistoryID
	,MilestonePayRate
	,OwnedByOrgID
	,LegacyID)
SELECT
	A.AssessmentID AS AssessmentID
	,ER.FollowUp
	,ER.FollowUpType
	,ER.AreYouStillWorking
	,ER.VerificationMethod
	,ISNULL(U2.EntityID, 11) AS VerificationBy
	,ER.CaseNoteID
	,ER.CreatedDate
	,ISNULL(U.EntityID, 11) AS CreatedBy
	,W.WorkHistoryID AS WorkHistoryID
	,NULL AS MilestonePayRate
	,A.OwnedByOrgID AS OwnedByOrgID
	,ER.EmploymentRetentionID AS LegacyID
FROM REPLACE_ME_Staging.DBO.EmploymentRetention ER
INNER JOIN Assessment A ON A.LegacyID = ER.AssessmentID
LEFT JOIN WorkHistory W on W.LegacyID = ER.WORKHISTORYID
LEFT JOIN Users U ON U.LegacyID = ER.CreatedBy
LEFT JOIN Users U2 ON U2.LegacyID = ER.VerificationBy
LEFT JOIN EmploymentRetention ERExisting ON ERExisting.LegacyID = ER.EmploymentRetentionID
WHERE ERExisting.AssessmentID IS NULL

-------------------------- EmploymentPlacement -------------------------------------
IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE COLUMN_NAME = 'LegacyID' AND TABLE_NAME = 'AssessEmploymentPlacement')
BEGIN
	ALTER TABLE dbo.AssessEmploymentPlacement ADD LegacyID VARCHAR(20)
END
GO

PRINT 'AssessEmploymentPlacement'
INSERT INTO AssessEmploymentPlacement (
	AssessmentID
	,PlacementBy
	,PlacementDate
	,PlacementType
	,CaseNoteID
	,CreatedBy
	,CreatedDate
	,WorkHistoryID
	,PlacementVerificationMethod
	,GoodwillEmployerType
	,LegacyID
	)
SELECT DISTINCT
	A.AssessmentID
	,U.EntityID AS PlacementBy
	,EP.PlacementDate
	,EP.PlacementType
	,CN.CaseNoteID
	,ISNULL(U2.EntityID, 11) AS CreatedBy
	,GETUTCDATE() AS CreatedDate
	,WH.WorkHistoryID
	,EP.PlacementVerificationMethod
	,GoodwillEmployerType
	,EP.AssessmentID
FROM REPLACE_ME_Staging.dbo.AssessEmploymentPlacement EP
INNER JOIN Assessment A ON A.LegacyID = EP.AssessmentID
INNER JOIN Users U ON U.LegacyID = EP.PlacementBy
INNER JOIN Users U2 ON U2.LegacyID = EP.CreatedBy
LEFT JOIN WorkHistory WH ON WH.LegacyID = EP.WorkHistoryID
LEFT JOIN CaseNotes CN ON CN.LegacyID = EP.CaseNoteID
LEFT JOIN AssessEmploymentPlacement AEP ON AEP.LegacyID = EP.ASSESSMENTID
WHERE AEP.AssessmentID IS NULL --Prevent dupes

----------------------------- WorkHistoryJournal -----------------------------------------
PRINT 'WorkHistoryJournal'
INSERT INTO WorkHistoryJournal (WorkhistoryID, PaymentRate, JobTitle,EmploymentTypeID,PaymentIntervalID,AvgHoursPerWeek,PaymentTypeID
							,HealthBenefits,WorkerPaysBenefits,CreatedDate,BeginDate,EndDate,AssessmentID,ClientID
							,EndPaymentRate,Placement,PlacementDate,PlacementBy,OwnedByOrgID,PayRate,SICTypeID,ProviderID
							,PlacementVerificationMethod,LastmodifiedDate,LastmodifiedBy)
SELECT DISTINCT WH.WorkhistoryID, WH.PaymentRate, WH.JobTitle, WH.EmploymentTypeID, WH.PaymentIntervalID, WH.AvgHoursPerWeek,WH.PaymentTypeID
							,WH.HealthBenefits,WH.WorkerPaysBenefits,WH.CreatedDate,WH.BeginDate,WH.EndDate,AssessmentID,WH.ClientID
							,WH.EndPaymentRate,Placement,AEP.PlacementDate,AEP.PlacementBy,WH.OwnedByOrgID,WH.PayRate,SICTypeID,WH.ProviderID
							,AEP.PlacementVerificationMethod,WH.LastmodifiedDate,WH.LastmodifiedBy
FROM REPLACE_ME_Staging.DBO.WorkHistory WH2
INNER JOIN WorkHistory WH ON WH.LegacyID = WH2.WORKHISTORYID
LEFT JOIN AssessEmploymentPlacement AEP ON AEP.WorkHistoryID = WH.WorkHistoryID
WHERE WH.WorkhistoryID NOT IN (select WorkhistoryID FROM WorkHistoryJournal)
