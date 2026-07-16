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

=================


/* =========================================================
   2. Latest state per enrollment
   ========================================================= */

DROP TABLE IF EXISTS #latest_enrollment;

;WITH ranked_enrollment AS (
    SELECT
        issuer,
        insurance_type,
        coverage_year,
        enrollment_key,
        enrollee_key,
        latest_status,
        business_event_datetime,
        loaded_at,
        file_hash,
        row_number_in_file,

        ROW_NUMBER() OVER (
            PARTITION BY
                issuer,
                insurance_type,
                coverage_year,
                enrollment_key
            ORDER BY
                business_event_datetime DESC,
                loaded_at DESC,
                file_hash DESC,
                row_number_in_file DESC
        ) AS rn
    FROM #base
    WHERE enrollment_key IS NOT NULL
)
SELECT
    issuer,
    insurance_type,
    coverage_year,
    enrollment_key,
    enrollee_key,
    latest_status,
    business_event_datetime,
    loaded_at,
    file_hash,
    row_number_in_file
INTO #latest_enrollment
FROM ranked_enrollment
WHERE rn = 1;


/* =========================================================
   3. Latest state per enrollee
   ========================================================= */

DROP TABLE IF EXISTS #latest_enrollee;

;WITH ranked_enrollee AS (
    SELECT
        issuer,
        insurance_type,
        coverage_year,
        enrollment_key,
        enrollee_key,
        latest_status,
        business_event_datetime,
        loaded_at,
        file_hash,
        row_number_in_file,

        ROW_NUMBER() OVER (
            PARTITION BY
                issuer,
                insurance_type,
                coverage_year,
                enrollment_key,
                enrollee_key
            ORDER BY
                business_event_datetime DESC,
                loaded_at DESC,
                file_hash DESC,
                row_number_in_file DESC
        ) AS rn
    FROM #base
    WHERE enrollment_key IS NOT NULL
      AND enrollee_key IS NOT NULL
)
SELECT
    issuer,
    insurance_type,
    coverage_year,
    enrollment_key,
    enrollee_key,
    latest_status,
    business_event_datetime,
    loaded_at,
    file_hash,
    row_number_in_file
INTO #latest_enrollee
FROM ranked_enrollee
WHERE rn = 1;


/* =========================================================
   4. Final issuer-level annual summary
   ========================================================= */

;WITH enrollment_summary AS (
    SELECT
        issuer,
        insurance_type,
        coverage_year,

        COUNT_BIG(*) AS enrollment_total,

        SUM(CASE
                WHEN latest_status = 'CONFIRM' THEN 1
                ELSE 0
            END) AS confirm_enrollments,

        SUM(CASE
                WHEN latest_status = 'CANCEL' THEN 1
                ELSE 0
            END) AS cancel_enrollments,

        SUM(CASE
                WHEN latest_status = 'TERM' THEN 1
                ELSE 0
            END) AS term_enrollments,

        SUM(CASE
                WHEN latest_status NOT IN ('CONFIRM', 'CANCEL', 'TERM')
                     OR latest_status IS NULL
                THEN 1
                ELSE 0
            END) AS unmapped_enrollments

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

        COUNT_BIG(*) AS enrollee_total,

        SUM(CASE
                WHEN latest_status = 'CONFIRM' THEN 1
                ELSE 0
            END) AS confirm_enrollees,

        SUM(CASE
                WHEN latest_status = 'CANCEL' THEN 1
                ELSE 0
            END) AS cancel_enrollees,

        SUM(CASE
                WHEN latest_status = 'TERM' THEN 1
                ELSE 0
            END) AS term_enrollees,

        SUM(CASE
                WHEN latest_status NOT IN ('CONFIRM', 'CANCEL', 'TERM')
                     OR latest_status IS NULL
                THEN 1
                ELSE 0
            END) AS unmapped_enrollees

    FROM #latest_enrollee
    GROUP BY
        issuer,
        insurance_type,
        coverage_year
)

SELECT
    COALESCE(e.issuer, n.issuer) AS [HIOS Issuer ID],
    COALESCE(e.insurance_type, n.insurance_type) AS [Insurance Type],
    COALESCE(e.coverage_year, n.coverage_year) AS [Coverage Year],

    e.enrollment_total AS [Our Enrollments Total],
    n.enrollee_total AS [Our Enrollees Total],

    e.confirm_enrollments AS [Latest CONFIRM Enrollments],
    n.confirm_enrollees AS [Latest CONFIRM Enrollees],

    e.cancel_enrollments AS [Latest CANCEL Enrollments],
    n.cancel_enrollees AS [Latest CANCEL Enrollees],

    e.term_enrollments AS [Latest TERM Enrollments],
    n.term_enrollees AS [Latest TERM Enrollees],

    e.unmapped_enrollments AS [Latest UNMAPPED Enrollments],
    n.unmapped_enrollees AS [Latest UNMAPPED Enrollees]

FROM enrollment_summary e
FULL OUTER JOIN enrollee_summary n
    ON n.issuer = e.issuer
   AND n.insurance_type = e.insurance_type
   AND n.coverage_year = e.coverage_year

ORDER BY
    [HIOS Issuer ID],
    [Insurance Type],
    [Coverage Year];


SELECT COUNT(*) AS base_rows FROM #base;
SELECT COUNT(*) AS latest_enrollment_rows FROM #latest_enrollment;
SELECT COUNT(*) AS latest_enrollee_rows FROM #latest_enrollee;
