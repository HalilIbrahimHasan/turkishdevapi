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
