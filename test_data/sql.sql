-- 2025 raw 834 DB counts by issuer and month
SELECT
    Coverage_Year,
    GAA_HIOS_ID,
    YEAR(CAST(GAA_834_File_Date AS date)) AS File_Year,
    MONTH(CAST(GAA_834_File_Date AS date)) AS File_Month,
    COUNT(*) AS DB_Raw_Record_Count,
    COUNT(DISTINCT GAA_834_File_Name) AS DB_File_Count,
    COUNT(DISTINCT exchgAssignedPolicyID) AS Distinct_Policy_Count,
    COUNT(DISTINCT exchgIndivIdentifier) AS Distinct_Member_Count
FROM dbo.[834_Inbound_test]
WHERE Coverage_Year = 2025
GROUP BY
    Coverage_Year,
    GAA_HIOS_ID,
    YEAR(CAST(GAA_834_File_Date AS date)),
    MONTH(CAST(GAA_834_File_Date AS date))
ORDER BY
    GAA_HIOS_ID,
    File_Year,
    File_Month;

Sonra status dağılımı:

SELECT
    Coverage_Year,
    GAA_HIOS_ID,
    MONTH(CAST(GAA_834_File_Date AS date)) AS File_Month,
    event_type_code,
    event_type_code_desc,
    enrolleeStatus,
    COUNT(*) AS Record_Count,
    COUNT(DISTINCT exchgAssignedPolicyID) AS Distinct_Policy_Count,
    COUNT(DISTINCT exchgIndivIdentifier) AS Distinct_Member_Count
FROM dbo.[834_Inbound_test]
WHERE Coverage_Year = 2025
GROUP BY
    Coverage_Year,
    GAA_HIOS_ID,
    MONTH(CAST(GAA_834_File_Date AS date)),
    event_type_code,
    event_type_code_desc,
    enrolleeStatus
ORDER BY
    GAA_HIOS_ID,
    File_Month,
    event_type_code;

Ve business table için:

SELECT
    coverage_year,
    hios_issuer_id,
    MONTH(GAA_Load_Date) AS Load_Month,
    Insurance_Type,
    enrollment_status_description,
    enrollee_status_description,
    COUNT(*) AS Business_Record_Count,
    COUNT(DISTINCT enrollment_id) AS Enrollment_Count,
    COUNT(DISTINCT enrollee_id) AS Enrollee_Count
FROM dbo.Enrollments_PY2025
WHERE coverage_year = 2025
GROUP BY
    coverage_year,
    hios_issuer_id,
    MONTH(GAA_Load_Date),
    Insurance_Type,
    enrollment_status_description,
    enrollee_status_description
ORDER BY
    hios_issuer_id,
    Load_Month;

Cursor logic’i de gönder cicim. Özellikle şunları görmem lazım:

SELECT
    '834_Inbound_test' AS table_name,
    COUNT(*) AS total_count,
    COUNT(DISTINCT GAA_HIOS_ID) AS issuer_count,
    MIN(GAA_834_File_Date) AS min_file_date,
    MAX(GAA_834_File_Date) AS max_file_date
FROM dbo.[834_Inbound_test]

UNION ALL

SELECT
    '834_Inbound_header_test',
    COUNT(*),
    COUNT(DISTINCT GAA_HIOS_ID),
    MIN(GAA_834_File_Date),
    MAX(GAA_834_File_Date)
FROM dbo.[834_Inbound_header_test];

Sonra business-ready adayları için bunu çalıştır:

SELECT
    'Enrollments_PY2025' AS table_name,
    COUNT(*) AS total_count,
    COUNT(DISTINCT hios_issuer_id) AS issuer_count,
    MIN(GAA_Load_Date) AS min_load_date,
    MAX(GAA_Load_Date) AS max_load_date
FROM dbo.Enrollments_PY2025

UNION ALL

SELECT
    'PY2025-Enrollments_All',
    COUNT(*),
    COUNT(DISTINCT hios_issuer_id),
    MIN(GAA_Load_Date),
    MAX(GAA_Load_Date)
FROM dbo.[PY2025-Enrollments_All];


SELECT COLUMN_NAME
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'PY2025-Enrollments_All'
ORDER BY ORDINAL_POSITION;


SELECT
    t.name AS table_name,
    SUM(p.rows) AS row_count
FROM sys.tables t
JOIN sys.partitions p
    ON t.object_id = p.object_id
WHERE p.index_id IN (0,1)
  AND (
        t.name LIKE '%834%'
     OR t.name LIKE '%Inbound%'
     OR t.name LIKE '%Enroll%'
  )
GROUP BY t.name
ORDER BY row_count DESC;

=============

SELECT TOP 20 *
FROM dbo.GI_Inbound;



SELECT COLUMN_NAME
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME='GI_Inbound'
ORDER BY ORDINAL_POSITION;





SELECT TOP 20 *
FROM dbo.Enrollments_TEST;




SELECT COLUMN_NAME
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME='Enrollments_TEST'
ORDER BY ORDINAL_POSITION;

=============

SELECT
    coverage_year,
    hios_issuer_id,
    MONTH(GAA_Load_Datetime) AS load_month,
    COUNT(*) AS row_count,
    COUNT(DISTINCT enrollment_id) AS enrollment_count,
    COUNT(DISTINCT enrollee_id) AS enrollee_count
FROM dbo.Enrollments_TEST
WHERE coverage_year = 2025
GROUP BY
    coverage_year,
    hios_issuer_id,
    MONTH(GAA_Load_Datetime)
ORDER BY
    hios_issuer_id,
    load_month;

====

SELECT
    coverage_year,
    hios_issuer_id,
    MONTH(GAA_Load_Datetime) AS load_month,
    Insurance_Type,
    enrollment_status_description,
    enrollee_status_description,
    COUNT(*) AS row_count,
    COUNT(DISTINCT enrollment_id) AS enrollment_count,
    COUNT(DISTINCT enrollee_id) AS enrollee_count
FROM dbo.Enrollments_TEST
WHERE coverage_year = 2025
GROUP BY
    coverage_year,
    hios_issuer_id,
    MONTH(GAA_Load_Datetime),
    Insurance_Type,
    enrollment_status_description,
    enrollee_status_description
ORDER BY
    hios_issuer_id,
    load_month,
    enrollment_status_description,
    enrollee_status_description;

=================


SELECT
    COUNT(*) AS rows,
    COUNT(DISTINCT enrollment_id) AS enrollments,
    COUNT(DISTINCT enrollee_id) AS enrollees,
    COUNT(DISTINCT household_id) AS households
FROM dbo.Enrollments_TEST
WHERE coverage_year=2025
AND hios_issuer_id=13535
AND MONTH(GAA_Load_Datetime)=6;

Sonra bir tane daha:

SELECT
    enrollment_id,
    COUNT(*) AS repeats
FROM dbo.Enrollments_TEST
WHERE coverage_year=2025
AND hios_issuer_id=13535
AND MONTH(GAA_Load_Datetime)=6
GROUP BY enrollment_id
HAVING COUNT(*)>1
ORDER BY repeats DESC;


========================

SELECT
    t.name AS table_name,
    c.name AS column_name
FROM sys.tables t
JOIN sys.columns c
ON t.object_id=c.object_id
WHERE
c.name IN
(
'GAA_HIOS_ID',
'memberMaintEffectiveDate',
'exchgAssignedPolicyID',
'exchgIndivIdentifier',
'memberSSN',
'policyID',
'enrollment_id',
'enrollee_id'
)
ORDER BY
t.name;


SELECT
    t.name,
    SUM(p.rows) rows
FROM sys.tables t
JOIN sys.partitions p
ON t.object_id=p.object_id
WHERE p.index_id IN (0,1)
GROUP BY
t.name
HAVING
SUM(p.rows)>100000
ORDER BY
rows DESC;



SELECT
TABLE_SCHEMA,
TABLE_NAME,
COLUMN_NAME
FROM INFORMATION_SCHEMA.COLUMNS
WHERE
COLUMN_NAME LIKE '%memberMaint%'
OR COLUMN_NAME LIKE '%policy%'
OR COLUMN_NAME LIKE '%HIOS%'
OR COLUMN_NAME LIKE '%exchg%'
OR COLUMN_NAME LIKE '%834%'
ORDER BY
TABLE_NAME;

===============


1. Kolonlarını görelim
SELECT COLUMN_NAME, DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'monthly_discrepancy_PY2025'
ORDER BY ORDINAL_POSITION;
2. İlk 20 satır
SELECT TOP 20 *
FROM dbo.monthly_discrepancy_PY2025;
3. Issuer ve ay dağılımı var mı bakalım

Önce tarih kolonlarını görmemiz lazım ama deneme için:

SELECT TOP 5 *
FROM dbo.monthly_discrepancy_PY2025
WHERE GAA_HIOS_ID = 13535;
4. Eğer tarih/load/month kolonu varsa hemen count alacağız

Kolonları görünce şuna benzer query yazacağız:

SELECT
    GAA_HIOS_ID,
    MONTH(<date_column>) AS month_num,
    COUNT(*) AS row_count,
    COUNT(DISTINCT Exchange_Assigned_Policy_ID) AS distinct_policy_count
FROM dbo.monthly_discrepancy_PY2025
GROUP BY
    GAA_HIOS_ID,
    MONTH(<date_column>)
ORDER BY
    GAA_HIOS_ID,
    month_num;


SELECT
    TABLE_NAME,
    COLUMN_NAME
FROM INFORMATION_SCHEMA.COLUMNS
WHERE
    COLUMN_NAME LIKE '%GAA_834%'
    OR COLUMN_NAME LIKE '%834_File%'
    OR COLUMN_NAME LIKE '%memberMaint%'
    OR COLUMN_NAME LIKE '%exchgAssigned%'
    OR COLUMN_NAME LIKE '%exchgIndiv%'
    OR COLUMN_NAME LIKE '%healthCoveragePolicy%'
ORDER BY
    TABLE_NAME,
    COLUMN_NAME;

=====================

SELECT
    COUNT(*) AS RawRows,
    COUNT(DISTINCT exchgAssignedPolicyID) AS Policies,
    COUNT(DISTINCT exchgIndivIdentifier) AS Members,
    MIN(GAA_834_File_Date) AS FirstFile,
    MAX(GAA_834_File_Date) AS LastFile
FROM dbo.834_Inbound_test;


SELECT
    GAA_HIOS_ID,
    YEAR(GAA_834_File_Date) AS FileYear,
    MONTH(GAA_834_File_Date) AS FileMonth,
    COUNT(*) AS RawRows
FROM dbo.834_Inbound_test
GROUP BY
    GAA_HIOS_ID,
    YEAR(GAA_834_File_Date),
    MONTH(GAA_834_File_Date)
ORDER BY
    GAA_HIOS_ID,
    FileYear,
    FileMonth;


==================

SELECT
    COUNT(*) AS RawRows,
    COUNT(DISTINCT exchgAssignedPolicyID) AS Policies,
    COUNT(DISTINCT exchgIndivIdentifier) AS Members,
    MIN(GAA_834_File_Date) AS FirstFile,
    MAX(GAA_834_File_Date) AS LastFile
FROM dbo.[834_Inbound_test];


SELECT
    GAA_HIOS_ID,
    YEAR(GAA_834_File_Date) AS FileYear,
    MONTH(GAA_834_File_Date) AS FileMonth,
    COUNT(*) AS RawRows
FROM dbo.[834_Inbound_test]
GROUP BY
    GAA_HIOS_ID,
    YEAR(GAA_834_File_Date),
    MONTH(GAA_834_File_Date)
ORDER BY
    GAA_HIOS_ID,
    FileYear,
    FileMonth;

===============


SELECT
    COUNT(*) AS RawRows,
    COUNT(DISTINCT exchgAssignedPolicyID) AS Policies,
    COUNT(DISTINCT exchgIndivIdentifier) AS Members
FROM dbo.[834_Inbound_test]
WHERE
GAA_HIOS_ID=13535
AND YEAR(GAA_834_File_Date)=2026
AND MONTH(GAA_834_File_Date)=5;


SELECT
    GAA_HIOS_ID,
    COUNT(*) AS RawRows,
    COUNT(DISTINCT exchgAssignedPolicyID) AS Policies,
    COUNT(DISTINCT exchgIndivIdentifier) AS Members
FROM dbo.[834_Inbound_test]
WHERE
YEAR(GAA_834_File_Date)=2026
AND MONTH(GAA_834_File_Date)=5
GROUP BY
GAA_HIOS_ID
ORDER BY
GAA_HIOS_ID;

============

SELECT
    COUNT(DISTINCT GAA_HIOS_ID) AS IssuerCount
FROM dbo.[834_Inbound_test];


SELECT DISTINCT
    GAA_HIOS_ID
FROM dbo.[834_Inbound_test]
ORDER BY GAA_HIOS_ID;


==================


SELECT
    GAA_HIOS_ID,
    YEAR(GAA_834_File_Date) AS FileYear,
    MONTH(GAA_834_File_Date) AS FileMonth,
    COUNT(*) AS DB_RawRows,
    COUNT(DISTINCT GAA_834_File_Name) AS DB_FileCount,
    COUNT(DISTINCT exchgAssignedPolicyID) AS DB_Policies,
    COUNT(DISTINCT exchgIndivIdentifier) AS DB_Members
FROM dbo.[834_Inbound_test]
GROUP BY
    GAA_HIOS_ID,
    YEAR(GAA_834_File_Date),
    MONTH(GAA_834_File_Date)
ORDER BY
    GAA_HIOS_ID,
    FileYear,
    FileMonth;



SELECT
    GAA_HIOS_ID,
    YEAR(GAA_834_File_Date) AS FileYear,
    MONTH(GAA_834_File_Date) AS FileMonth,
    Insurance_Type,
    enrolleeStatus,
    COUNT(*) AS DB_RawRows,
    COUNT(DISTINCT exchgAssignedPolicyID) AS DB_Policies,
    COUNT(DISTINCT exchgIndivIdentifier) AS DB_Members
FROM dbo.[834_Inbound_test]
GROUP BY
    GAA_HIOS_ID,
    YEAR(GAA_834_File_Date),
    MONTH(GAA_834_File_Date),
    Insurance_Type,
    enrolleeStatus
ORDER BY
    GAA_HIOS_ID,
    FileYear,
    FileMonth,
    Insurance_Type,
    enrolleeStatus;



SELECT
    'test_834_in' AS table_name,
    COUNT(*) AS rows_count
FROM dbo.[test_834_in]

UNION ALL

SELECT
    '834_Inbound_test',
    COUNT(*)
FROM dbo.[834_Inbound_test]

UNION ALL

SELECT
    'monthly_discrepancy_PY2025',
    COUNT(*)
FROM dbo.monthly_discrepancy_PY2025

UNION ALL

SELECT
    'Enrollments_TEST',
    COUNT(*)
FROM dbo.Enrollments_TEST;


==============


WITH normalized AS
(
    SELECT
        GAA_HIOS_ID,
        Coverage_Year,
        GAA_834_File_Date,
        Insurance_Type,
        enrolleeStatus,
        exchgAssignedPolicyID,
        exchgIndivIdentifier,
        memberMaintEffectiveDate,

        ROW_NUMBER() OVER
        (
            PARTITION BY
                GAA_HIOS_ID,
                exchgAssignedPolicyID,
                exchgIndivIdentifier,
                Insurance_Type,
                enrolleeStatus,
                memberMaintEffectiveDate
            ORDER BY
                GAA_834_File_Date DESC
        ) rn

    FROM dbo.834_Inbound_test

    WHERE Coverage_Year=2025
      AND GAA_HIOS_ID IN (13535,15105,43802)
)

SELECT
    COUNT(*) RawRows,

    SUM(CASE WHEN rn=1 THEN 1 END) AfterDedupe


    =========


    WITH normalized AS
(
    SELECT
        GAA_HIOS_ID,

        ROW_NUMBER() OVER
        (
            PARTITION BY
                GAA_HIOS_ID,
                exchgAssignedPolicyID,
                exchgIndivIdentifier,
                Insurance_Type,
                enrolleeStatus,
                memberMaintEffectiveDate
            ORDER BY
                GAA_834_File_Date DESC
        ) AS rn

    FROM dbo.[834_Inbound_test]

    WHERE Coverage_Year = 2025
      AND GAA_HIOS_ID IN (13535,15105,43802)
)

SELECT
    GAA_HIOS_ID,
    COUNT(*) AS RawRows,
    SUM(CASE WHEN rn=1 THEN 1 ELSE 0 END) AS AfterDedupe,
    COUNT(*)-SUM(CASE WHEN rn=1 THEN 1 ELSE 0 END) AS RemovedDuplicates
FROM normalized
GROUP BY GAA_HIOS_ID
ORDER BY GAA_HIOS_ID;

FROM normalized;
