DECLARE @Year INT = 2025;

;WITH base AS (
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
        ) AS enrollee_key,

        UPPER(
            COALESCE(
                NULLIF(LTRIM(RTRIM(enrolleeStatus)), ''),
                'UNMAPPED'
            )
        ) AS latest_status,

        COALESCE(
            TRY_CONVERT(DATETIME2, member_maint_effective_date),
            TRY_CONVERT(DATETIME2, benefit_effective_date),
            loaded_at
        ) AS business_event_datetime,

        loaded_at,
        file_hash,
        row_number_in_file

    FROM dbo.inbound_automation
    WHERE folder_year = @Year
      AND coverage_year = @Year
      AND insurance_type IN ('Health', 'Dental')
      AND issuer IS NOT NULL
),

ranked_enrollment AS (
    SELECT
        *,
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
    FROM base
    WHERE enrollment_key IS NOT NULL
),

latest_enrollment AS (
    SELECT *
    FROM ranked_enrollment
    WHERE rn = 1
),

ranked_enrollee AS (
    SELECT
        *,
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
    FROM base
    WHERE enrollment_key IS NOT NULL
      AND enrollee_key IS NOT NULL
),

latest_enrollee AS (
    SELECT *
    FROM ranked_enrollee
    WHERE rn = 1
),

enrollment_summary AS (
    SELECT
        issuer,
        insurance_type,
        coverage_year,

        COUNT_BIG(*) AS enrollments_total,

        SUM(CASE
                WHEN latest_status = 'CONFIRM'
                THEN 1 ELSE 0
            END) AS confirm_enrollments,

        SUM(CASE
                WHEN latest_status <> 'CONFIRM'
                THEN 1 ELSE 0
            END) AS non_confirm_enrollments,

        SUM(CASE
                WHEN latest_status = 'CANCEL'
                THEN 1 ELSE 0
            END) AS cancel_enrollments,

        SUM(CASE
                WHEN latest_status = 'TERM'
                THEN 1 ELSE 0
            END) AS term_enrollments,

        SUM(CASE
                WHEN latest_status NOT IN ('CONFIRM', 'CANCEL', 'TERM')
                THEN 1 ELSE 0
            END) AS unmapped_enrollments

    FROM latest_enrollment
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

        COUNT_BIG(*) AS enrollees_total,

        SUM(CASE
                WHEN latest_status = 'CONFIRM'
                THEN 1 ELSE 0
            END) AS confirm_enrollees,

        SUM(CASE
                WHEN latest_status <> 'CONFIRM'
                THEN 1 ELSE 0
            END) AS non_confirm_enrollees,

        SUM(CASE
                WHEN latest_status = 'CANCEL'
                THEN 1 ELSE 0
            END) AS cancel_enrollees,

        SUM(CASE
                WHEN latest_status = 'TERM'
                THEN 1 ELSE 0
            END) AS term_enrollees,

        SUM(CASE
                WHEN latest_status NOT IN ('CONFIRM', 'CANCEL', 'TERM')
                THEN 1 ELSE 0
            END) AS unmapped_enrollees

    FROM latest_enrollee
    GROUP BY
        issuer,
        insurance_type,
        coverage_year
)

SELECT
    COALESCE(e.issuer, n.issuer)
        AS [HIOS Issuer ID],

    COALESCE(e.insurance_type, n.insurance_type)
        AS [Insurance Type],

    COALESCE(e.coverage_year, n.coverage_year)
        AS [Coverage Year],

    e.enrollments_total
        AS [Enrollments Total],

    n.enrollees_total
        AS [Enrollees Total],

    /* Same display position as Sisense Effectuated,
       but intentionally labeled CONFIRM */
    e.confirm_enrollments
        AS [Latest CONFIRM Enrollments],

    n.confirm_enrollees
        AS [Latest CONFIRM Enrollees],

    /* Same display position as Sisense Pending,
       but intentionally labeled Non-CONFIRM */
    e.non_confirm_enrollments
        AS [Latest Non-CONFIRM Enrollments],

    n.non_confirm_enrollees
        AS [Latest Non-CONFIRM Enrollees],

    /* Additional diagnostics */
    e.cancel_enrollments
        AS [Latest CANCEL Enrollments],

    n.cancel_enrollees
        AS [Latest CANCEL Enrollees],

    e.term_enrollments
        AS [Latest TERM Enrollments],

    n.term_enrollees
        AS [Latest TERM Enrollees],

    e.unmapped_enrollments
        AS [Latest UNMAPPED Enrollments],

    n.unmapped_enrollees
        AS [Latest UNMAPPED Enrollees]

FROM enrollment_summary e
FULL OUTER JOIN enrollee_summary n
    ON n.issuer = e.issuer
   AND n.insurance_type = e.insurance_type
   AND n.coverage_year = e.coverage_year

ORDER BY
    [HIOS Issuer ID],
    [Insurance Type],
    [Coverage Year];
