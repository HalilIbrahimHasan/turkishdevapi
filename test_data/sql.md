-- 1. 834 ile ilgili tüm tabloları bul
SELECT 
    TABLE_SCHEMA,
    TABLE_NAME
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_NAME LIKE '%834%'
   OR TABLE_NAME LIKE '%Inbound%'
   OR TABLE_NAME LIKE '%Enrollment%'
ORDER BY TABLE_SCHEMA, TABLE_NAME;

Sonra aday tablolar için kolonları çıkaracağız:

SELECT 
    TABLE_SCHEMA,
    TABLE_NAME,
    COLUMN_NAME,
    DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME LIKE '%834%'
   OR TABLE_NAME LIKE '%Inbound%'
   OR TABLE_NAME LIKE '%Enrollment%'
ORDER BY TABLE_SCHEMA, TABLE_NAME, ORDINAL_POSITION;

Bizim arayacağımız kritik kolonlar:

GAA_HIOS_ID
Coverage_Year
memberSSN
member_id
exchangeAssignedPolicyID
issuerPolicyID
memberMaintEffectiveDate
actionCode
event_type_code
PA_enrollment_status_description
PA_enrollee_status_description
S_enrollee_status_description
source_file
load_date
