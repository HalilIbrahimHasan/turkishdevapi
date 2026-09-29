

-- =============================================================================
-- EXPORT — 2026 NO_INBOUND_ENROLLEE_EVIDENCE
-- =============================================================================
-- Purpose:
--   Export the complete row-level 2026 FFM Enrolled/Pending population with no
--   enrollee identifier evidence anywhere in the full inbound 834 history.
--
-- Reuses the validated forward reconciliation semantics from:
--   sql/scenario_b_2026_834_row_level_reconciliation.sql
--
-- Definition:
--   One row per FFM (coverage_year, enrollment_id, enrollee_id), retaining the
--   latest FFM physical row by enrollment update/create date, where enrollee_id
--   matches none of these independently:
--     1) inbound_automation.member_id
--     2) inbound_automation.issuer_indiv_identifier
--     3) inbound_automation.exchg_assigned_enrollee_id
--
--   Policy ID is deliberately not part of NO_INBOUND determination.
--   COALESCE is deliberately not used for inbound evidence detection.
--
-- Safety/performance:
--   READ ONLY on permanent tables. Temp tables/indexes only. No RCNI.
--   Inbound is staged once across all coverage years, exactly as in the
--   original validated forward reconciliation.
--   Separate indexed NOT EXISTS checks avoid a large OR predicate.
-- =============================================================================

SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @coverage_year INT = 2026;
DECLARE @expected_ffm_target BIGINT = 960531;
DECLARE @expected_no_inbound BIGINT = 109776;

DECLARE @t0 DATETIME2 = SYSDATETIME();
DECLARE @msg NVARCHAR(400);


-- =============================================================================
-- STEP 1 — Validated 2026 FFM target population and deduplication
-- =============================================================================
RAISERROR('NO_INBOUND EXPORT STEP1: build validated FFM target', 10, 1) WITH NOWAIT;

IF OBJECT_ID('tempdb..#ffm_target') IS NOT NULL DROP TABLE #ffm_target;

SELECT
    e.coverage_year AS FFM_Coverage_Year,
    CAST(e.hios_issuer_id AS VARCHAR(20)) AS FFM_Issuer,
    CAST(e.enrollment_id AS VARCHAR(100)) AS FFM_Policy_ID,
    CAST(e.enrollee_id AS VARCHAR(100)) AS FFM_Enrollee_ID,
    e.enrollment_status_description AS FFM_Enrollment_Status,
    e.enrollee_status_description AS FFM_Enrollee_Status
INTO #ffm_target
FROM (
    SELECT
        e.coverage_year,
        e.hios_issuer_id,
        e.enrollment_id,
        e.enrollee_id,
        e.enrollment_status_description,
        e.enrollee_status_description,
        e.enrollment_create_date,
        e.enrollment_last_update_date,
        ROW_NUMBER() OVER (
            PARTITION BY e.coverage_year, e.enrollment_id, e.enrollee_id
            ORDER BY
                e.enrollment_last_update_date DESC,
                e.enrollment_create_date DESC
        ) AS _rn
    FROM dbo.Enrollments_TEST AS e
    WHERE e.coverage_year = @coverage_year
      AND UPPER(LTRIM(RTRIM(e.enrollment_status_description))) IN ('ENROLLED', 'PENDING')
) AS e
WHERE e._rn = 1;

CREATE UNIQUE CLUSTERED INDEX CX_ffm_target
    ON #ffm_target (FFM_Coverage_Year, FFM_Policy_ID, FFM_Enrollee_ID);

CREATE NONCLUSTERED INDEX IX_ffm_target_enrollee
    ON #ffm_target (FFM_Enrollee_ID)
    INCLUDE (
        FFM_Issuer,
        FFM_Policy_ID,
        FFM_Enrollment_Status,
        FFM_Enrollee_Status
    );

DECLARE @ffm_target_count BIGINT = (SELECT COUNT_BIG(*) FROM #ffm_target);

SET @msg = CONCAT(
    'NO_INBOUND EXPORT STEP1 complete: FFM_TARGET_COUNT=', @ffm_target_count,
    '; elapsed_s=', DATEDIFF(second, @t0, SYSDATETIME())
);
RAISERROR(@msg, 10, 1) WITH NOWAIT;

IF @ffm_target_count <> @expected_ffm_target
BEGIN
    RAISERROR(
        'NO_INBOUND EXPORT STOP: FFM_TARGET_COUNT=%I64d; expected %I64d. No detail exported.',
        16, 1, @ffm_target_count, @expected_ffm_target
    );
    RETURN;
END;


-- =============================================================================
-- STEP 2 — Stage all-year inbound enrollee identifiers once
-- =============================================================================
RAISERROR('NO_INBOUND EXPORT STEP2: stage all-year inbound identifiers', 10, 1) WITH NOWAIT;

IF OBJECT_ID('tempdb..#inbound_identifiers') IS NOT NULL DROP TABLE #inbound_identifiers;

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

DECLARE @inbound_row_count BIGINT = (SELECT COUNT_BIG(*) FROM #inbound_identifiers);

SET @msg = CONCAT(
    'NO_INBOUND EXPORT STEP2 complete: inbound_rows=', @inbound_row_count,
    '; elapsed_s=', DATEDIFF(second, @t0, SYSDATETIME())
);
RAISERROR(@msg, 10, 1) WITH NOWAIT;


-- =============================================================================
-- STEP 3 — Independently derive NO_INBOUND_ENROLLEE_EVIDENCE
-- =============================================================================
-- These are enrollee-only evidence checks. Policy and issuer are intentionally
-- not required. A hit in any one identifier field excludes the FFM pair.
-- =============================================================================
RAISERROR('NO_INBOUND EXPORT STEP3: derive no-inbound population', 10, 1) WITH NOWAIT;

IF OBJECT_ID('tempdb..#no_inbound_export') IS NOT NULL DROP TABLE #no_inbound_export;

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
    ON #no_inbound_export (FFM_Issuer, FFM_Policy_ID, FFM_Enrollee_ID);

DECLARE @no_inbound_count BIGINT = (SELECT COUNT_BIG(*) FROM #no_inbound_export);

SET @msg = CONCAT(
    'NO_INBOUND EXPORT STEP3 complete: NO_INBOUND_COUNT=', @no_inbound_count,
    '; expected=', @expected_no_inbound,
    '; difference=', (@no_inbound_count - @expected_no_inbound),
    '; elapsed_s=', DATEDIFF(second, @t0, SYSDATETIME())
);
RAISERROR(@msg, 10, 1) WITH NOWAIT;

IF @no_inbound_count <> @expected_no_inbound
BEGIN
    RAISERROR(
        'NO_INBOUND EXPORT STOP: independently derived count=%I64d; expected %I64d. No detail exported.',
        16, 1, @no_inbound_count, @expected_no_inbound
    );
    RETURN;
END;


-- =============================================================================
-- RESULT SET 1 — Required control
-- =============================================================================
SELECT
    @no_inbound_count AS NO_INBOUND_COUNT,
    CAST('PASS' AS VARCHAR(4)) AS CONTROL_STATUS;


-- =============================================================================
-- LAST RESULT SET — All 109,776 row-level records
-- =============================================================================
SELECT
    FFM_Issuer,
    FFM_Policy_ID,
    FFM_Enrollee_ID,
    FFM_Enrollment_Status,
    FFM_Enrollee_Status
FROM #no_inbound_export
WHERE Match_Level = 'NO_INBOUND_ENROLLEE_EVIDENCE'
ORDER BY
    FFM_Issuer,
    FFM_Policy_ID,
    FFM_Enrollee_ID;
