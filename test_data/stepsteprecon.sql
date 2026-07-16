DECLARE @Year INT = 2025;   -- Change to 2026 for the next run

DROP TABLE IF EXISTS #base;
DROP TABLE IF EXISTS #latest_enrollment;
DROP TABLE IF EXISTS #latest_enrollee;

/* =========================================================
   1. Create a narrow working population for one coverage year
   ========================================================= */
SELECT
    issuer,

    CASE
        WHEN UPPER(insurance_type) IN ('HEALTH', 'HLT')
            THEN 'Health'
        WHEN UPPER(insurance_type) IN ('DENTAL', 'DEN')
            THEN 'Dental'
        ELSE insurance_type
    END AS insurance_type,

    coverage_year,

    COALESCE(
        NULLIF(policy_id, ''),
        NULLIF(health_coverage_policy_no, '')
    ) AS enrollment_key,

    COALESCE(
        NULLIF(member_id, ''),
        NULLIF(issuer_indiv_identifier, ''),
        NULLIF(exchg_assigned_enrollee_id, '')
    ) AS enrollee_key,

    UPPER(COALESCE(NULLIF(enrolleeStatus, ''), 'UNMAPPED'))
        AS latest_status,

    COALESCE(
        TRY_CONVERT(DATETIME2, member_maint_effective_date),
        TRY_CONVERT(DATETIME2, benefit_effective_date),
        loaded_at
    ) AS business_event_datetime,

    loaded_at,
    file_hash,
    row_number_in_file

INTO #base
FROM dbo.inbound_automation
WHERE folder_year = @Year
  AND coverage_year = @Year
  AND insurance_type IN ('Health', 'Dental')
  AND issuer IS NOT NULL;



/* =========================================================
   4. Final issuer-level annual summary
   ========================================================= */
WITH enrollment_summary AS (
    SELECT
        issuer,
        insurance_type,
        coverage_year,

        COUNT(*) AS [Our Enrollments Total],

        SUM(CASE WHEN latest_status = 'CONFIRM' THEN 1 ELSE 0 END)
            AS [Our Latest CONFIRM Enrollments],

        SUM(CASE WHEN latest_status = 'CANCEL' THEN 1 ELSE 0 END)
            AS [Our Latest CANCEL Enrollments],

        SUM(CASE WHEN latest_status = 'TERM' THEN 1 ELSE 0 END)
            AS [Our Latest TERM Enrollments],

        SUM(CASE
                WHEN latest_status NOT IN ('CONFIRM', 'CANCEL', 'TERM')
                THEN 1 ELSE 0
            END) AS [Our Latest UNMAPPED Enrollments]

    FROM #latest_enrollment
    GROUP BY
        issuer,
        insurance_type,
        coverage_year
),

enrollee_summary AS (
    SELECT
        issuer,
        insurance_type,
        coverage_year,

        COUNT(*) AS [Our Enrollees Total],

        SUM(CASE WHEN latest_status = 'CONFIRM' THEN 1 ELSE 0 END)
            AS [Our Latest CONFIRM Enrollees],

        SUM(CASE WHEN latest_status = 'CANCEL' THEN 1 ELSE 0 END)
            AS [Our Latest CANCEL Enrollees],

        SUM(CASE WHEN latest_status = 'TERM' THEN 1 ELSE 0 END)
            AS [Our Latest TERM Enrollees],

        SUM(CASE
                WHEN latest_status NOT IN ('CONFIRM', 'CANCEL', 'TERM')
                THEN 1 ELSE 0
            END) AS [Our Latest UNMAPPED Enrollees]

    FROM #latest_enrollee
    GROUP BY
        issuer,
        insurance_type,
        coverage_year
)

SELECT
    e.issuer AS [HIOS Issuer ID],
    e.insurance_type AS [Insurance Type],
    e.coverage_year AS [Coverage Year],

    e.[Our Enrollments Total],
    n.[Our Enrollees Total],

    e.[Our Latest CONFIRM Enrollments],
    n.[Our Latest CONFIRM Enrollees],

    e.[Our Latest CANCEL Enrollments],
    n.[Our Latest CANCEL Enrollees],

    e.[Our Latest TERM Enrollments],
    n.[Our Latest TERM Enrollees],

    e.[Our Latest UNMAPPED Enrollments],
    n.[Our Latest UNMAPPED Enrollees]

FROM enrollment_summary e
FULL OUTER JOIN enrollee_summary n
    ON n.issuer = e.issuer
   AND n.insurance_type = e.insurance_type
   AND n.coverage_year = e.coverage_year

ORDER BY
    [HIOS Issuer ID],
    [Insurance Type],
    [Coverage Year];
