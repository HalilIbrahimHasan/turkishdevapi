SELECT
    coverage_year AS Coverage_Year,
    hios_issuer_id AS GAA_HIOS_ID,
    DATEFROMPARTS(coverage_year, 6, 1) AS GAA_Load_Date,
    Insurance_Type,

    CASE
        WHEN enrollment_status_description = 'Enrolled' THEN 1
        WHEN enrollment_status_description = 'Cancelled' THEN 2
        WHEN enrollment_status_description = 'Terminated' THEN 3
    END AS status_Id,

    CASE
        WHEN enrollment_status_description = 'Enrolled' THEN 'CONFIRM'
        WHEN enrollment_status_description = 'Cancelled' THEN 'CANCEL'
        WHEN enrollment_status_description = 'Terminated' THEN 'TERM'
    END AS enrolleeStatus,

    COUNT(DISTINCT enrollment_id) AS Enrollment_Count,
    COUNT(DISTINCT enrollee_id) AS Enrollee_Count

FROM dbo.Enrollments_TEST

WHERE coverage_year = 2025
  AND MONTH(GAA_Load_Datetime) = 6
  AND enrollment_status_description IN
      ('Enrolled','Cancelled','Terminated')

GROUP BY
    coverage_year,
    hios_issuer_id,
    Insurance_Type,
    enrollment_status_description

ORDER BY
    hios_issuer_id,
    Insurance_Type,
    status_Id;


=========

SELECT
    enrollment_status_description,
    enrollee_status_description,
    COUNT(*) AS Record_Count
FROM dbo.Enrollments_TEST
WHERE coverage_year = 2025
  AND MONTH(GAA_Load_Datetime) = 6
GROUP BY
    enrollment_status_description,
    enrollee_status_description
ORDER BY
    Record_Count DESC;
