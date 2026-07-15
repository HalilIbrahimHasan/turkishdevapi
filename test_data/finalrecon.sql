
SELECT
    issuer AS [HIOS Issuer ID],
    insurance_type AS [Insurance Type],
    coverage_year AS [Coverage Year],

    COUNT(DISTINCT COALESCE(
        NULLIF(policy_id, ''),
        NULLIF(health_coverage_policy_no, '')
    )) AS [Our Enrollments Total],

    COUNT(DISTINCT COALESCE(
        NULLIF(member_id, ''),
        NULLIF(issuer_indiv_identifier, ''),
        NULLIF(exchg_assigned_enrollee_id, '')
    )) AS [Our Enrollees Total],

    COUNT_BIG(*) AS [Our Raw Rows]

FROM dbo.inbound_automation
WHERE folder_year IN (2025, 2026)
  AND coverage_year IN (2025, 2026)
  AND insurance_type IN ('Health', 'Dental')
GROUP BY
    issuer,
    insurance_type,
    coverage_year
ORDER BY
    issuer,
    insurance_type,
    coverage_year;


SELECT
    issuer AS [HIOS Issuer ID],
    insurance_type AS [Insurance Type],
    coverage_year AS [Coverage Year],

    COUNT(DISTINCT COALESCE(
        NULLIF(policy_id, ''),
        NULLIF(health_coverage_policy_no, '')
    )) AS [Our Enrollments Total],

    COUNT(DISTINCT COALESCE(
        NULLIF(member_id, ''),
        NULLIF(issuer_indiv_identifier, ''),
        NULLIF(exchg_assigned_enrollee_id, '')
    )) AS [Our Enrollees Total],

    COUNT_BIG(*) AS [Our Raw Rows]

FROM dbo.inbound_automation
WHERE folder_year = 2025
  AND coverage_year = 2025
  AND insurance_type IN ('Health', 'Dental')
GROUP BY
    issuer,
    insurance_type,
    coverage_year
ORDER BY
    issuer,
    insurance_type;

=============================

WITH source_rows AS (
    SELECT
        LTRIM(RTRIM(issuer)) AS issuer,

        CASE
            WHEN UPPER(LTRIM(RTRIM(insurance_type))) IN ('HEALTH', 'HLT')
                THEN 'Health'
            WHEN UPPER(LTRIM(RTRIM(insurance_type))) IN ('DENTAL', 'DEN')
                THEN 'Dental'
            ELSE LTRIM(RTRIM(insurance_type))
        END AS insurance_type,

        coverage_year,

        COALESCE(
            NULLIF(LTRIM(RTRIM(policy_id)), ''),
            NULLIF(LTRIM(RTRIM(health_coverage_policy_no)), '')
        ) AS enrollment_key,

        COALESCE(
            NULLIF(LTRIM(RTRIM(member_id)), ''),
            NULLIF(LTRIM(RTRIM(issuer_indiv_identifier)), ''),
            NULLIF(LTRIM(RTRIM(exchg_assigned_enrollee_id)), '')
        ) AS enrollee_key

    FROM dbo.inbound_automation
    WHERE folder_year IN (2025, 2026)
)

SELECT
    issuer AS [HIOS Issuer ID],
    insurance_type AS [Insurance Type],
    coverage_year AS [Coverage Year],

    COUNT(DISTINCT enrollment_key)
        AS [Our Enrollments Total],

    COUNT(DISTINCT enrollee_key)
        AS [Our Enrollees Total],

    COUNT_BIG(*)
        AS [Our Raw Rows],

    SUM(CASE WHEN enrollment_key IS NULL THEN 1 ELSE 0 END)
        AS [Rows Missing Enrollment Key],

    SUM(CASE WHEN enrollee_key IS NULL THEN 1 ELSE 0 END)
        AS [Rows Missing Enrollee Key]

FROM source_rows
WHERE coverage_year IN (2025, 2026)
  AND issuer IS NOT NULL
  AND insurance_type IN ('Health', 'Dental')
GROUP BY
    issuer,
    insurance_type,
    coverage_year
ORDER BY
    issuer,
    insurance_type,
    coverage_year;



SELECT
    folder_year,
    COUNT_BIG(*) AS Raw_Row_Count,
    COUNT(DISTINCT file_hash) AS File_Count
FROM dbo.inbound_automation
WHERE folder_year IN (2025, 2026)
GROUP BY folder_year
ORDER BY folder_year;
