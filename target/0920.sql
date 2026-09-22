-- =============================================================================
-- COMPLETE 2026 ENROLLMENT POPULATION DIAGNOSTIC
-- Source: dbo.Enrollments_TEST ONLY
-- =============================================================================
-- Purpose:
--   Establish the full coverage_year = 2026 universe BEFORE any business
--   status filter and BEFORE any 834 / inbound matching.
--
-- Unique business grain:
--   coverage_year + enrollment_id + enrollee_id
--
-- Dedup rule:
--   Keep the latest physical row per grain using available update/create
--   timestamps (enrollment then enrollee).
--
-- Safety:
--   READ ONLY. Temp tables only. No inbound_automation. No RCNI.
--   No permanent DDL/DML. Do not assume 960,531.
-- =============================================================================

SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @coverage_year INT = 2026;


-- =============================================================================
-- 0) Build deduplicated 2026 population (one row per Policy + Enrollee)
-- =============================================================================
IF OBJECT_ID('tempdb..#pop_2026') IS NOT NULL DROP TABLE #pop_2026;

SELECT
    e.coverage_year,
    e.hios_issuer_id,
    e.enrollment_id,
    e.enrollee_id,
    e.enrollment_status_description,
    e.enrollee_status_description,
    /* Enrollments_TEST exposes a single benefit start/end pair on the row */
    e.benefit_effective_date AS enrollment_benefit_start_date,
    e.benefit_end_date       AS enrollment_benefit_end_date,
    e.benefit_effective_date AS enrollee_benefit_start_date,
    e.benefit_end_date       AS enrollee_benefit_end_date,
    e.household_id,
    e.enrollment_create_date,
    e.enrollment_last_update_date,
    e.enrollee_create_date,
    e.enrollee_last_update_date,
    e.physical_row_count_for_key
INTO #pop_2026
FROM (
    SELECT
        e.coverage_year,
        e.hios_issuer_id,
        e.enrollment_id,
        e.enrollee_id,
        e.enrollment_status_description,
        e.enrollee_status_description,
        e.benefit_effective_date,
        e.benefit_end_date,
        e.household_id,
        e.enrollment_create_date,
        e.enrollment_last_update_date,
        e.enrollee_create_date,
        e.enrollee_last_update_date,
        COUNT(*) OVER (
            PARTITION BY e.coverage_year, e.enrollment_id, e.enrollee_id
        ) AS physical_row_count_for_key,
        ROW_NUMBER() OVER (
            PARTITION BY e.coverage_year, e.enrollment_id, e.enrollee_id
            ORDER BY
                e.enrollment_last_update_date DESC,
                e.enrollee_last_update_date DESC,
                e.enrollment_create_date DESC,
                e.enrollee_create_date DESC,
                e.benefit_effective_date DESC
        ) AS _rn
    FROM dbo.Enrollments_TEST AS e
    WHERE e.coverage_year = @coverage_year
) AS e
WHERE e._rn = 1;

CREATE UNIQUE CLUSTERED INDEX CX_pop_2026
    ON #pop_2026 (coverage_year, enrollment_id, enrollee_id);

CREATE NONCLUSTERED INDEX IX_pop_2026_status
    ON #pop_2026 (enrollment_status_description)
    INCLUDE (hios_issuer_id, enrollee_status_description);

DECLARE @raw_physical_rows           BIGINT;
DECLARE @distinct_pairs              BIGINT;
DECLARE @distinct_enrollment_id      BIGINT;
DECLARE @distinct_enrollee_id        BIGINT;
DECLARE @distinct_issuers            BIGINT;
DECLARE @enrolled_pending_pairs      BIGINT;
DECLARE @physical_rows_collapsed     BIGINT;

SELECT @raw_physical_rows = COUNT(*)
FROM dbo.Enrollments_TEST
WHERE coverage_year = @coverage_year;

SELECT
    @distinct_pairs         = COUNT(*),
    @distinct_enrollment_id = COUNT(DISTINCT enrollment_id),
    @distinct_enrollee_id   = COUNT(DISTINCT enrollee_id),
    @distinct_issuers       = COUNT(DISTINCT hios_issuer_id),
    @physical_rows_collapsed = SUM(CASE WHEN physical_row_count_for_key > 1 THEN physical_row_count_for_key - 1 ELSE 0 END)
FROM #pop_2026;

SELECT @enrolled_pending_pairs = COUNT(*)
FROM #pop_2026
WHERE UPPER(LTRIM(RTRIM(enrollment_status_description))) IN ('ENROLLED', 'PENDING');


-- =============================================================================
-- RESULT 1 – Overall 2026 controls
-- =============================================================================
SELECT
    @coverage_year AS coverage_year,
    @raw_physical_rows AS raw_physical_row_count,
    @distinct_enrollment_id AS distinct_enrollment_id,
    @distinct_enrollee_id AS distinct_enrollee_id,
    @distinct_pairs AS distinct_coverage_year_enrollment_id_enrollee_id_pairs,
    @distinct_issuers AS number_of_issuers,
    @physical_rows_collapsed AS physical_rows_collapsed_by_dedup,
    @enrolled_pending_pairs AS enrolled_pending_distinct_pairs_independent_check,
    CASE
        WHEN @distinct_pairs > 0 THEN 'OK'
        ELSE 'EMPTY_POPULATION'
    END AS control_status;


-- =============================================================================
-- RESULT 2 – Status distribution (distinct Policy + Enrollee population)
-- =============================================================================
SELECT
    enrollment_status_description,
    enrollee_status_description,
    COUNT(*) AS distinct_pair_count,
    CAST(
        100.0 * COUNT(*) / NULLIF(@distinct_pairs, 0)
        AS DECIMAL(10, 4)
    ) AS pct_of_total_2026_distinct_population
FROM #pop_2026
GROUP BY
    enrollment_status_description,
    enrollee_status_description
ORDER BY
    distinct_pair_count DESC,
    enrollment_status_description,
    enrollee_status_description;


-- =============================================================================
-- RESULT 3 – Enrollment status summary
-- =============================================================================
SELECT
    enrollment_status_description,
    COUNT(*) AS distinct_policy_enrollee_count,
    CAST(
        100.0 * COUNT(*) / NULLIF(@distinct_pairs, 0)
        AS DECIMAL(10, 4)
    ) AS pct_of_total_2026_distinct_population
FROM #pop_2026
GROUP BY enrollment_status_description
ORDER BY distinct_policy_enrollee_count DESC, enrollment_status_description;


-- =============================================================================
-- RESULT 4 – Issuer / status summary
-- =============================================================================
SELECT
    hios_issuer_id,
    COUNT(*) AS total_distinct_2026_policy_enrollee_pairs,
    SUM(CASE
            WHEN UPPER(LTRIM(RTRIM(enrollment_status_description))) = 'ENROLLED'
            THEN 1 ELSE 0
        END) AS enrolled_count,
    SUM(CASE
            WHEN UPPER(LTRIM(RTRIM(enrollment_status_description))) = 'PENDING'
            THEN 1 ELSE 0
        END) AS pending_count,
    SUM(CASE
            WHEN UPPER(LTRIM(RTRIM(enrollment_status_description))) NOT IN ('ENROLLED', 'PENDING')
              OR enrollment_status_description IS NULL
            THEN 1 ELSE 0
        END) AS all_other_status_count
FROM #pop_2026
GROUP BY hios_issuer_id
ORDER BY total_distinct_2026_policy_enrollee_pairs DESC, hios_issuer_id;


-- =============================================================================
-- RESULT 5 – Full deduplicated 2026 population
-- One row per coverage_year + enrollment_id + enrollee_id
-- =============================================================================
SELECT
    coverage_year,
    hios_issuer_id,
    enrollment_id,
    enrollee_id,
    enrollment_status_description,
    enrollee_status_description,
    enrollment_benefit_start_date,
    enrollment_benefit_end_date,
    enrollee_benefit_start_date,
    enrollee_benefit_end_date,
    household_id,
    enrollment_create_date,
    enrollment_last_update_date,
    enrollee_create_date,
    enrollee_last_update_date,
    physical_row_count_for_key
FROM #pop_2026
ORDER BY
    hios_issuer_id,
    enrollment_id,
    enrollee_id;


-- =============================================================================
-- RESULT 6 – Independent Enrolled/Pending subset validation
-- (after complete population; do NOT hard-code 960,531)
-- =============================================================================
SELECT
    'enrollment_status_description IN (Enrolled, Pending)' AS filter_definition,
    @distinct_pairs AS complete_2026_distinct_pairs,
    @enrolled_pending_pairs AS enrolled_pending_distinct_pairs,
    (@distinct_pairs - @enrolled_pending_pairs) AS complete_minus_enrolled_pending,
    CAST(
        100.0 * @enrolled_pending_pairs / NULLIF(@distinct_pairs, 0)
        AS DECIMAL(10, 4)
    ) AS pct_of_complete_2026_population;
