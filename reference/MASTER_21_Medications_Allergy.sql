USE [Replace_Me_ETL]
GO

--------------------------------------- MedicationType --------------------------
IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE COLUMN_NAME = 'LegacyID'	AND TABLE_NAME = 'MEDICATIONTYPE')
BEGIN
	ALTER TABLE MEDICATIONTYPE ADD LegacyID VARCHAR(20)
END
GO

PRINT 'MEDICATIONTYPE'
INSERT INTO [dbo].[MEDICATIONTYPE] (CategoryID,TypeDescription,CreatedDate,MedicationType
,CreatedBy,ControlledSubstance,OwnedByOrgID,LegacyID)
SELECT DISTINCT
M.CategoryID
,TypeDescription
,ISNULL(M.CreatedDate,GETUTCDATE()) AS CreatedDate
,L.ListValue AS MedicationType  --Uses listID 212
,ISNULL(U.EntityID,11) AS CreatedBy
,M.ControlledSubstance
,12 AS OwnedByOrgID --make sure to change if another org id needed
,M.MedicationTypeID AS LegacyID
FROM Replace_Me_Staging.[dbo].[MEDICATIONTYPE] M
LEFT JOIN ListItem L on L.listid = 212 AND L.ListLabel = M.MedicationType
LEFT JOIN Users U on U.LegacyID = M.CreatedBy



--------------------------------------- Medications --------------------------
ALTER TABLE [dbo].[Medications] NOCHECK CONSTRAINT [FK_Medications_Client]
GO

PRINT 'Medications'
INSERT INTO Medications (
	ClientID
	,LastFillPharmacy
	,MedicationTypeID
	,ExpirationDate
	,RxNumber
	,DoctorName
	,Quantity
	,Dosage
	,UnitOfMeasure
	,MilligramsPerUnit
	,QuantityRemain
	,RefillRemain
	,RxStatus
	,BeginDate
	,ClosedDate
	,Restriction
	,OwnedByOrgID
--	,CreatedBy
--	,CreatedDate
	,LegacyID
)
SELECT
	C.EntityID AS ClientID
	,P.EntityID --P.EntityID AS Pharmacy
	,XM.MedicationTypeID
	,XM.ExpirationDate
	,LEFT(XM.RxNumber, 255) AS RxNumber
	,LEFT(XM.DoctorName, 255) AS DoctorName
	,ISNULL(XM.Quantity, 1) as Quantity
	,XM.Dosage
	,ISNULL(XM.UnitOfMeasure,1)
	,XM.MilligramsPerUnit
	,XM.QuantityRemain
	,XM.RefillRemain
	,XM.RxStatus
	,XM.BeginDate
	,isnull(XM.BeginDate, getdate())
	,XM.Restriction
	,24394 --select * from organization
--	,XM.CreatedBy
-- ,XM.CreatedDate
	,XM.MedicationID
FROM Replace_Me_Staging.dbo.Medications XM
INNER JOIN Client C ON C.LegacyID = XM.ClientID
INNER JOIN MedicationType MT ON MT.MedicationTypeID = XM.MedicationTypeID
INNER JOIN Provider P ON P.EntityID = XM.Pharmacy
--LEFT JOIN CaseNotes CN ON CN.LegacyID = XM.CaseNoteID
LEFT JOIN Medications M ON M.LegacyID = XM.MedicationID
WHERE M.LegacyID IS NULL

ALTER TABLE [dbo].[Medications] CHECK CONSTRAINT [FK_Medications_Client]
GO

--------------------------------------- MedicationMasterRefill --------------------------

PRINT 'MedicationMasterRefill'
INSERT INTO MedicationMasterRefill (
	MedicationID
	,RefillDate
	,CompleteDate
	,Status
	,Quantity
	,QuantityRemaining
	,CreatedDate
	,CreatedBy
	,OwnedByOrgID
	)
SELECT
	M.MedicationID
	,M.BeginDate AS RefillDate
	,'9999-12-31' AS CompleteDate
	,10 AS Status
	,M.Quantity
	,0 AS QuantityRemaining
	,M.CreatedDate
	,M.CreatedBy
	,M.OwnedByOrgID
FROM Medications M


--------------------------------------- MedicationRefill --------------------------

PRINT 'MedicationRefill'
INSERT INTO MedicationRefill (
MedicationID
,MedicationMasterRefillID	--NULL OK
,RefillTypeID
,RefillDate
,RefillBy
,Status
,PharmacyProviderID	--NULL OK
,Restriction
,OwnedByOrgID
,CreatedBy
)
SELECT
M.MedicationID
,MM.MedicationMasterRefillID	--NULL OK
,1 AS RefillTypeID
,M.BeginDate AS RefillDate
,11 AS RefillBy
,10 AS Status
,NULL --M.Pharmacy AS PharmacyProviderID	--NULL OK
,M.Restriction
,M.OwnedByOrgID
,M.CreatedBy
FROM Medications M
INNER JOIN MedicationMasterRefill MM ON MM.MedicationID = M.MedicationID
WHERE M.LegacyID IS NOT NULL


Delete from Medications
where medicationid in
(select medicationid from
	(select MedicationID, CLientID, MedicationTypeID, ROW_NUMBER() OVER (partition by clientid, medicationtypeid order by medicationid desc) as rownum from medications where legacyid is not null
	)s where rownum>1) m --1994

select count(*) from Replace_Me_Staging.dbo.Medications --5371

select count(*) from Medications where legacyid is not null --10742


select MedicationID, CLientID, MedicationTypeID, createddate, ROW_NUMBER() OVER (partition by clientid, medicationtypeid order by medicationid desc) as rownum
from Medications where legacyid is not null and deleteddate>getdate()
order by CLientID, MedicationTypeID

select * from client where entityid=35050
select * from AssessHIVRiskFactors ah inner join assessment a on ah.assessmentid=a.assessmentid where a.clientid=35050 --55467
select * from multiselectvalue where contexttypeid=1000000029--contextid=55467

select * from Replace_Me_Staging.dbo.Medications where clientid=1000 --147 pharmacy

select * from client where legacyid=1000 --clientid=35050


select * from Medications
where clientid=35050

select * from Provider where legacyid=147 --34510

Update M
Set LastFillPharmacy=P.Entityid
From Medications M inner join Replace_Me_Staging.dbo.Medications SM on M.LegacyID=SM.MEDICATIONID
INNER JOIN Provider P on SM.PHARMACY=P.LegacyID



----------------------------- AllergyType -----------------------------------------
PRINT 'AllergyType'
INSERT INTO AllergyType (
	CategoryID
	,TypeDescription
	,CreatedDate
	)
SELECT CategoryID
	,TypeDescription
	,CreatedDate
FROM REPLACE_ME_Staging.dbo.AllergyType
WHERE TypeDescription NOT IN (SELECT TypeDescription FROM AllergyType	)
