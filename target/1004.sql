-- =============================================================================
-- PREMIUM PROFILE — VALIDATED 2026 NO_INBOUND_ENROLLEE_EVIDENCE
-- =============================================================================
-- COMPONENT A:
--   Exact complete-2026 population and five-field deduplication from:
--   sql/enrollments_2026_complete_population_diagnostic.sql
--
-- COMPONENT B:
--   Validated NO_INBOUND_ENROLLEE_EVIDENCE definition:
--   search all inbound history and independently test all three inbound
--   enrollee identifier fields. No policy, issuer, status, or year restriction.
--
-- COMPONENT C:
--   Premium enrichment with dbo.Enrollments_TEST.net_premium_amt only after
--   the complete population, FFM target, and NO_INBOUND controls pass.
--
-- Safety:
--   READ ONLY on permanent tables. Temp tables/indexes only.
--   No RCNI. No Auto-Renewal analysis. No permanent writes.
-- =============================================================================

SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @coverage_year INT = 2026;
DECLARE @expected_complete_2026 BIGINT = 2263972;
DECLARE @expected_ffm_target BIGINT = 960531;
DECLARE @expected_no_inbound BIGINT = 109776;

DECLARE @t0 DATETIME2 = SYSDATETIME();
DECLARE @msg NVARCHAR(400);


-- =============================================================================
-- COMPONENT A1 — COMPLETE 2026 DEDUPLICATED POPULATION
-- Exact logic from enrollments_2026_complete_population_diagnostic.sql
-- =============================================================================
RAISERROR('PREMIUM PROFILE A1: build complete deduplicated 2026 population', 10, 1) WITH NOWAIT;

IF OBJECT_ID('tempdb..#pop_2026') IS NOT NULL DROP TABLE #pop_2026;

SELECT
    e.coverage_year,
    e.hios_issuer_id,
    e.enrollment_id,
    e.enrollee_id,
    e.enrollment_status_description,
    e.enrollee_status_description,
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

DECLARE @complete_2026_distinct_pairs BIGINT = (
    SELECT COUNT_BIG(*) FROM #pop_2026
);

SET @msg = CONCAT(
    'PREMIUM PROFILE A1 complete: COMPLETE_2026_DISTINCT_PAIRS=',
    @complete_2026_distinct_pairs,
    '; elapsed_s=', DATEDIFF(second, @t0, SYSDATETIME())
);
RAISERROR(@msg, 10, 1) WITH NOWAIT;

IF @complete_2026_distinct_pairs <> @expected_complete_2026
BEGIN
    RAISERROR(
        'STOP: COMPLETE_2026_DISTINCT_PAIRS=%I64d; expected %I64d.',
        16, 1,
        @complete_2026_distinct_pairs,
        @expected_complete_2026
    );
    RETURN;
END;


-- =============================================================================
-- COMPONENT A2 — 2026 FFM ENROLLED/PENDING TARGET
-- Filter only after complete-2026 deduplication. Do not filter enrollee status.
-- =============================================================================
RAISERROR('PREMIUM PROFILE A2: filter validated FFM target', 10, 1) WITH NOWAIT;

IF OBJECT_ID('tempdb..#ffm_target') IS NOT NULL DROP TABLE #ffm_target;

SELECT
    p.coverage_year AS FFM_Coverage_Year,
    CAST(p.hios_issuer_id AS VARCHAR(20)) AS FFM_Issuer,
    CAST(p.enrollment_id AS VARCHAR(100)) AS FFM_Policy_ID,
    CAST(p.enrollee_id AS VARCHAR(100)) AS FFM_Enrollee_ID,
    p.enrollment_status_description AS FFM_Enrollment_Status,
    p.enrollee_status_description AS FFM_Enrollee_Status
INTO #ffm_target
FROM #pop_2026 AS p
WHERE UPPER(LTRIM(RTRIM(p.enrollment_status_description)))
      IN ('ENROLLED', 'PENDING');

CREATE UNIQUE CLUSTERED INDEX CX_ffm_target
    ON #ffm_target (
        FFM_Coverage_Year,
        FFM_Policy_ID,
        FFM_Enrollee_ID
    );

CREATE NONCLUSTERED INDEX IX_ffm_target_enrollee
    ON #ffm_target (FFM_Enrollee_ID)
    INCLUDE (
        FFM_Issuer,
        FFM_Policy_ID,
        FFM_Enrollment_Status,
        FFM_Enrollee_Status
    );

DECLARE @ffm_target_count BIGINT = (
    SELECT COUNT_BIG(*) FROM #ffm_target
);

SET @msg = CONCAT(
    'PREMIUM PROFILE A2 complete: FFM_TARGET_COUNT=',
    @ffm_target_count,
    '; elapsed_s=', DATEDIFF(second, @t0, SYSDATETIME())
);
RAISERROR(@msg, 10, 1) WITH NOWAIT;

IF @ffm_target_count <> @expected_ffm_target
BEGIN
    RAISERROR(
        'STOP: FFM_TARGET_COUNT=%I64d; expected %I64d.',
        16, 1,
        @ffm_target_count,
        @expected_ffm_target
    );
    RETURN;
END;


-- =============================================================================
-- COMPONENT B1 — STAGE ALL-HISTORY INBOUND ENROLLEE IDENTIFIERS
-- No inbound coverage-year or status restriction.
-- =============================================================================
RAISERROR('PREMIUM PROFILE B1: stage all-history inbound identifiers', 10, 1) WITH NOWAIT;

IF OBJECT_ID('tempdb..#inbound_identifiers') IS NOT NULL
    DROP TABLE #inbound_identifiers;

SELECT
    ia.id AS inbound_row_id,
    NULLIF(LTRIM(RTRIM(CAST(ia.member_id AS VARCHAR(100)))), '')
        AS Inbound_Member_ID,
    NULLIF(LTRIM(RTRIM(CAST(ia.issuer_indiv_identifier AS VARCHAR(100)))), '')
        AS Inbound_Issuer_Indiv_Identifier,
    NULLIF(LTRIM(RTRIM(CAST(ia.exchg_assigned_enrollee_id AS VARCHAR(100)))), '')
        AS Inbound_Exchange_Assigned_Enrollee_ID
INTO #inbound_identifiers
FROM dbo.inbound_automation AS ia
WHERE NULLIF(LTRIM(RTRIM(ia.member_id)), '') IS NOT NULL
   OR NULLIF(LTRIM(RTRIM(ia.issuer_indiv_identifier)), '') IS NOT NULL
   OR NULLIF(LTRIM(RTRIM(ia.exchg_assigned_enrollee_id)), '') IS NOT NULL;

CREATE UNIQUE CLUSTERED INDEX CX_inbound_identifiers
    ON #inbound_identifiers (inbound_row_id);

CREATE NONCLUSTERED INDEX IX_inbound_member
    ON #inbound_identifiers (Inbound_Member_ID);

CREATE NONCLUSTERED INDEX IX_inbound_issuer_indiv
    ON #inbound_identifiers (Inbound_Issuer_Indiv_Identifier);

CREATE NONCLUSTERED INDEX IX_inbound_exchange
    ON #inbound_identifiers (Inbound_Exchange_Assigned_Enrollee_ID);

DECLARE @inbound_row_count BIGINT = (
    SELECT COUNT_BIG(*) FROM #inbound_identifiers
);

SET @msg = CONCAT(
    'PREMIUM PROFILE B1 complete: inbound_rows=',
    @inbound_row_count,
    '; elapsed_s=', DATEDIFF(second, @t0, SYSDATETIME())
);
RAISERROR(@msg, 10, 1) WITH NOWAIT;


-- =============================================================================
-- COMPONENT B2 — VALIDATED NO_INBOUND_ENROLLEE_EVIDENCE
-- Three independent enrollee-only NOT EXISTS checks.
-- No policy, issuer, inbound status, or inbound year match is required.
-- =============================================================================
RAISERROR('PREMIUM PROFILE B2: build NO_INBOUND population', 10, 1) WITH NOWAIT;

IF OBJECT_ID('tempdb..#no_inbound_export') IS NOT NULL
    DROP TABLE #no_inbound_export;

SELECT
    t.FFM_Coverage_Year,
    t.FFM_Issuer,
    t.FFM_Policy_ID,
    t.FFM_Enrollee_ID,
    t.FFM_Enrollment_Status,
    t.FFM_Enrollee_Status,
    CAST('NO_INBOUND_ENROLLEE_EVIDENCE' AS VARCHAR(40)) AS Match_Level
INTO #no_inbound_export
FROM #ffm_target AS t
WHERE NOT EXISTS (
          SELECT 1
          FROM #inbound_identifiers AS i
          WHERE i.Inbound_Member_ID = t.FFM_Enrollee_ID
      )
  AND NOT EXISTS (
          SELECT 1
          FROM #inbound_identifiers AS i
          WHERE i.Inbound_Issuer_Indiv_Identifier = t.FFM_Enrollee_ID
      )
  AND NOT EXISTS (
          SELECT 1
          FROM #inbound_identifiers AS i
          WHERE i.Inbound_Exchange_Assigned_Enrollee_ID = t.FFM_Enrollee_ID
      );

CREATE UNIQUE CLUSTERED INDEX CX_no_inbound_export
    ON #no_inbound_export (
        FFM_Coverage_Year,
        FFM_Policy_ID,
        FFM_Enrollee_ID
    );

DECLARE @no_inbound_count BIGINT = (
    SELECT COUNT_BIG(*) FROM #no_inbound_export
);

SET @msg = CONCAT(
    'PREMIUM PROFILE B2 complete: NO_INBOUND_COUNT=',
    @no_inbound_count,
    '; elapsed_s=', DATEDIFF(second, @t0, SYSDATETIME())
);
RAISERROR(@msg, 10, 1) WITH NOWAIT;

IF @no_inbound_count <> @expected_no_inbound
BEGIN
    RAISERROR(
        'STOP: NO_INBOUND_COUNT=%I64d; expected %I64d. Premium enrichment was not attempted.',
        16, 1,
        @no_inbound_count,
        @expected_no_inbound
    );
    RETURN;
END;


-- =============================================================================
-- COMPONENT C1 — PREMIUM LOOKUP
-- Begins only after all population controls pass.
-- Uses the same five-field latest-row ordering as the complete population.
-- Premium does not affect membership.
-- =============================================================================
RAISERROR('PREMIUM PROFILE C1: enrich validated population with net_premium_amt', 10, 1) WITH NOWAIT;

IF OBJECT_ID('tempdb..#premium_lookup') IS NOT NULL DROP TABLE #premium_lookup;

SELECT
    e.coverage_year AS FFM_Coverage_Year,
    CAST(e.enrollment_id AS VARCHAR(100)) AS FFM_Policy_ID,
    CAST(e.enrollee_id AS VARCHAR(100)) AS FFM_Enrollee_ID,
    CAST(e.net_premium_amt AS DECIMAL(38, 10)) AS Net_Premium_Amount
INTO #premium_lookup
FROM (
    SELECT
        e.coverage_year,
        e.enrollment_id,
        e.enrollee_id,
        e.net_premium_amt,
        e.enrollment_last_update_date,
        e.enrollee_last_update_date,
        e.enrollment_create_date,
        e.enrollee_create_date,
        e.benefit_effective_date,
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
    INNER JOIN #no_inbound_export AS n
        ON n.FFM_Coverage_Year = e.coverage_year
       AND n.FFM_Policy_ID = CAST(e.enrollment_id AS VARCHAR(100))
       AND n.FFM_Enrollee_ID = CAST(e.enrollee_id AS VARCHAR(100))
    WHERE e.coverage_year = @coverage_year
) AS e
WHERE e._rn = 1;

CREATE UNIQUE CLUSTERED INDEX CX_premium_lookup
    ON #premium_lookup (
        FFM_Coverage_Year,
        FFM_Policy_ID,
        FFM_Enrollee_ID
    );


-- =============================================================================
-- COMPONENT C2 — ONE-TO-ONE PREMIUM ENRICHMENT
-- =============================================================================
IF OBJECT_ID('tempdb..#premium_enriched') IS NOT NULL
    DROP TABLE #premium_enriched;

SELECT
    n.FFM_Coverage_Year,
    n.FFM_Issuer,
    n.FFM_Policy_ID,
    n.FFM_Enrollee_ID,
    n.FFM_Enrollment_Status,
    n.FFM_Enrollee_Status,
    p.Net_Premium_Amount,
    CAST(
        CASE
            WHEN p.Net_Premium_Amount IS NULL THEN 'NULL_PREMIUM'
            WHEN p.Net_Premium_Amount = 0 THEN 'ZERO_DOLLAR'
            ELSE 'NON_ZERO'
        END
        AS VARCHAR(20)
    ) AS Premium_Category
INTO #premium_enriched
FROM #no_inbound_export AS n
LEFT JOIN #premium_lookup AS p
    ON p.FFM_Coverage_Year = n.FFM_Coverage_Year
   AND p.FFM_Policy_ID = n.FFM_Policy_ID
   AND p.FFM_Enrollee_ID = n.FFM_Enrollee_ID;

CREATE CLUSTERED INDEX CX_premium_enriched
    ON #premium_enriched (
        FFM_Coverage_Year,
        FFM_Policy_ID,
        FFM_Enrollee_ID
    );

DECLARE @premium_enriched_count BIGINT = (
    SELECT COUNT_BIG(*) FROM #premium_enriched
);

DECLARE @distinct_policy_enrollee_count BIGINT = (
    SELECT COUNT_BIG(*)
    FROM (
        SELECT
            FFM_Coverage_Year,
            FFM_Policy_ID,
            FFM_Enrollee_ID
        FROM #premium_enriched
        GROUP BY
            FFM_Coverage_Year,
            FFM_Policy_ID,
            FFM_Enrollee_ID
    ) AS distinct_grain
);

DECLARE @duplicate_rows_introduced BIGINT =
    @premium_enriched_count - @distinct_policy_enrollee_count;

DECLARE @control_status VARCHAR(4) =
    CASE
        WHEN @complete_2026_distinct_pairs = @expected_complete_2026
         AND @ffm_target_count = @expected_ffm_target
         AND @no_inbound_count = @expected_no_inbound
         AND @premium_enriched_count = @expected_no_inbound
         AND @distinct_policy_enrollee_count = @expected_no_inbound
         AND @duplicate_rows_introduced = 0
            THEN 'PASS'
        ELSE 'FAIL'
    END;


-- =============================================================================
-- OUTPUT 1 — HARD CONTROL TABLE
-- =============================================================================
SELECT
    @complete_2026_distinct_pairs AS COMPLETE_2026_DISTINCT_PAIRS,
    @ffm_target_count AS FFM_TARGET_COUNT,
    @no_inbound_count AS NO_INBOUND_COUNT,
    @premium_enriched_count AS PREMIUM_ENRICHED_COUNT,
    @distinct_policy_enrollee_count AS DISTINCT_POLICY_ENROLLEE_COUNT,
    @duplicate_rows_introduced AS DUPLICATE_ROWS_INTRODUCED,
    @control_status AS CONTROL_STATUS;

IF @control_status <> 'PASS'
BEGIN
    RAISERROR(
        'STOP: final controls failed. complete=%I64d target=%I64d no_inbound=%I64d enriched=%I64d distinct=%I64d duplicates=%I64d.',
        16, 1,
        @complete_2026_distinct_pairs,
        @ffm_target_count,
        @no_inbound_count,
        @premium_enriched_count,
        @distinct_policy_enrollee_count,
        @duplicate_rows_introduced
    );
    RETURN;
END;


-- =============================================================================
-- OUTPUT 2 — PREMIUM CATEGORY DISTRIBUTION
-- =============================================================================
SELECT
    Premium_Category,
    COUNT_BIG(*) AS Record_Count,
    CAST(
        100.0 * COUNT_BIG(*) / NULLIF(@expected_no_inbound, 0)
        AS DECIMAL(10, 4)
    ) AS Percent_of_109776
FROM #premium_enriched
GROUP BY Premium_Category
ORDER BY
    CASE Premium_Category
        WHEN 'ZERO_DOLLAR' THEN 1
        WHEN 'NON_ZERO' THEN 2
        WHEN 'NULL_PREMIUM' THEN 3
        ELSE 99
    END;


-- =============================================================================
-- OUTPUT 3 — ENROLLMENT STATUS x PREMIUM CATEGORY
-- =============================================================================
SELECT
    FFM_Enrollment_Status,
    Premium_Category,
    COUNT_BIG(*) AS Record_Count
FROM #premium_enriched
GROUP BY
    FFM_Enrollment_Status,
    Premium_Category
ORDER BY
    FFM_Enrollment_Status,
    CASE Premium_Category
        WHEN 'ZERO_DOLLAR' THEN 1
        WHEN 'NON_ZERO' THEN 2
        WHEN 'NULL_PREMIUM' THEN 3
        ELSE 99
    END;


-- =============================================================================
-- OUTPUT 4 — ENROLLEE STATUS x PREMIUM CATEGORY
-- =============================================================================
SELECT
    FFM_Enrollee_Status,
    Premium_Category,
    COUNT_BIG(*) AS Record_Count
FROM #premium_enriched
GROUP BY
    FFM_Enrollee_Status,
    Premium_Category
ORDER BY
    FFM_Enrollee_Status,
    CASE Premium_Category
        WHEN 'ZERO_DOLLAR' THEN 1
        WHEN 'NON_ZERO' THEN 2
        WHEN 'NULL_PREMIUM' THEN 3
        ELSE 99
    END;


-- =============================================================================
-- OUTPUT 5 — ISSUER x PREMIUM CATEGORY
-- =============================================================================
SELECT
    FFM_Issuer,
    Premium_Category,
    COUNT_BIG(*) AS Record_Count
FROM #premium_enriched
GROUP BY
    FFM_Issuer,
    Premium_Category
ORDER BY
    FFM_Issuer,
    CASE Premium_Category
        WHEN 'ZERO_DOLLAR' THEN 1
        WHEN 'NON_ZERO' THEN 2
        WHEN 'NULL_PREMIUM' THEN 3
        ELSE 99
    END;


-- =============================================================================
-- OUTPUT 6 — ALL 109,776 ROW-LEVEL RECORDS
-- =============================================================================
SELECT
    FFM_Coverage_Year,
    FFM_Issuer,
    FFM_Policy_ID,
    FFM_Enrollee_ID,
    FFM_Enrollment_Status,
    FFM_Enrollee_Status,
    Net_Premium_Amount,
    Premium_Category
FROM #premium_enriched
ORDER BY
    FFM_Issuer,
    FFM_Policy_ID,
    FFM_Enrollee_ID;
