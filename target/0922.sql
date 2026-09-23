
-- =============================================================================
-- EXPORT 1 — Validated EXACT_ENROLLEE_POLICY_MATCH population (755,548)
-- =============================================================================
-- Reuses forward matching from:
--   sql/scenario_b_2026_834_row_level_reconciliation.sql
-- Do NOT redesign matching.
-- Inbound working set limited to coverage_year IN (2025, 2026) for VPN stability
-- (validated exact evidence years only). Identifier-presence filter retained.
-- Control MUST equal 755,548 or STOP.
-- Output: control count + export rows only.
-- READ ONLY. Temp tables only. No RCNI.
-- =============================================================================

SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @coverage_year INT = 2026;
DECLARE @expected_target BIGINT = 960531;
DECLARE @expected_exact BIGINT = 755548;

DECLARE @t0 DATETIME2 = SYSDATETIME();
DECLARE @msg NVARCHAR(400);

RAISERROR('EXPORT1 STEP1: FFM target', 10, 1) WITH NOWAIT;

IF OBJECT_ID('tempdb..#target_population') IS NOT NULL DROP TABLE #target_population;

SELECT
    e.coverage_year AS FFM_Coverage_Year,
    CAST(e.enrollment_id AS VARCHAR(100)) AS FFM_Policy_ID,
    CAST(e.enrollee_id AS VARCHAR(100)) AS FFM_Enrollee_ID,
    CAST(e.hios_issuer_id AS VARCHAR(20)) AS FFM_Issuer,
    e.enrollment_status_description AS FFM_Enrollment_Status,
    e.enrollee_status_description AS FFM_Enrollee_Status,
    CASE
        WHEN UPPER(LTRIM(RTRIM(e.enrollment_status_description))) = 'ENROLLED' THEN 'CONFIRM'
        WHEN UPPER(LTRIM(RTRIM(e.enrollment_status_description))) = 'PENDING'  THEN 'PENDING'
        ELSE 'STATUS_MAPPING_REVIEW'
    END AS FFM_Status_Norm,
    COALESCE(
        e.enrollment_last_update_date,
        e.enrollment_create_date,
        e.benefit_effective_date
    ) AS FFM_Event_Date
INTO #target_population
FROM (
    SELECT
        e.coverage_year,
        e.enrollment_id,
        e.enrollee_id,
        e.hios_issuer_id,
        e.enrollment_status_description,
        e.enrollee_status_description,
        e.benefit_effective_date,
        e.enrollment_create_date,
        e.enrollment_last_update_date,
        ROW_NUMBER() OVER (
            PARTITION BY e.coverage_year, e.enrollment_id, e.enrollee_id
            ORDER BY e.enrollment_last_update_date DESC, e.enrollment_create_date DESC
        ) AS _rn
    FROM dbo.Enrollments_TEST AS e
    WHERE e.coverage_year = @coverage_year
      AND UPPER(LTRIM(RTRIM(e.enrollment_status_description))) IN ('ENROLLED', 'PENDING')
) AS e
WHERE e._rn = 1;

CREATE UNIQUE CLUSTERED INDEX CX_target
    ON #target_population (FFM_Coverage_Year, FFM_Policy_ID, FFM_Enrollee_ID);
CREATE NONCLUSTERED INDEX IX_target_eel
    ON #target_population (FFM_Enrollee_ID)
    INCLUDE (FFM_Policy_ID, FFM_Issuer, FFM_Status_Norm, FFM_Event_Date);

DECLARE @target_count BIGINT = (SELECT COUNT(*) FROM #target_population);
SET @msg = CONCAT('EXPORT1 target=', @target_count, ' elapsed_s=', DATEDIFF(second, @t0, SYSDATETIME()));
RAISERROR(@msg, 10, 1) WITH NOWAIT;

IF @target_count <> @expected_target
BEGIN
    RAISERROR('EXPORT1 STOP: FFM target %I64d <> expected %I64d', 16, 1, @target_count, @expected_target);
    RETURN;
END;

RAISERROR('EXPORT1 STEP2: inbound working set', 10, 1) WITH NOWAIT;

IF OBJECT_ID('tempdb..#inbound') IS NOT NULL DROP TABLE #inbound;

SELECT
    ia.id AS inbound_row_id,
    NULLIF(LTRIM(RTRIM(CAST(ia.member_id AS VARCHAR(100)))), '') AS Inbound_Member_ID,
    NULLIF(LTRIM(RTRIM(CAST(ia.issuer_indiv_identifier AS VARCHAR(100)))), '') AS Inbound_Issuer_Indiv_Identifier,
    NULLIF(LTRIM(RTRIM(CAST(ia.exchg_assigned_enrollee_id AS VARCHAR(100)))), '') AS Inbound_Exchange_Assigned_Enrollee_ID,
    NULLIF(LTRIM(RTRIM(CAST(ia.policy_id AS VARCHAR(100)))), '') AS Inbound_Policy_ID,
    NULLIF(LTRIM(RTRIM(CAST(ia.health_coverage_policy_no AS VARCHAR(100)))), '') AS Inbound_Health_Coverage_Policy_No,
    CAST(ia.issuer AS VARCHAR(20)) AS Inbound_Issuer,
    ia.coverage_year AS Inbound_Coverage_Year,
    ia.enrolleeStatus AS Inbound_Status_Raw,
    CASE
        WHEN UPPER(LTRIM(RTRIM(ia.enrolleeStatus))) = 'CONFIRM' THEN 'CONFIRM'
        WHEN UPPER(LTRIM(RTRIM(ia.enrolleeStatus))) = 'CANCEL'  THEN 'CANCEL'
        WHEN UPPER(LTRIM(RTRIM(ia.enrolleeStatus))) = 'TERM'    THEN 'TERM'
        ELSE 'STATUS_MAPPING_REVIEW'
    END AS Inbound_Status_Normalized,
    ia.member_maint_effective_date,
    ia.benefit_effective_date,
    ia.benefit_end_date,
    COALESCE(
        ia.member_maint_effective_date,
        TRY_CONVERT(
            date,
            SUBSTRING(
                ia.source_file,
                NULLIF(
                    PATINDEX(
                        '%[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]%.xml',
                        ia.source_file
                    ),
                    0
                ),
                8
            ),
            112
        ),
        ia.benefit_effective_date
    ) AS Inbound_Event_Date,
    ia.source_file AS Inbound_Source_File
INTO #inbound
FROM dbo.inbound_automation AS ia
WHERE ia.coverage_year IN (2025, 2026)
  AND (
         NULLIF(LTRIM(RTRIM(ia.member_id)), '') IS NOT NULL
      OR NULLIF(LTRIM(RTRIM(ia.issuer_indiv_identifier)), '') IS NOT NULL
      OR NULLIF(LTRIM(RTRIM(ia.exchg_assigned_enrollee_id)), '') IS NOT NULL
  );

CREATE UNIQUE CLUSTERED INDEX CX_inbound ON #inbound (inbound_row_id);
CREATE NONCLUSTERED INDEX IX_ib_member
    ON #inbound (Inbound_Member_ID)
    INCLUDE (Inbound_Policy_ID, Inbound_Health_Coverage_Policy_No, Inbound_Issuer, Inbound_Event_Date, Inbound_Status_Normalized);
CREATE NONCLUSTERED INDEX IX_ib_ii
    ON #inbound (Inbound_Issuer_Indiv_Identifier)
    INCLUDE (Inbound_Policy_ID, Inbound_Health_Coverage_Policy_No, Inbound_Issuer, Inbound_Event_Date, Inbound_Status_Normalized);
CREATE NONCLUSTERED INDEX IX_ib_ex
    ON #inbound (Inbound_Exchange_Assigned_Enrollee_ID)
    INCLUDE (Inbound_Policy_ID, Inbound_Health_Coverage_Policy_No, Inbound_Issuer, Inbound_Event_Date, Inbound_Status_Normalized);

DECLARE @inbound_count BIGINT = (SELECT COUNT(*) FROM #inbound);
SET @msg = CONCAT(
    'EXPORT1 inbound working set loaded: rows=', @inbound_count,
    ' (coverage_year IN 2025,2026); elapsed_s=', DATEDIFF(second, @t0, SYSDATETIME())
);
RAISERROR(@msg, 10, 1) WITH NOWAIT;

RAISERROR('EXPORT1 STEP3: candidate hits + ranking (unchanged)', 10, 1) WITH NOWAIT;

IF OBJECT_ID('tempdb..#candidate_hits') IS NOT NULL DROP TABLE #candidate_hits;

;WITH hit_raw AS (
    SELECT t.FFM_Coverage_Year, t.FFM_Policy_ID, t.FFM_Enrollee_ID, i.inbound_row_id
    FROM #target_population AS t
    INNER JOIN #inbound AS i ON i.Inbound_Member_ID = t.FFM_Enrollee_ID
    UNION
    SELECT t.FFM_Coverage_Year, t.FFM_Policy_ID, t.FFM_Enrollee_ID, i.inbound_row_id
    FROM #target_population AS t
    INNER JOIN #inbound AS i ON i.Inbound_Issuer_Indiv_Identifier = t.FFM_Enrollee_ID
    UNION
    SELECT t.FFM_Coverage_Year, t.FFM_Policy_ID, t.FFM_Enrollee_ID, i.inbound_row_id
    FROM #target_population AS t
    INNER JOIN #inbound AS i ON i.Inbound_Exchange_Assigned_Enrollee_ID = t.FFM_Enrollee_ID
)
SELECT FFM_Coverage_Year, FFM_Policy_ID, FFM_Enrollee_ID, inbound_row_id
INTO #candidate_hits
FROM hit_raw;

CREATE CLUSTERED INDEX CX_hits
    ON #candidate_hits (FFM_Enrollee_ID, FFM_Policy_ID, inbound_row_id);

IF OBJECT_ID('tempdb..#candidates') IS NOT NULL DROP TABLE #candidates;

SELECT
    t.FFM_Coverage_Year,
    t.FFM_Policy_ID,
    t.FFM_Enrollee_ID,
    t.FFM_Issuer,
    t.FFM_Enrollment_Status,
    t.FFM_Enrollee_Status,
    i.Inbound_Member_ID,
    i.Inbound_Issuer_Indiv_Identifier,
    i.Inbound_Exchange_Assigned_Enrollee_ID,
    i.Inbound_Policy_ID,
    i.Inbound_Health_Coverage_Policy_No,
    i.Inbound_Issuer,
    i.Inbound_Coverage_Year,
    i.Inbound_Status_Raw,
    i.Inbound_Status_Normalized,
    i.Inbound_Event_Date,
    i.member_maint_effective_date,
    i.benefit_effective_date,
    i.benefit_end_date,
    i.Inbound_Source_File,
    CASE
        WHEN t.FFM_Policy_ID = i.Inbound_Policy_ID
          OR t.FFM_Policy_ID = i.Inbound_Health_Coverage_Policy_No THEN 'YES'
        ELSE 'NO'
    END AS Policy_Match_Flag,
    CASE WHEN t.FFM_Issuer = i.Inbound_Issuer THEN 'YES' ELSE 'NO' END AS Issuer_Match_Flag,
    CASE
        WHEN t.FFM_Status_Norm = 'CONFIRM'
         AND i.Inbound_Status_Normalized = 'CONFIRM' THEN 'YES'
        ELSE 'NO'
    END AS Status_Match_Flag,
    CASE
        WHEN t.FFM_Event_Date IS NOT NULL AND i.Inbound_Event_Date IS NOT NULL
            THEN ABS(DATEDIFF(day, t.FFM_Event_Date, i.Inbound_Event_Date))
    END AS Date_Difference_Days,
    CASE
        WHEN t.FFM_Policy_ID = i.Inbound_Policy_ID
          OR t.FFM_Policy_ID = i.Inbound_Health_Coverage_Policy_No THEN 1
        WHEN t.FFM_Issuer = i.Inbound_Issuer
         AND t.FFM_Status_Norm = 'CONFIRM'
         AND i.Inbound_Status_Normalized = 'CONFIRM'
         AND t.FFM_Event_Date IS NOT NULL AND i.Inbound_Event_Date IS NOT NULL
         AND ABS(DATEDIFF(day, t.FFM_Event_Date, i.Inbound_Event_Date)) = 0 THEN 2
        WHEN t.FFM_Issuer = i.Inbound_Issuer
         AND t.FFM_Status_Norm = 'CONFIRM'
         AND i.Inbound_Status_Normalized = 'CONFIRM'
         AND t.FFM_Event_Date IS NOT NULL AND i.Inbound_Event_Date IS NOT NULL
         AND ABS(DATEDIFF(day, t.FFM_Event_Date, i.Inbound_Event_Date)) <= 7 THEN 3
        WHEN t.FFM_Issuer = i.Inbound_Issuer
         AND t.FFM_Status_Norm = 'CONFIRM'
         AND i.Inbound_Status_Normalized = 'CONFIRM' THEN 4
        WHEN t.FFM_Issuer = i.Inbound_Issuer THEN 5
        WHEN t.FFM_Status_Norm = 'CONFIRM'
         AND i.Inbound_Status_Normalized = 'CONFIRM'
         AND t.FFM_Event_Date IS NOT NULL AND i.Inbound_Event_Date IS NOT NULL
         AND ABS(DATEDIFF(day, t.FFM_Event_Date, i.Inbound_Event_Date)) <= 30 THEN 6
        WHEN t.FFM_Status_Norm = 'CONFIRM'
         AND i.Inbound_Status_Normalized = 'CONFIRM' THEN 7
        ELSE 8
    END AS rank_priority,
    i.inbound_row_id
INTO #candidates
FROM #candidate_hits AS h
INNER JOIN #target_population AS t
    ON t.FFM_Coverage_Year = h.FFM_Coverage_Year
   AND t.FFM_Policy_ID = h.FFM_Policy_ID
   AND t.FFM_Enrollee_ID = h.FFM_Enrollee_ID
INNER JOIN #inbound AS i
    ON i.inbound_row_id = h.inbound_row_id;

CREATE CLUSTERED INDEX CX_cand
    ON #candidates (FFM_Enrollee_ID, FFM_Policy_ID, rank_priority, inbound_row_id);

IF OBJECT_ID('tempdb..#best') IS NOT NULL DROP TABLE #best;

SELECT *
INTO #best
FROM (
    SELECT
        c.*,
        ROW_NUMBER() OVER (
            PARTITION BY c.FFM_Coverage_Year, c.FFM_Policy_ID, c.FFM_Enrollee_ID
            ORDER BY
                c.rank_priority ASC,
                CASE WHEN c.Date_Difference_Days IS NULL THEN 999999 ELSE c.Date_Difference_Days END ASC,
                c.inbound_row_id DESC
        ) AS rn
    FROM #candidates AS c
) AS x
WHERE x.rn = 1;

CREATE UNIQUE CLUSTERED INDEX CX_best
    ON #best (FFM_Coverage_Year, FFM_Policy_ID, FFM_Enrollee_ID);

/* Exact only — validated forward Match_Level rule */
IF OBJECT_ID('tempdb..#exact_export') IS NOT NULL DROP TABLE #exact_export;

SELECT
    b.FFM_Coverage_Year,
    b.FFM_Issuer,
    b.FFM_Policy_ID,
    b.FFM_Enrollee_ID,
    b.FFM_Enrollment_Status,
    b.FFM_Enrollee_Status,
    b.Inbound_Coverage_Year,
    b.Inbound_Issuer,
    b.Inbound_Policy_ID,
    b.Inbound_Health_Coverage_Policy_No,
    b.Inbound_Member_ID,
    b.Inbound_Issuer_Indiv_Identifier,
    b.Inbound_Exchange_Assigned_Enrollee_ID,
    b.Inbound_Status_Raw AS Inbound_Status,
    b.member_maint_effective_date AS Member_Maint_Effective_Date,
    b.benefit_effective_date AS Benefit_Effective_Date,
    b.benefit_end_date AS Benefit_End_Date,
    b.Inbound_Source_File AS Source_File,
    CAST('EXACT_ENROLLEE_POLICY_MATCH' AS VARCHAR(40)) AS Match_Level
INTO #exact_export
FROM #best AS b
WHERE b.Policy_Match_Flag = 'YES';

CREATE UNIQUE CLUSTERED INDEX CX_exact_export
    ON #exact_export (FFM_Coverage_Year, FFM_Policy_ID, FFM_Enrollee_ID);

DECLARE @exact_count BIGINT = (SELECT COUNT(*) FROM #exact_export);

SET @msg = CONCAT(
    'EXPORT1 exact_count=', @exact_count,
    ' expected=', @expected_exact,
    ' elapsed_s=', DATEDIFF(second, @t0, SYSDATETIME())
);
RAISERROR(@msg, 10, 1) WITH NOWAIT;

-- CONTROL (must equal 755,548)
SELECT
    @exact_count AS exact_match_export_count,
    @expected_exact AS expected_exact_count,
    CASE WHEN @exact_count = @expected_exact THEN 'PASS' ELSE 'FAIL_STOP' END AS control_status;

IF @exact_count <> @expected_exact
BEGIN
    RAISERROR(
        'EXPORT1 STOP: exact count %I64d <> expected %I64d. Not changing logic. No export rows returned.',
        16, 1, @exact_count, @expected_exact
    );
    RETURN;
END;

-- EXPORT ROWS
SELECT
    FFM_Coverage_Year,
    FFM_Issuer,
    FFM_Policy_ID,
    FFM_Enrollee_ID,
    FFM_Enrollment_Status,
    FFM_Enrollee_Status,
    Inbound_Coverage_Year,
    Inbound_Issuer,
    Inbound_Policy_ID,
    Inbound_Health_Coverage_Policy_No,
    Inbound_Member_ID,
    Inbound_Issuer_Indiv_Identifier,
    Inbound_Exchange_Assigned_Enrollee_ID,
    Inbound_Status,
    Member_Maint_Effective_Date,
    Benefit_Effective_Date,
    Benefit_End_Date,
    Source_File,
    Match_Level
FROM #exact_export;

RAISERROR('EXPORT1 DONE', 10, 1) WITH NOWAIT;
