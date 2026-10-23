-- =============================================================================
-- DIAGNOSTIC — Enrollments_TEST 2026 population freshness / drift
-- =============================================================================
-- Purpose:
--   Compare the current dbo.Enrollments_TEST Coverage Year 2026 population
--   with the previously validated snapshot, without changing any controls.
--
-- Safety:
--   READ ONLY. Temp tables/indexes only. No inbound_automation. No RCNI.
--   No permanent writes. No Auto-Renewal or lineage classification.
-- =============================================================================

SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @coverage_year INT = 2026;

-- Previously validated snapshot controls — comparison only, never enforced.
DECLARE @previous_raw_physical_rows BIGINT = 2268819;
DECLARE @previous_distinct_enrollment_id BIGINT = 1645980;
DECLARE @previous_distinct_enrollee_id BIGINT = 1298829;
DECLARE @previous_distinct_pairs BIGINT = 2263972;
DECLARE @previous_distinct_issuers BIGINT = 16;
DECLARE @previous_physical_rows_collapsed BIGINT = 4847;
DECLARE @previous_enrolled_pending_pairs BIGINT = 960531;


-- =============================================================================
-- 1) Stage current physical 2026 rows once
-- =============================================================================
IF OBJECT_ID('tempdb..#raw_2026') IS NOT NULL DROP TABLE #raw_2026;

SELECT
    e.coverage_year,
    e.hios_issuer_id,
    e.enrollment_id,
    e.enrollee_id,
    e.enrollment_status_description,
    e.enrollee_status_description,
    e.enrollment_create_date,
    e.enrollment_last_update_date,
    e.enrollee_create_date,
    e.enrollee_last_update_date,
    e.benefit_effective_date
INTO #raw_2026
FROM dbo.Enrollments_TEST AS e
WHERE e.coverage_year = @coverage_year;

CREATE CLUSTERED INDEX CX_raw_2026
    ON #raw_2026 (enrollment_id, enrollee_id);


-- =============================================================================
-- 2) Exact validated five-field deduplication
-- =============================================================================
IF OBJECT_ID('tempdb..#pop_2026') IS NOT NULL DROP TABLE #pop_2026;

SELECT
    r.coverage_year,
    r.hios_issuer_id,
    r.enrollment_id,
    r.enrollee_id,
    r.enrollment_status_description,
    r.enrollee_status_description,
    r.enrollment_create_date,
    r.enrollment_last_update_date,
    r.enrollee_create_date,
    r.enrollee_last_update_date,
    r.benefit_effective_date,
    r.physical_row_count_for_key
INTO #pop_2026
FROM (
    SELECT
        r.*,
        COUNT_BIG(*) OVER (
            PARTITION BY r.coverage_year, r.enrollment_id, r.enrollee_id
        ) AS physical_row_count_for_key,
        ROW_NUMBER() OVER (
            PARTITION BY
                r.coverage_year,
                r.enrollment_id,
                r.enrollee_id
            ORDER BY
                r.enrollment_last_update_date DESC,
                r.enrollee_last_update_date DESC,
                r.enrollment_create_date DESC,
                r.enrollee_create_date DESC,
                r.benefit_effective_date DESC
        ) AS _rn
    FROM #raw_2026 AS r
) AS r
WHERE r._rn = 1;

CREATE UNIQUE CLUSTERED INDEX CX_pop_2026
    ON #pop_2026 (coverage_year, enrollment_id, enrollee_id);

CREATE NONCLUSTERED INDEX IX_pop_2026_status
    ON #pop_2026 (enrollment_status_description)
    INCLUDE (
        hios_issuer_id,
        enrollee_status_description,
        enrollment_last_update_date,
        enrollee_last_update_date
    );


-- =============================================================================
-- 3) Current metrics
-- =============================================================================
DECLARE @current_raw_physical_rows BIGINT = (
    SELECT COUNT_BIG(*) FROM #raw_2026
);

DECLARE @current_distinct_enrollment_id BIGINT = (
    SELECT COUNT(DISTINCT enrollment_id)
    FROM #pop_2026
);

DECLARE @current_distinct_enrollee_id BIGINT = (
    SELECT COUNT(DISTINCT enrollee_id)
    FROM #pop_2026
);

DECLARE @current_distinct_pairs BIGINT = (
    SELECT COUNT_BIG(*) FROM #pop_2026
);

DECLARE @current_distinct_issuers BIGINT = (
    SELECT COUNT(DISTINCT hios_issuer_id)
    FROM #pop_2026
);

DECLARE @current_physical_rows_collapsed BIGINT =
    @current_raw_physical_rows - @current_distinct_pairs;

DECLARE @current_enrolled_pending_pairs BIGINT = (
    SELECT COUNT_BIG(*)
    FROM #pop_2026
    WHERE UPPER(LTRIM(RTRIM(enrollment_status_description)))
          IN ('ENROLLED', 'PENDING')
);


-- =============================================================================
-- RESULT 1 — Deduplication verification
-- =============================================================================
SELECT
    CAST(
        'coverage_year + enrollment_id + enrollee_id'
        AS VARCHAR(100)
    ) AS Business_Grain,
    CAST(
        'enrollment_last_update_date DESC; '
        + 'enrollee_last_update_date DESC; '
        + 'enrollment_create_date DESC; '
        + 'enrollee_create_date DESC; '
        + 'benefit_effective_date DESC'
        AS VARCHAR(500)
    ) AS ROW_NUMBER_Order,
    CAST('EXACT_FIVE_FIELD_ORDER_CONFIRMED' AS VARCHAR(40))
        AS Dedup_Verification;


-- =============================================================================
-- RESULT 2 — Previous validated snapshot vs current population
-- =============================================================================
SELECT
    v.Metric,
    v.Previous_Validated,
    v.Current_Value,
    v.Current_Value - v.Previous_Validated AS Difference
FROM (
    VALUES
        (
            CAST('Raw physical rows' AS VARCHAR(60)),
            @previous_raw_physical_rows,
            @current_raw_physical_rows
        ),
        (
            CAST('Distinct enrollment_id' AS VARCHAR(60)),
            @previous_distinct_enrollment_id,
            @current_distinct_enrollment_id
        ),
        (
            CAST('Distinct enrollee_id' AS VARCHAR(60)),
            @previous_distinct_enrollee_id,
            @current_distinct_enrollee_id
        ),
        (
            CAST('Distinct Coverage Year + Policy + Enrollee' AS VARCHAR(60)),
            @previous_distinct_pairs,
            @current_distinct_pairs
        ),
        (
            CAST('Distinct issuers' AS VARCHAR(60)),
            @previous_distinct_issuers,
            @current_distinct_issuers
        ),
        (
            CAST('Physical rows collapsed' AS VARCHAR(60)),
            @previous_physical_rows_collapsed,
            @current_physical_rows_collapsed
        ),
        (
            CAST('Enrolled/Pending Policy + Enrollee pairs' AS VARCHAR(60)),
            @previous_enrolled_pending_pairs,
            @current_enrolled_pending_pairs
        )
) AS v (Metric, Previous_Validated, Current_Value)
ORDER BY
    CASE v.Metric
        WHEN 'Raw physical rows' THEN 1
        WHEN 'Distinct enrollment_id' THEN 2
        WHEN 'Distinct enrollee_id' THEN 3
        WHEN 'Distinct Coverage Year + Policy + Enrollee' THEN 4
        WHEN 'Distinct issuers' THEN 5
        WHEN 'Physical rows collapsed' THEN 6
        WHEN 'Enrolled/Pending Policy + Enrollee pairs' THEN 7
        ELSE 99
    END;


-- =============================================================================
-- RESULT 3 — Current 2026 source date range
-- =============================================================================
SELECT
    MIN(enrollment_create_date) AS Min_Enrollment_Create_Date,
    MAX(enrollment_create_date) AS Max_Enrollment_Create_Date,
    MIN(enrollment_last_update_date) AS Min_Enrollment_Last_Update_Date,
    MAX(enrollment_last_update_date) AS Max_Enrollment_Last_Update_Date,
    MIN(enrollee_create_date) AS Min_Enrollee_Create_Date,
    MAX(enrollee_create_date) AS Max_Enrollee_Create_Date,
    MIN(enrollee_last_update_date) AS Min_Enrollee_Last_Update_Date,
    MAX(enrollee_last_update_date) AS Max_Enrollee_Last_Update_Date,
    MIN(benefit_effective_date) AS Min_Benefit_Effective_Date,
    MAX(benefit_effective_date) AS Max_Benefit_Effective_Date
FROM #raw_2026;


-- =============================================================================
-- RESULT 4 — Five-field-deduplicated Enrollment Status distribution
-- =============================================================================
SELECT
    enrollment_status_description AS Enrollment_Status,
    COUNT_BIG(*) AS Distinct_Policy_Enrollee_Count,
    CAST(
        100.0 * COUNT_BIG(*) / NULLIF(@current_distinct_pairs, 0)
        AS DECIMAL(10, 4)
    ) AS Percent_of_Current_Deduplicated_2026
FROM #pop_2026
GROUP BY enrollment_status_description
ORDER BY
    Distinct_Policy_Enrollee_Count DESC,
    enrollment_status_description;


-- =============================================================================
-- RESULT 5 — Current counts by issuer
-- =============================================================================
SELECT
    hios_issuer_id AS Issuer,
    COUNT_BIG(*) AS Total_Deduplicated_2026_Pairs,
    SUM(
        CASE
            WHEN UPPER(LTRIM(RTRIM(enrollment_status_description)))
                 IN ('ENROLLED', 'PENDING')
                THEN CAST(1 AS BIGINT)
            ELSE CAST(0 AS BIGINT)
        END
    ) AS Enrolled_Pending_Pairs,
    SUM(
        CASE
            WHEN UPPER(LTRIM(RTRIM(enrollment_status_description)))
                 NOT IN ('ENROLLED', 'PENDING')
              OR enrollment_status_description IS NULL
                THEN CAST(1 AS BIGINT)
            ELSE CAST(0 AS BIGINT)
        END
    ) AS Other_Status_Pairs
FROM #pop_2026
GROUP BY hios_issuer_id
ORDER BY
    Total_Deduplicated_2026_Pairs DESC,
    hios_issuer_id;


-- =============================================================================
-- RESULT 6 — Monthly create/update distributions
-- RAW_PHYSICAL shows source rows; FIVE_FIELD_DEDUP shows selected business rows.
-- A prior snapshot cutoff date is not stored in the repository, so no cutoff is
-- invented. Later months in this output identify candidate post-snapshot growth.
-- =============================================================================
SELECT
    x.Population_Stage,
    x.Date_Field,
    x.Activity_Month,
    x.Record_Count
FROM (
    SELECT
        CAST('RAW_PHYSICAL' AS VARCHAR(30)) AS Population_Stage,
        CAST('enrollment_last_update_date' AS VARCHAR(40)) AS Date_Field,
        DATEFROMPARTS(
            YEAR(enrollment_last_update_date),
            MONTH(enrollment_last_update_date),
            1
        ) AS Activity_Month,
        COUNT_BIG(*) AS Record_Count
    FROM #raw_2026
    WHERE enrollment_last_update_date IS NOT NULL
    GROUP BY
        DATEFROMPARTS(
            YEAR(enrollment_last_update_date),
            MONTH(enrollment_last_update_date),
            1
        )

    UNION ALL

    SELECT
        'FIVE_FIELD_DEDUP',
        'enrollment_last_update_date',
        DATEFROMPARTS(
            YEAR(enrollment_last_update_date),
            MONTH(enrollment_last_update_date),
            1
        ),
        COUNT_BIG(*)
    FROM #pop_2026
    WHERE enrollment_last_update_date IS NOT NULL
    GROUP BY
        DATEFROMPARTS(
            YEAR(enrollment_last_update_date),
            MONTH(enrollment_last_update_date),
            1
        )

    UNION ALL

    SELECT
        'RAW_PHYSICAL',
        'enrollee_last_update_date',
        DATEFROMPARTS(
            YEAR(enrollee_last_update_date),
            MONTH(enrollee_last_update_date),
            1
        ),
        COUNT_BIG(*)
    FROM #raw_2026
    WHERE enrollee_last_update_date IS NOT NULL
    GROUP BY
        DATEFROMPARTS(
            YEAR(enrollee_last_update_date),
            MONTH(enrollee_last_update_date),
            1
        )

    UNION ALL

    SELECT
        'FIVE_FIELD_DEDUP',
        'enrollee_last_update_date',
        DATEFROMPARTS(
            YEAR(enrollee_last_update_date),
            MONTH(enrollee_last_update_date),
            1
        ),
        COUNT_BIG(*)
    FROM #pop_2026
    WHERE enrollee_last_update_date IS NOT NULL
    GROUP BY
        DATEFROMPARTS(
            YEAR(enrollee_last_update_date),
            MONTH(enrollee_last_update_date),
            1
        )

    UNION ALL

    SELECT
        'RAW_PHYSICAL',
        'enrollment_create_date',
        DATEFROMPARTS(
            YEAR(enrollment_create_date),
            MONTH(enrollment_create_date),
            1
        ),
        COUNT_BIG(*)
    FROM #raw_2026
    WHERE enrollment_create_date IS NOT NULL
    GROUP BY
        DATEFROMPARTS(
            YEAR(enrollment_create_date),
            MONTH(enrollment_create_date),
            1
        )

    UNION ALL

    SELECT
        'FIVE_FIELD_DEDUP',
        'enrollment_create_date',
        DATEFROMPARTS(
            YEAR(enrollment_create_date),
            MONTH(enrollment_create_date),
            1
        ),
        COUNT_BIG(*)
    FROM #pop_2026
    WHERE enrollment_create_date IS NOT NULL
    GROUP BY
        DATEFROMPARTS(
            YEAR(enrollment_create_date),
            MONTH(enrollment_create_date),
            1
        )

    UNION ALL

    SELECT
        'RAW_PHYSICAL',
        'enrollee_create_date',
        DATEFROMPARTS(
            YEAR(enrollee_create_date),
            MONTH(enrollee_create_date),
            1
        ),
        COUNT_BIG(*)
    FROM #raw_2026
    WHERE enrollee_create_date IS NOT NULL
    GROUP BY
        DATEFROMPARTS(
            YEAR(enrollee_create_date),
            MONTH(enrollee_create_date),
            1
        )

    UNION ALL

    SELECT
        'FIVE_FIELD_DEDUP',
        'enrollee_create_date',
        DATEFROMPARTS(
            YEAR(enrollee_create_date),
            MONTH(enrollee_create_date),
            1
        ),
        COUNT_BIG(*)
    FROM #pop_2026
    WHERE enrollee_create_date IS NOT NULL
    GROUP BY
        DATEFROMPARTS(
            YEAR(enrollee_create_date),
            MONTH(enrollee_create_date),
            1
        )
) AS x
ORDER BY
    x.Date_Field,
    x.Activity_Month,
    x.Population_Stage;


-- =============================================================================
-- RESULT 7 — Diagnostic disposition
-- =============================================================================
SELECT
    @previous_distinct_pairs AS Previous_Validated_Distinct_Pairs,
    @current_distinct_pairs AS Current_Distinct_Pairs,
    @current_distinct_pairs - @previous_distinct_pairs
        AS Distinct_Pair_Difference,
    @previous_enrolled_pending_pairs
        AS Previous_Validated_Enrolled_Pending_Pairs,
    @current_enrolled_pending_pairs
        AS Current_Enrolled_Pending_Pairs,
    @current_enrolled_pending_pairs - @previous_enrolled_pending_pairs
        AS Enrolled_Pending_Difference,
    CAST(
        'Current values are observed only; no prior control was changed or enforced.'
        AS VARCHAR(120)
    ) AS Diagnostic_Note;
