USE REPLACE_ME_ETL
GO

----------------------------- MultiSelectValue -----------------------------------------
PRINT 'MultiSelectValue'

INSERT INTO MultiSelectValue (
	ContextTypeID
	,ContextID
	,ListID
	,ListValue
	,OtherDescription
	,CreatedBy
	,CreatedDate
	,OwnedByOrgID
	)
SELECT ContextTypeID
	,C.EntityID AS ContextID
	,ListID
	,ListValue
	,OtherDescription
	,CreatedBy
	,GETDATE() AS CreatedDate
	,C.OwnedByOrgID AS OwnedByOrgID
FROM REPLACE_ME_Staging.DBO.MultiSelectValue
INNER JOIN Client C ON C.LegacyID = MSV.ContextID AND ContextTypeID = 10
