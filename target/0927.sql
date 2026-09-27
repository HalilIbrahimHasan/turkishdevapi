-- =============================================================================
-- MASTER 2026 FFM / 834 RECONCILIATION POPULATION
-- =============================================================================
-- Business purpose:
--   One normalized MASTER of relevant inbound evidence for the 2026 reconciliation,
--   combining:
--     A) ALL distinct 2026 inbound CONFIRM business entities
--     B) Relevant 2025 inbound carry-forward evidence that EXACTLY supports a
--        Policy+Enrollee pair in the approved 2026 FFM Enrolled/Pending target
--
-- Why the final count is DERIVED (not 755,548 + 161,189):
--   Forward (755,548 exact) and reverse non-exact (161,189) use different grains
--   and directions. A naive UNION ALL would double-count entities that have both
--   2025 carry-forward exact evidence and 2026 CONFIRM evidence. The master
--   normalizes to a cross-year entity key and classifies evidence as
--   2025_CARRY_FORWARD_ONLY / 2026_CONFIRM_ONLY / BOTH_2025_AND_2026.
--
-- Source populations:
--   FFM:    dbo.Enrollments_TEST  (Scenario B: 2026 Enrolled/Pending)
--   Inbound: dbo.inbound_automation (coverage_year IN 2025, 2026)
--
-- Grain:
--   Master_Entity_Key = issuer | Canonical_Policy_Key | Canonical_Enrollee_Key
--   (coverage year removed so both-year evidence is one row)
--
-- Validated controls must PASS before the master is built. Do NOT force totals.
--
-- Safety: READ ONLY on permanent tables. Temp tables/indexes only. No RCNI.
-- Does NOT modify existing validated reconciliation SQL files.
-- =============================================================================

SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @ffm_year INT = 2026;
DECLARE @expected_ffm BIGINT = 960531;
DECLARE @expected_exact BIGINT = 755548;
DECLARE @expected_exact_2025 BIGINT = 404740;
DECLARE @expected_exact_2026 BIGINT = 350808;
DECLARE @expected_2026_raw BIGINT = 551208;
DECLARE @expected_2026_incomplete BIGINT = 8382;
DECLARE @expected_2026_complete BIGINT = 542826;
DECLARE @expected_2026_entities BIGINT = 501369;
DECLARE @expected_2026_collapsed BIGINT = 41457;
DECLARE @expected_rev_exact BIGINT = 340180;
DECLARE @expected_rev_eel BIGINT = 74439;
DECLARE @expected_rev_pol BIGINT = 824;
DECLARE @expected_rev_nit BIGINT = 85926;
DECLARE @expected_rev_nonexact BIGINT = 161189;

DECLARE @t0 DATETIME2 = SYSDATETIME();
DECLARE @t_phase DATETIME2 = SYSDATETIME();
DECLARE @msg NVARCHAR(400);


-- =============================================================================
-- PHASE 1 — FFM Scenario B target
-- =============================================================================
RAISERROR('PHASE1 start: FFM Scenario B target', 10, 1) WITH NOWAIT;

IF OBJECT_ID('tempdb..#ffm_target') IS NOT NULL DROP TABLE #ffm_target;

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
    ) AS FFM_Event_Date,
    e.benefit_effective_date AS FFM_Benefit_Effective_Date,
    e.benefit_end_date AS FFM_Benefit_End_Date
INTO #ffm_target
FROM (
    SELECT
        e.coverage_year,
        e.enrollment_id,
        e.enrollee_id,
        e.hios_issuer_id,
        e.enrollment_status_description,
        e.enrollee_status_description,
        e.benefit_effective_date,
        e.benefit_end_date,
        e.enrollment_create_date,
        e.enrollment_last_update_date,
        ROW_NUMBER() OVER (
            PARTITION BY e.coverage_year, e.enrollment_id, e.enrollee_id
            ORDER BY
                e.enrollment_last_update_date DESC,
                e.enrollment_create_date DESC
        ) AS _rn
    FROM dbo.Enrollments_TEST AS e
    WHERE e.coverage_year = @ffm_year
      AND UPPER(LTRIM(RTRIM(e.enrollment_status_description))) IN ('ENROLLED', 'PENDING')
) AS e
WHERE e._rn = 1;

CREATE UNIQUE CLUSTERED INDEX CX_ffm
    ON #ffm_target (FFM_Coverage_Year, FFM_Policy_ID, FFM_Enrollee_ID);
CREATE NONCLUSTERED INDEX IX_ffm_eel
    ON #ffm_target (FFM_Enrollee_ID)
    INCLUDE (FFM_Policy_ID, FFM_Issuer, FFM_Status_Norm, FFM_Event_Date, FFM_Enrollment_Status, FFM_Enrollee_Status);
CREATE NONCLUSTERED INDEX IX_ffm_pol
    ON #ffm_target (FFM_Policy_ID)
    INCLUDE (FFM_Enrollee_ID, FFM_Issuer, FFM_Enrollment_Status, FFM_Enrollee_Status);

DECLARE @ffm_count BIGINT = (SELECT COUNT(*) FROM #ffm_target);

SET @msg = CONCAT(
    'PHASE1 done in ', DATEDIFF(second, @t_phase, SYSDATETIME()),
    's; ffm_pairs=', @ffm_count
);
RAISERROR(@msg, 10, 1) WITH NOWAIT;

IF @ffm_count <> @expected_ffm
BEGIN
    RAISERROR(
        'CONTROL1 FAIL: FFM target %I64d <> expected %I64d. Aborting.',
        16, 1, @ffm_count, @expected_ffm
    );
    RETURN;
END;


-- =============================================================================
-- PHASE 2 — Inbound working set ONCE (2025 + 2026 only)
-- =============================================================================
SET @t_phase = SYSDATETIME();
RAISERROR('PHASE2 start: load inbound 2025+2026', 10, 1) WITH NOWAIT;

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
    ia.source_file AS Inbound_Source_File,
    COALESCE(
        NULLIF(LTRIM(RTRIM(CAST(ia.member_id AS VARCHAR(100)))), ''),
        NULLIF(LTRIM(RTRIM(CAST(ia.issuer_indiv_identifier AS VARCHAR(100)))), ''),
        NULLIF(LTRIM(RTRIM(CAST(ia.exchg_assigned_enrollee_id AS VARCHAR(100)))), '')
    ) AS Canonical_Enrollee_Key,
    COALESCE(
        NULLIF(LTRIM(RTRIM(CAST(ia.policy_id AS VARCHAR(100)))), ''),
        NULLIF(LTRIM(RTRIM(CAST(ia.health_coverage_policy_no AS VARCHAR(100)))), '')
    ) AS Canonical_Policy_Key
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
    INCLUDE (Inbound_Policy_ID, Inbound_Health_Coverage_Policy_No, Inbound_Issuer, Inbound_Event_Date, Inbound_Status_Normalized, Inbound_Coverage_Year);
CREATE NONCLUSTERED INDEX IX_ib_ii
    ON #inbound (Inbound_Issuer_Indiv_Identifier)
    INCLUDE (Inbound_Policy_ID, Inbound_Health_Coverage_Policy_No, Inbound_Issuer, Inbound_Event_Date, Inbound_Status_Normalized, Inbound_Coverage_Year);
CREATE NONCLUSTERED INDEX IX_ib_ex
    ON #inbound (Inbound_Exchange_Assigned_Enrollee_ID)
    INCLUDE (Inbound_Policy_ID, Inbound_Health_Coverage_Policy_No, Inbound_Issuer, Inbound_Event_Date, Inbound_Status_Normalized, Inbound_Coverage_Year);
CREATE NONCLUSTERED INDEX IX_ib_year_status
    ON #inbound (Inbound_Coverage_Year, Inbound_Status_Normalized)
    INCLUDE (Inbound_Issuer, Canonical_Enrollee_Key, Canonical_Policy_Key);

DECLARE @inbound_count BIGINT = (SELECT COUNT(*) FROM #inbound);
SET @msg = CONCAT(
    'PHASE2 done in ', DATEDIFF(second, @t_phase, SYSDATETIME()),
    's; inbound_rows=', @inbound_count
);
RAISERROR(@msg, 10, 1) WITH NOWAIT;


-- =============================================================================
-- PHASE 3 — Forward exact match (validated semantics) + selected-year controls
-- =============================================================================
SET @t_phase = SYSDATETIME();
RAISERROR('PHASE3 start: forward exact matching', 10, 1) WITH NOWAIT;

IF OBJECT_ID('tempdb..#candidate_hits') IS NOT NULL DROP TABLE #candidate_hits;

;WITH hit_raw AS (
    SELECT t.FFM_Coverage_Year, t.FFM_Policy_ID, t.FFM_Enrollee_ID, i.inbound_row_id,
           CAST('MEMBER_ID' AS VARCHAR(40)) AS hit_type
    FROM #ffm_target AS t
    INNER JOIN #inbound AS i ON i.Inbound_Member_ID = t.FFM_Enrollee_ID

    UNION ALL

    SELECT t.FFM_Coverage_Year, t.FFM_Policy_ID, t.FFM_Enrollee_ID, i.inbound_row_id,
           CAST('ISSUER_INDIV_IDENTIFIER' AS VARCHAR(40))
    FROM #ffm_target AS t
    INNER JOIN #inbound AS i ON i.Inbound_Issuer_Indiv_Identifier = t.FFM_Enrollee_ID

    UNION ALL

    SELECT t.FFM_Coverage_Year, t.FFM_Policy_ID, t.FFM_Enrollee_ID, i.inbound_row_id,
           CAST('EXCHG_ASSIGNED_ENROLLEE_ID' AS VARCHAR(40))
    FROM #ffm_target AS t
    INNER JOIN #inbound AS i ON i.Inbound_Exchange_Assigned_Enrollee_ID = t.FFM_Enrollee_ID
)
SELECT
    FFM_Coverage_Year,
    FFM_Policy_ID,
    FFM_Enrollee_ID,
    inbound_row_id,
    CASE
        WHEN MAX(CASE WHEN hit_type = 'MEMBER_ID' THEN 1 ELSE 0 END) = 1
         AND MAX(CASE WHEN hit_type = 'ISSUER_INDIV_IDENTIFIER' THEN 1 ELSE 0 END) = 1
         AND MAX(CASE WHEN hit_type = 'EXCHG_ASSIGNED_ENROLLEE_ID' THEN 1 ELSE 0 END) = 1
            THEN 'ALL_THREE'
        WHEN MAX(CASE WHEN hit_type = 'MEMBER_ID' THEN 1 ELSE 0 END) = 1
         AND MAX(CASE WHEN hit_type = 'ISSUER_INDIV_IDENTIFIER' THEN 1 ELSE 0 END) = 1
            THEN 'MEMBER_ID+ISSUER_INDIV_IDENTIFIER'
        WHEN MAX(CASE WHEN hit_type = 'MEMBER_ID' THEN 1 ELSE 0 END) = 1
         AND MAX(CASE WHEN hit_type = 'EXCHG_ASSIGNED_ENROLLEE_ID' THEN 1 ELSE 0 END) = 1
            THEN 'MEMBER_ID+EXCHG_ASSIGNED_ENROLLEE_ID'
        WHEN MAX(CASE WHEN hit_type = 'ISSUER_INDIV_IDENTIFIER' THEN 1 ELSE 0 END) = 1
         AND MAX(CASE WHEN hit_type = 'EXCHG_ASSIGNED_ENROLLEE_ID' THEN 1 ELSE 0 END) = 1
            THEN 'ISSUER_INDIV_IDENTIFIER+EXCHG_ASSIGNED_ENROLLEE_ID'
        WHEN MAX(CASE WHEN hit_type = 'MEMBER_ID' THEN 1 ELSE 0 END) = 1 THEN 'MEMBER_ID'
        WHEN MAX(CASE WHEN hit_type = 'ISSUER_INDIV_IDENTIFIER' THEN 1 ELSE 0 END) = 1 THEN 'ISSUER_INDIV_IDENTIFIER'
        ELSE 'EXCHG_ASSIGNED_ENROLLEE_ID'
    END AS Matched_Inbound_ID_Type
INTO #candidate_hits
FROM hit_raw
GROUP BY FFM_Coverage_Year, FFM_Policy_ID, FFM_Enrollee_ID, inbound_row_id;

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
    t.FFM_Status_Norm,
    t.FFM_Event_Date,
    t.FFM_Benefit_Effective_Date,
    t.FFM_Benefit_End_Date,
    h.Matched_Inbound_ID_Type,
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
    i.Canonical_Enrollee_Key,
    i.Canonical_Policy_Key,
    CASE
        WHEN t.FFM_Policy_ID = i.Inbound_Policy_ID
          OR t.FFM_Policy_ID = i.Inbound_Health_Coverage_Policy_No THEN 'YES'
        ELSE 'NO'
    END AS Policy_Match_Flag,
    CASE
        WHEN t.FFM_Policy_ID = i.Inbound_Policy_ID
         AND t.FFM_Policy_ID = i.Inbound_Health_Coverage_Policy_No THEN 'BOTH'
        WHEN t.FFM_Policy_ID = i.Inbound_Policy_ID THEN 'POLICY_ID'
        WHEN t.FFM_Policy_ID = i.Inbound_Health_Coverage_Policy_No THEN 'HEALTH_COVERAGE_POLICY_NO'
        ELSE 'NONE'
    END AS Policy_Match_Type,
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
INNER JOIN #ffm_target AS t
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

IF OBJECT_ID('tempdb..#forward_exact') IS NOT NULL DROP TABLE #forward_exact;

SELECT *
INTO #forward_exact
FROM #best
WHERE Policy_Match_Flag = 'YES';

CREATE UNIQUE CLUSTERED INDEX CX_fwd_exact
    ON #forward_exact (FFM_Coverage_Year, FFM_Policy_ID, FFM_Enrollee_ID);
CREATE NONCLUSTERED INDEX IX_fwd_exact_year
    ON #forward_exact (Inbound_Coverage_Year);

DECLARE @exact_total BIGINT = (SELECT COUNT(*) FROM #forward_exact);
DECLARE @exact_sel_2025 BIGINT = (
    SELECT COUNT(*) FROM #forward_exact WHERE Inbound_Coverage_Year = 2025
);
DECLARE @exact_sel_2026 BIGINT = (
    SELECT COUNT(*) FROM #forward_exact WHERE Inbound_Coverage_Year = 2026
);

SET @msg = CONCAT(
    'PHASE3 done in ', DATEDIFF(second, @t_phase, SYSDATETIME()),
    's; exact=', @exact_total,
    '; sel_2025=', @exact_sel_2025,
    '; sel_2026=', @exact_sel_2026
);
RAISERROR(@msg, 10, 1) WITH NOWAIT;

IF @exact_total <> @expected_exact
   OR @exact_sel_2025 <> @expected_exact_2025
   OR @exact_sel_2026 <> @expected_exact_2026
BEGIN
    SELECT
        'CONTROL2_FORWARD_EXACT' AS control_name,
        @exact_total AS exact_total_actual,
        @expected_exact AS exact_total_expected,
        @exact_sel_2025 AS exact_selected_2025_actual,
        @expected_exact_2025 AS exact_selected_2025_expected,
        @exact_sel_2026 AS exact_selected_2026_actual,
        @expected_exact_2026 AS exact_selected_2026_expected,
        'FAIL' AS control_status;

    RAISERROR(
        'CONTROL2 FAIL: exact=%I64d (exp %I64d), sel_2025=%I64d (exp %I64d), sel_2026=%I64d (exp %I64d). Aborting.',
        16, 1,
        @exact_total, @expected_exact,
        @exact_sel_2025, @expected_exact_2025,
        @exact_sel_2026, @expected_exact_2026
    );
    RETURN;
END;

/* Free large intermediate candidate tables */
DROP TABLE #candidate_hits;
DROP TABLE #candidates;
DROP TABLE #best;


-- =============================================================================
-- PHASE 4 — 2026 CONFIRM entities (validated reverse grain) + reverse match
-- =============================================================================
SET @t_phase = SYSDATETIME();
RAISERROR('PHASE4 start: 2026 CONFIRM entities + reverse match', 10, 1) WITH NOWAIT;

/* Raw CONFIRM count from source (includes incomplete-key rows excluded from #inbound) */
DECLARE @raw_2026 BIGINT = (
    SELECT COUNT(*)
    FROM dbo.inbound_automation AS ia
    WHERE ia.coverage_year = 2026
      AND UPPER(LTRIM(RTRIM(ia.enrolleeStatus))) = 'CONFIRM'
);

IF OBJECT_ID('tempdb..#c2026_bridge') IS NOT NULL DROP TABLE #c2026_bridge;

SELECT
    CAST(i.Inbound_Issuer AS VARCHAR(20))
        + N'|' + CAST(i.Inbound_Coverage_Year AS VARCHAR(10))
        + N'|' + i.Canonical_Policy_Key
        + N'|' + i.Canonical_Enrollee_Key AS Year_Business_Key,
    CAST(i.Inbound_Issuer AS VARCHAR(20))
        + N'|' + i.Canonical_Policy_Key
        + N'|' + i.Canonical_Enrollee_Key AS Master_Entity_Key,
    i.*
INTO #c2026_bridge
FROM #inbound AS i
WHERE i.Inbound_Coverage_Year = 2026
  AND i.Inbound_Status_Normalized = 'CONFIRM'
  AND i.Canonical_Enrollee_Key IS NOT NULL
  AND i.Canonical_Policy_Key IS NOT NULL;

CREATE CLUSTERED INDEX CX_c2026_br
    ON #c2026_bridge (Master_Entity_Key, inbound_row_id);
CREATE NONCLUSTERED INDEX IX_c2026_member
    ON #c2026_bridge (Inbound_Member_ID) INCLUDE (Master_Entity_Key, Year_Business_Key);
CREATE NONCLUSTERED INDEX IX_c2026_ii
    ON #c2026_bridge (Inbound_Issuer_Indiv_Identifier) INCLUDE (Master_Entity_Key, Year_Business_Key);
CREATE NONCLUSTERED INDEX IX_c2026_ex
    ON #c2026_bridge (Inbound_Exchange_Assigned_Enrollee_ID) INCLUDE (Master_Entity_Key, Year_Business_Key);
CREATE NONCLUSTERED INDEX IX_c2026_pol
    ON #c2026_bridge (Inbound_Policy_ID) INCLUDE (Master_Entity_Key, Year_Business_Key);
CREATE NONCLUSTERED INDEX IX_c2026_hc
    ON #c2026_bridge (Inbound_Health_Coverage_Policy_No) INCLUDE (Master_Entity_Key, Year_Business_Key);

DECLARE @complete_2026 BIGINT = (SELECT COUNT(*) FROM #c2026_bridge);
DECLARE @incomplete_2026 BIGINT = @raw_2026 - @complete_2026;

IF OBJECT_ID('tempdb..#c2026_entity') IS NOT NULL DROP TABLE #c2026_entity;

SELECT
    Master_Entity_Key,
    MAX(Year_Business_Key) AS Year_Business_Key,
    MAX(Inbound_Issuer) AS Inbound_Issuer,
    MAX(Canonical_Policy_Key) AS Canonical_Policy_Key,
    MAX(Canonical_Enrollee_Key) AS Canonical_Enrollee_Key,
    COUNT(*) AS Physical_Confirm_Row_Count
INTO #c2026_entity
FROM #c2026_bridge
GROUP BY Master_Entity_Key;

CREATE UNIQUE CLUSTERED INDEX CX_c2026_ent ON #c2026_entity (Master_Entity_Key);

DECLARE @entities_2026 BIGINT = (SELECT COUNT(*) FROM #c2026_entity);
DECLARE @collapsed_2026 BIGINT = @complete_2026 - @entities_2026;

/* Reverse match: enrollee / policy hits via independent ID paths */
IF OBJECT_ID('tempdb..#rev_eel') IS NOT NULL DROP TABLE #rev_eel;

;WITH e_raw AS (
    SELECT br.Master_Entity_Key, f.FFM_Coverage_Year, f.FFM_Policy_ID, f.FFM_Enrollee_ID,
           f.FFM_Issuer, f.FFM_Enrollment_Status, f.FFM_Enrollee_Status,
           f.FFM_Benefit_Effective_Date, f.FFM_Benefit_End_Date,
           CAST('MEMBER_ID' AS VARCHAR(40)) AS Enrollee_Hit_Type
    FROM #c2026_bridge AS br
    INNER JOIN #ffm_target AS f ON f.FFM_Enrollee_ID = br.Inbound_Member_ID
    WHERE br.Inbound_Member_ID IS NOT NULL

    UNION ALL

    SELECT br.Master_Entity_Key, f.FFM_Coverage_Year, f.FFM_Policy_ID, f.FFM_Enrollee_ID,
           f.FFM_Issuer, f.FFM_Enrollment_Status, f.FFM_Enrollee_Status,
           f.FFM_Benefit_Effective_Date, f.FFM_Benefit_End_Date,
           CAST('ISSUER_INDIV_IDENTIFIER' AS VARCHAR(40))
    FROM #c2026_bridge AS br
    INNER JOIN #ffm_target AS f ON f.FFM_Enrollee_ID = br.Inbound_Issuer_Indiv_Identifier
    WHERE br.Inbound_Issuer_Indiv_Identifier IS NOT NULL

    UNION ALL

    SELECT br.Master_Entity_Key, f.FFM_Coverage_Year, f.FFM_Policy_ID, f.FFM_Enrollee_ID,
           f.FFM_Issuer, f.FFM_Enrollment_Status, f.FFM_Enrollee_Status,
           f.FFM_Benefit_Effective_Date, f.FFM_Benefit_End_Date,
           CAST('EXCHG_ASSIGNED_ENROLLEE_ID' AS VARCHAR(40))
    FROM #c2026_bridge AS br
    INNER JOIN #ffm_target AS f ON f.FFM_Enrollee_ID = br.Inbound_Exchange_Assigned_Enrollee_ID
    WHERE br.Inbound_Exchange_Assigned_Enrollee_ID IS NOT NULL
)
SELECT
    Master_Entity_Key,
    FFM_Coverage_Year,
    FFM_Policy_ID,
    FFM_Enrollee_ID,
    FFM_Issuer,
    MAX(FFM_Enrollment_Status) AS FFM_Enrollment_Status,
    MAX(FFM_Enrollee_Status) AS FFM_Enrollee_Status,
    MAX(FFM_Benefit_Effective_Date) AS FFM_Benefit_Effective_Date,
    MAX(FFM_Benefit_End_Date) AS FFM_Benefit_End_Date,
    CASE
        WHEN MAX(CASE WHEN Enrollee_Hit_Type = 'MEMBER_ID' THEN 1 ELSE 0 END) = 1
         AND MAX(CASE WHEN Enrollee_Hit_Type = 'ISSUER_INDIV_IDENTIFIER' THEN 1 ELSE 0 END) = 1
         AND MAX(CASE WHEN Enrollee_Hit_Type = 'EXCHG_ASSIGNED_ENROLLEE_ID' THEN 1 ELSE 0 END) = 1
            THEN 'ALL_THREE'
        WHEN MAX(CASE WHEN Enrollee_Hit_Type = 'MEMBER_ID' THEN 1 ELSE 0 END) = 1
         AND MAX(CASE WHEN Enrollee_Hit_Type = 'ISSUER_INDIV_IDENTIFIER' THEN 1 ELSE 0 END) = 1
            THEN 'MEMBER_ID+ISSUER_INDIV_IDENTIFIER'
        WHEN MAX(CASE WHEN Enrollee_Hit_Type = 'MEMBER_ID' THEN 1 ELSE 0 END) = 1
         AND MAX(CASE WHEN Enrollee_Hit_Type = 'EXCHG_ASSIGNED_ENROLLEE_ID' THEN 1 ELSE 0 END) = 1
            THEN 'MEMBER_ID+EXCHG_ASSIGNED_ENROLLEE_ID'
        WHEN MAX(CASE WHEN Enrollee_Hit_Type = 'ISSUER_INDIV_IDENTIFIER' THEN 1 ELSE 0 END) = 1
         AND MAX(CASE WHEN Enrollee_Hit_Type = 'EXCHG_ASSIGNED_ENROLLEE_ID' THEN 1 ELSE 0 END) = 1
            THEN 'ISSUER_INDIV_IDENTIFIER+EXCHG_ASSIGNED_ENROLLEE_ID'
        WHEN MAX(CASE WHEN Enrollee_Hit_Type = 'MEMBER_ID' THEN 1 ELSE 0 END) = 1 THEN 'MEMBER_ID'
        WHEN MAX(CASE WHEN Enrollee_Hit_Type = 'ISSUER_INDIV_IDENTIFIER' THEN 1 ELSE 0 END) = 1 THEN 'ISSUER_INDIV_IDENTIFIER'
        ELSE 'EXCHG_ASSIGNED_ENROLLEE_ID'
    END AS Matched_Enrollee_ID_Type
INTO #rev_eel
FROM e_raw
GROUP BY Master_Entity_Key, FFM_Coverage_Year, FFM_Policy_ID, FFM_Enrollee_ID, FFM_Issuer;

CREATE CLUSTERED INDEX CX_rev_eel ON #rev_eel (Master_Entity_Key, FFM_Policy_ID, FFM_Enrollee_ID);

IF OBJECT_ID('tempdb..#rev_pol') IS NOT NULL DROP TABLE #rev_pol;

;WITH p_raw AS (
    SELECT br.Master_Entity_Key, f.FFM_Coverage_Year, f.FFM_Policy_ID, f.FFM_Enrollee_ID,
           f.FFM_Issuer, f.FFM_Enrollment_Status, f.FFM_Enrollee_Status,
           f.FFM_Benefit_Effective_Date, f.FFM_Benefit_End_Date,
           CAST('POLICY_ID' AS VARCHAR(40)) AS Policy_Hit_Type
    FROM #c2026_bridge AS br
    INNER JOIN #ffm_target AS f ON f.FFM_Policy_ID = br.Inbound_Policy_ID
    WHERE br.Inbound_Policy_ID IS NOT NULL

    UNION ALL

    SELECT br.Master_Entity_Key, f.FFM_Coverage_Year, f.FFM_Policy_ID, f.FFM_Enrollee_ID,
           f.FFM_Issuer, f.FFM_Enrollment_Status, f.FFM_Enrollee_Status,
           f.FFM_Benefit_Effective_Date, f.FFM_Benefit_End_Date,
           CAST('HEALTH_COVERAGE_POLICY_NO' AS VARCHAR(40))
    FROM #c2026_bridge AS br
    INNER JOIN #ffm_target AS f ON f.FFM_Policy_ID = br.Inbound_Health_Coverage_Policy_No
    WHERE br.Inbound_Health_Coverage_Policy_No IS NOT NULL
)
SELECT
    Master_Entity_Key,
    FFM_Coverage_Year,
    FFM_Policy_ID,
    FFM_Enrollee_ID,
    FFM_Issuer,
    MAX(FFM_Enrollment_Status) AS FFM_Enrollment_Status,
    MAX(FFM_Enrollee_Status) AS FFM_Enrollee_Status,
    MAX(FFM_Benefit_Effective_Date) AS FFM_Benefit_Effective_Date,
    MAX(FFM_Benefit_End_Date) AS FFM_Benefit_End_Date,
    CASE
        WHEN MAX(CASE WHEN Policy_Hit_Type = 'POLICY_ID' THEN 1 ELSE 0 END) = 1
         AND MAX(CASE WHEN Policy_Hit_Type = 'HEALTH_COVERAGE_POLICY_NO' THEN 1 ELSE 0 END) = 1
            THEN 'BOTH'
        WHEN MAX(CASE WHEN Policy_Hit_Type = 'POLICY_ID' THEN 1 ELSE 0 END) = 1 THEN 'POLICY_ID'
        ELSE 'HEALTH_COVERAGE_POLICY_NO'
    END AS Matched_Policy_ID_Type
INTO #rev_pol
FROM p_raw
GROUP BY Master_Entity_Key, FFM_Coverage_Year, FFM_Policy_ID, FFM_Enrollee_ID, FFM_Issuer;

CREATE CLUSTERED INDEX CX_rev_pol ON #rev_pol (Master_Entity_Key, FFM_Policy_ID, FFM_Enrollee_ID);

IF OBJECT_ID('tempdb..#rev_exact') IS NOT NULL DROP TABLE #rev_exact;

SELECT
    e.Master_Entity_Key,
    e.FFM_Coverage_Year,
    e.FFM_Policy_ID,
    e.FFM_Enrollee_ID,
    e.FFM_Issuer,
    e.FFM_Enrollment_Status,
    e.FFM_Enrollee_Status,
    e.FFM_Benefit_Effective_Date,
    e.FFM_Benefit_End_Date,
    e.Matched_Enrollee_ID_Type,
    p.Matched_Policy_ID_Type
INTO #rev_exact
FROM #rev_eel AS e
INNER JOIN #rev_pol AS p
    ON p.Master_Entity_Key = e.Master_Entity_Key
   AND p.FFM_Policy_ID = e.FFM_Policy_ID
   AND p.FFM_Enrollee_ID = e.FFM_Enrollee_ID;

CREATE CLUSTERED INDEX CX_rev_exact ON #rev_exact (Master_Entity_Key);

IF OBJECT_ID('tempdb..#rev_exact_best') IS NOT NULL DROP TABLE #rev_exact_best;
SELECT * INTO #rev_exact_best FROM (
    SELECT *, ROW_NUMBER() OVER (
        PARTITION BY Master_Entity_Key
        ORDER BY FFM_Policy_ID, FFM_Enrollee_ID
    ) AS rn FROM #rev_exact
) x WHERE rn = 1;
CREATE UNIQUE CLUSTERED INDEX CX_rev_exact_best ON #rev_exact_best (Master_Entity_Key);

IF OBJECT_ID('tempdb..#rev_eel_only') IS NOT NULL DROP TABLE #rev_eel_only;
SELECT * INTO #rev_eel_only FROM (
    SELECT e.*, ROW_NUMBER() OVER (
        PARTITION BY e.Master_Entity_Key ORDER BY e.FFM_Policy_ID, e.FFM_Enrollee_ID
    ) AS rn
    FROM #rev_eel AS e
    WHERE NOT EXISTS (SELECT 1 FROM #rev_exact x WHERE x.Master_Entity_Key = e.Master_Entity_Key)
) x WHERE rn = 1;
CREATE UNIQUE CLUSTERED INDEX CX_rev_eel_only ON #rev_eel_only (Master_Entity_Key);

IF OBJECT_ID('tempdb..#rev_pol_only') IS NOT NULL DROP TABLE #rev_pol_only;
SELECT * INTO #rev_pol_only FROM (
    SELECT p.*, ROW_NUMBER() OVER (
        PARTITION BY p.Master_Entity_Key ORDER BY p.FFM_Policy_ID, p.FFM_Enrollee_ID
    ) AS rn
    FROM #rev_pol AS p
    WHERE NOT EXISTS (SELECT 1 FROM #rev_exact x WHERE x.Master_Entity_Key = p.Master_Entity_Key)
      AND NOT EXISTS (SELECT 1 FROM #rev_eel_only e WHERE e.Master_Entity_Key = p.Master_Entity_Key)
) x WHERE rn = 1;
CREATE UNIQUE CLUSTERED INDEX CX_rev_pol_only ON #rev_pol_only (Master_Entity_Key);

IF OBJECT_ID('tempdb..#c2026_class') IS NOT NULL DROP TABLE #c2026_class;

SELECT
    ent.Master_Entity_Key,
    ent.Inbound_Issuer,
    ent.Canonical_Policy_Key,
    ent.Canonical_Enrollee_Key,
    ent.Physical_Confirm_Row_Count,
    CASE
        WHEN ex.Master_Entity_Key IS NOT NULL THEN 'EXACT_POLICY_ENROLLEE_MATCH'
        WHEN eo.Master_Entity_Key IS NOT NULL THEN 'ENROLLEE_IN_TARGET_DIFFERENT_POLICY'
        WHEN po.Master_Entity_Key IS NOT NULL THEN 'POLICY_IN_TARGET_DIFFERENT_ENROLLEE'
        ELSE 'NOT_IN_FFM_TARGET'
    END AS Reverse_Match_Category,
    COALESCE(ex.FFM_Coverage_Year, eo.FFM_Coverage_Year, po.FFM_Coverage_Year) AS FFM_Coverage_Year,
    COALESCE(ex.FFM_Issuer, eo.FFM_Issuer, po.FFM_Issuer) AS FFM_Issuer,
    COALESCE(ex.FFM_Policy_ID, eo.FFM_Policy_ID, po.FFM_Policy_ID) AS FFM_Policy_ID,
    COALESCE(ex.FFM_Enrollee_ID, eo.FFM_Enrollee_ID, po.FFM_Enrollee_ID) AS FFM_Enrollee_ID,
    COALESCE(ex.FFM_Enrollment_Status, eo.FFM_Enrollment_Status, po.FFM_Enrollment_Status) AS FFM_Enrollment_Status,
    COALESCE(ex.FFM_Enrollee_Status, eo.FFM_Enrollee_Status, po.FFM_Enrollee_Status) AS FFM_Enrollee_Status,
    COALESCE(ex.FFM_Benefit_Effective_Date, eo.FFM_Benefit_Effective_Date, po.FFM_Benefit_Effective_Date) AS FFM_Benefit_Effective_Date,
    COALESCE(ex.FFM_Benefit_End_Date, eo.FFM_Benefit_End_Date, po.FFM_Benefit_End_Date) AS FFM_Benefit_End_Date,
    ex.Matched_Enrollee_ID_Type AS Matched_Enrollee_ID_Type,
    ex.Matched_Policy_ID_Type AS Matched_Policy_ID_Type,
    eo.Matched_Enrollee_ID_Type AS Enrollee_Only_Hit_Type,
    po.Matched_Policy_ID_Type AS Policy_Only_Hit_Type
INTO #c2026_class
FROM #c2026_entity AS ent
LEFT JOIN #rev_exact_best AS ex ON ex.Master_Entity_Key = ent.Master_Entity_Key
LEFT JOIN #rev_eel_only AS eo ON eo.Master_Entity_Key = ent.Master_Entity_Key
LEFT JOIN #rev_pol_only AS po ON po.Master_Entity_Key = ent.Master_Entity_Key;

CREATE UNIQUE CLUSTERED INDEX CX_c2026_class ON #c2026_class (Master_Entity_Key);

DECLARE @rev_exact BIGINT = (SELECT COUNT(*) FROM #c2026_class WHERE Reverse_Match_Category = 'EXACT_POLICY_ENROLLEE_MATCH');
DECLARE @rev_eel BIGINT = (SELECT COUNT(*) FROM #c2026_class WHERE Reverse_Match_Category = 'ENROLLEE_IN_TARGET_DIFFERENT_POLICY');
DECLARE @rev_pol BIGINT = (SELECT COUNT(*) FROM #c2026_class WHERE Reverse_Match_Category = 'POLICY_IN_TARGET_DIFFERENT_ENROLLEE');
DECLARE @rev_nit BIGINT = (SELECT COUNT(*) FROM #c2026_class WHERE Reverse_Match_Category = 'NOT_IN_FFM_TARGET');
DECLARE @rev_nonexact BIGINT = @rev_eel + @rev_pol + @rev_nit;

SET @msg = CONCAT(
    'PHASE4 done in ', DATEDIFF(second, @t_phase, SYSDATETIME()),
    's; entities=', @entities_2026,
    '; rev_exact=', @rev_exact,
    '; nonexact=', @rev_nonexact
);
RAISERROR(@msg, 10, 1) WITH NOWAIT;

IF @raw_2026 <> @expected_2026_raw
   OR @complete_2026 <> @expected_2026_complete
   OR @entities_2026 <> @expected_2026_entities
   OR @incomplete_2026 <> @expected_2026_incomplete
   OR @collapsed_2026 <> @expected_2026_collapsed
BEGIN
    SELECT
        'CONTROL3_2026_CONFIRM' AS control_name,
        @raw_2026 AS raw_actual, @expected_2026_raw AS raw_expected,
        @complete_2026 AS complete_actual, @expected_2026_complete AS complete_expected,
        @entities_2026 AS entities_actual, @expected_2026_entities AS entities_expected,
        @incomplete_2026 AS incomplete_actual, @expected_2026_incomplete AS incomplete_expected,
        @collapsed_2026 AS collapsed_actual, @expected_2026_collapsed AS collapsed_expected,
        'FAIL' AS control_status;

    RAISERROR('CONTROL3 FAIL: 2026 CONFIRM population controls did not match. Aborting.', 16, 1);
    RETURN;
END;

IF @rev_exact <> @expected_rev_exact
   OR @rev_eel <> @expected_rev_eel
   OR @rev_pol <> @expected_rev_pol
   OR @rev_nit <> @expected_rev_nit
   OR @rev_nonexact <> @expected_rev_nonexact
   OR (@rev_exact + @rev_nonexact) <> @entities_2026
BEGIN
    SELECT
        'CONTROL4_REVERSE_CATEGORIES' AS control_name,
        @rev_exact AS exact_actual, @expected_rev_exact AS exact_expected,
        @rev_eel AS eel_actual, @expected_rev_eel AS eel_expected,
        @rev_pol AS pol_actual, @expected_rev_pol AS pol_expected,
        @rev_nit AS nit_actual, @expected_rev_nit AS nit_expected,
        @rev_nonexact AS nonexact_actual, @expected_rev_nonexact AS nonexact_expected,
        (@rev_exact + @rev_nonexact) AS category_sum,
        @entities_2026 AS entities,
        'FAIL' AS control_status;

    RAISERROR('CONTROL4 FAIL: reverse category controls did not match. Aborting.', 16, 1);
    RETURN;
END;

/* Representative 2026 CONFIRM row per master entity */
IF OBJECT_ID('tempdb..#rep_2026') IS NOT NULL DROP TABLE #rep_2026;
SELECT * INTO #rep_2026 FROM (
    SELECT
        b.*,
        ROW_NUMBER() OVER (
            PARTITION BY b.Master_Entity_Key
            ORDER BY b.member_maint_effective_date DESC, b.inbound_row_id DESC
        ) AS rn
    FROM #c2026_bridge AS b
) x WHERE rn = 1;
CREATE UNIQUE CLUSTERED INDEX CX_rep_2026 ON #rep_2026 (Master_Entity_Key);


-- =============================================================================
-- PHASE 5 — 2025 carry-forward entities from validated forward exact (selected 2025)
-- =============================================================================
SET @t_phase = SYSDATETIME();
RAISERROR('PHASE5 start: 2025 carry-forward entities from forward exact', 10, 1) WITH NOWAIT;

IF OBJECT_ID('tempdb..#cf_2025') IS NOT NULL DROP TABLE #cf_2025;

SELECT
    CAST(f.Inbound_Issuer AS VARCHAR(20))
        + N'|' + f.Canonical_Policy_Key
        + N'|' + f.Canonical_Enrollee_Key AS Master_Entity_Key,
    f.FFM_Coverage_Year,
    f.FFM_Issuer,
    f.FFM_Policy_ID,
    f.FFM_Enrollee_ID,
    f.FFM_Enrollment_Status,
    f.FFM_Enrollee_Status,
    f.FFM_Benefit_Effective_Date,
    f.FFM_Benefit_End_Date,
    f.Matched_Inbound_ID_Type AS Matched_Enrollee_ID_Type,
    f.Policy_Match_Type AS Matched_Policy_ID_Type,
    f.Inbound_Coverage_Year,
    f.Inbound_Issuer,
    f.Inbound_Policy_ID,
    f.Inbound_Health_Coverage_Policy_No,
    f.Inbound_Member_ID,
    f.Inbound_Issuer_Indiv_Identifier,
    f.Inbound_Exchange_Assigned_Enrollee_ID,
    f.Inbound_Status_Raw,
    f.member_maint_effective_date,
    f.benefit_effective_date,
    f.benefit_end_date,
    f.Inbound_Source_File,
    f.Canonical_Enrollee_Key,
    f.Canonical_Policy_Key,
    f.inbound_row_id
INTO #cf_2025_raw
FROM #forward_exact AS f
WHERE f.Inbound_Coverage_Year = 2025
  AND f.Canonical_Enrollee_Key IS NOT NULL
  AND f.Canonical_Policy_Key IS NOT NULL;

/* One row per master entity (prefer latest maint among selected 2025 exact rows) */
SELECT *
INTO #cf_2025
FROM (
    SELECT
        r.*,
        ROW_NUMBER() OVER (
            PARTITION BY r.Master_Entity_Key
            ORDER BY r.member_maint_effective_date DESC, r.inbound_row_id DESC
        ) AS rn
    FROM #cf_2025_raw AS r
) x
WHERE rn = 1;

CREATE UNIQUE CLUSTERED INDEX CX_cf_2025 ON #cf_2025 (Master_Entity_Key);

DECLARE @cf_2025_entities BIGINT = (SELECT COUNT(*) FROM #cf_2025);

DROP TABLE #cf_2025_raw;

SET @msg = CONCAT(
    'PHASE5 done in ', DATEDIFF(second, @t_phase, SYSDATETIME()),
    's; cf_2025_entities=', @cf_2025_entities,
    ' (from selected_2025_exact_pairs=', @exact_sel_2025, ')'
);
RAISERROR(@msg, 10, 1) WITH NOWAIT;


-- =============================================================================
-- PHASE 6 — MASTER: normalize, overlap-dedupe, classify
-- =============================================================================
SET @t_phase = SYSDATETIME();
RAISERROR('PHASE6 start: build master population', 10, 1) WITH NOWAIT;

IF OBJECT_ID('tempdb..#master_keys') IS NOT NULL DROP TABLE #master_keys;

SELECT Master_Entity_Key, CAST(1 AS INT) AS Has_2026_Evidence, CAST(0 AS INT) AS Has_2025_Evidence
INTO #master_keys
FROM #c2026_entity

UNION ALL

SELECT Master_Entity_Key, CAST(0 AS INT), CAST(1 AS INT)
FROM #cf_2025;

IF OBJECT_ID('tempdb..#master_base') IS NOT NULL DROP TABLE #master_base;

SELECT
    Master_Entity_Key,
    MAX(Has_2025_Evidence) AS Has_2025_Evidence,
    MAX(Has_2026_Evidence) AS Has_2026_Evidence,
    CASE
        WHEN MAX(Has_2025_Evidence) = 1 AND MAX(Has_2026_Evidence) = 1 THEN 'BOTH_2025_AND_2026'
        WHEN MAX(Has_2025_Evidence) = 1 THEN '2025_CARRY_FORWARD_ONLY'
        WHEN MAX(Has_2026_Evidence) = 1 THEN '2026_CONFIRM_ONLY'
        ELSE 'UNEXPECTED'
    END AS Evidence_Category
INTO #master_base
FROM #master_keys
GROUP BY Master_Entity_Key;

CREATE UNIQUE CLUSTERED INDEX CX_master_base ON #master_base (Master_Entity_Key);

DECLARE @master_total BIGINT = (SELECT COUNT(*) FROM #master_base);
DECLARE @ev_2025_only BIGINT = (SELECT COUNT(*) FROM #master_base WHERE Evidence_Category = '2025_CARRY_FORWARD_ONLY');
DECLARE @ev_2026_only BIGINT = (SELECT COUNT(*) FROM #master_base WHERE Evidence_Category = '2026_CONFIRM_ONLY');
DECLARE @ev_both BIGINT = (SELECT COUNT(*) FROM #master_base WHERE Evidence_Category = 'BOTH_2025_AND_2026');

/* Assemble final master row */
IF OBJECT_ID('tempdb..#master') IS NOT NULL DROP TABLE #master;

SELECT
    mb.Master_Entity_Key,
    mb.Evidence_Category,
    mb.Has_2025_Evidence,
    mb.Has_2026_Evidence,
    CASE
        WHEN mb.Has_2025_Evidence = 1 AND mb.Has_2026_Evidence = 1 THEN '2025,2026'
        WHEN mb.Has_2025_Evidence = 1 THEN '2025'
        WHEN mb.Has_2026_Evidence = 1 THEN '2026'
        ELSE NULL
    END AS Evidence_Years,

    /* Exact always wins: 2025 CF is exact by construction; else use reverse category */
    CASE
        WHEN mb.Has_2025_Evidence = 1 THEN 'EXACT_POLICY_ENROLLEE_MATCH'
        WHEN c26.Reverse_Match_Category IS NOT NULL THEN c26.Reverse_Match_Category
        ELSE 'NOT_IN_FFM_TARGET'
    END AS Match_Category,

    /* FFM: prefer reverse exact / eel / pol; if 2025 CF exact, use that FFM pair */
    COALESCE(
        CASE WHEN mb.Has_2025_Evidence = 1 THEN cf.FFM_Coverage_Year END,
        c26.FFM_Coverage_Year
    ) AS FFM_Coverage_Year,
    COALESCE(
        CASE WHEN mb.Has_2025_Evidence = 1 THEN cf.FFM_Issuer END,
        c26.FFM_Issuer
    ) AS FFM_Issuer,
    COALESCE(
        CASE WHEN mb.Has_2025_Evidence = 1 THEN cf.FFM_Policy_ID END,
        c26.FFM_Policy_ID
    ) AS FFM_Policy_ID,
    COALESCE(
        CASE WHEN mb.Has_2025_Evidence = 1 THEN cf.FFM_Enrollee_ID END,
        c26.FFM_Enrollee_ID
    ) AS FFM_Enrollee_ID,
    COALESCE(
        CASE WHEN mb.Has_2025_Evidence = 1 THEN cf.FFM_Enrollment_Status END,
        c26.FFM_Enrollment_Status
    ) AS FFM_Enrollment_Status,
    COALESCE(
        CASE WHEN mb.Has_2025_Evidence = 1 THEN cf.FFM_Enrollee_Status END,
        c26.FFM_Enrollee_Status
    ) AS FFM_Enrollee_Status,
    COALESCE(
        CASE WHEN mb.Has_2025_Evidence = 1 THEN cf.FFM_Benefit_Effective_Date END,
        c26.FFM_Benefit_Effective_Date
    ) AS FFM_Benefit_Effective_Date,
    COALESCE(
        CASE WHEN mb.Has_2025_Evidence = 1 THEN cf.FFM_Benefit_End_Date END,
        c26.FFM_Benefit_End_Date
    ) AS FFM_Benefit_End_Date,

    /* Representative inbound: prefer 2026 CONFIRM display fields */
    COALESCE(r26.Inbound_Coverage_Year, cf.Inbound_Coverage_Year) AS Inbound_Coverage_Year,
    COALESCE(r26.Inbound_Issuer, cf.Inbound_Issuer) AS Inbound_Issuer,
    COALESCE(r26.Inbound_Policy_ID, cf.Inbound_Policy_ID) AS Inbound_Policy_ID,
    COALESCE(r26.Inbound_Health_Coverage_Policy_No, cf.Inbound_Health_Coverage_Policy_No) AS Inbound_Health_Coverage_Policy_No,
    COALESCE(r26.Inbound_Member_ID, cf.Inbound_Member_ID) AS Inbound_Member_ID,
    COALESCE(r26.Inbound_Issuer_Indiv_Identifier, cf.Inbound_Issuer_Indiv_Identifier) AS Inbound_Issuer_Individual_ID,
    COALESCE(r26.Inbound_Exchange_Assigned_Enrollee_ID, cf.Inbound_Exchange_Assigned_Enrollee_ID) AS Inbound_Exchange_Assigned_Enrollee_ID,
    COALESCE(r26.Inbound_Status_Raw, cf.Inbound_Status_Raw) AS Inbound_Status,
    COALESCE(r26.member_maint_effective_date, cf.member_maint_effective_date) AS Member_Maint_Effective_Date,
    COALESCE(r26.benefit_effective_date, cf.benefit_effective_date) AS Benefit_Effective_Date,
    COALESCE(r26.benefit_end_date, cf.benefit_end_date) AS Benefit_End_Date,
    COALESCE(r26.Inbound_Source_File, cf.Inbound_Source_File) AS Source_File,
    COALESCE(c26.Physical_Confirm_Row_Count, 1) AS Physical_Rows_Collapsed,

    COALESCE(
        CASE WHEN mb.Has_2025_Evidence = 1 THEN cf.Matched_Enrollee_ID_Type END,
        c26.Matched_Enrollee_ID_Type,
        c26.Enrollee_Only_Hit_Type
    ) AS Matched_Enrollee_ID_Type,
    COALESCE(
        CASE WHEN mb.Has_2025_Evidence = 1 THEN cf.Matched_Policy_ID_Type END,
        c26.Matched_Policy_ID_Type,
        c26.Policy_Only_Hit_Type
    ) AS Matched_Policy_ID_Type,

    cf.Inbound_Coverage_Year AS CarryForward_2025_Inbound_Year,
    cf.Inbound_Source_File AS CarryForward_2025_Source_File,
    r26.Inbound_Coverage_Year AS Confirm_2026_Inbound_Year,
    r26.Inbound_Source_File AS Confirm_2026_Source_File
INTO #master
FROM #master_base AS mb
LEFT JOIN #c2026_class AS c26 ON c26.Master_Entity_Key = mb.Master_Entity_Key
LEFT JOIN #rep_2026 AS r26 ON r26.Master_Entity_Key = mb.Master_Entity_Key
LEFT JOIN #cf_2025 AS cf ON cf.Master_Entity_Key = mb.Master_Entity_Key;

CREATE UNIQUE CLUSTERED INDEX CX_master ON #master (Master_Entity_Key);
CREATE NONCLUSTERED INDEX IX_master_match ON #master (Match_Category);
CREATE NONCLUSTERED INDEX IX_master_ev ON #master (Evidence_Category);

DECLARE @m_exact BIGINT = (SELECT COUNT(*) FROM #master WHERE Match_Category = 'EXACT_POLICY_ENROLLEE_MATCH');
DECLARE @m_eel BIGINT = (SELECT COUNT(*) FROM #master WHERE Match_Category = 'ENROLLEE_IN_TARGET_DIFFERENT_POLICY');
DECLARE @m_pol BIGINT = (SELECT COUNT(*) FROM #master WHERE Match_Category = 'POLICY_IN_TARGET_DIFFERENT_ENROLLEE');
DECLARE @m_nit BIGINT = (SELECT COUNT(*) FROM #master WHERE Match_Category = 'NOT_IN_FFM_TARGET');
DECLARE @m_match_sum BIGINT = @m_exact + @m_eel + @m_pol + @m_nit;

SET @msg = CONCAT(
    'PHASE6 done in ', DATEDIFF(second, @t_phase, SYSDATETIME()),
    's; master_entities=', @master_total,
    '; match_sum=', @m_match_sum,
    '; total_elapsed_s=', DATEDIFF(second, @t0, SYSDATETIME())
);
RAISERROR(@msg, 10, 1) WITH NOWAIT;

IF @m_match_sum <> @master_total
BEGIN
    RAISERROR(
        'CONTROL6 FAIL: match category sum %I64d <> master entities %I64d. Aborting export.',
        16, 1, @m_match_sum, @master_total
    );
    RETURN;
END;


-- =============================================================================
-- CONTROL 1 — FFM TARGET
-- =============================================================================
SELECT
    'CONTROL1_FFM_TARGET' AS control_name,
    @ffm_count AS FFM_2026_ENROLLED_PENDING_PAIRS,
    @expected_ffm AS expected_value,
    CASE WHEN @ffm_count = @expected_ffm THEN 'PASS' ELSE 'FAIL' END AS control_status;


-- =============================================================================
-- CONTROL 2 — VALIDATED FORWARD EXACT
-- =============================================================================
SELECT
    'CONTROL2_FORWARD_EXACT' AS control_name,
    @exact_total AS EXACT_TOTAL,
    @expected_exact AS EXACT_TOTAL_EXPECTED,
    @exact_sel_2025 AS EXACT_SELECTED_2025,
    @expected_exact_2025 AS EXACT_SELECTED_2025_EXPECTED,
    @exact_sel_2026 AS EXACT_SELECTED_2026,
    @expected_exact_2026 AS EXACT_SELECTED_2026_EXPECTED,
    CASE
        WHEN @exact_total = @expected_exact
         AND @exact_sel_2025 = @expected_exact_2025
         AND @exact_sel_2026 = @expected_exact_2026
            THEN 'PASS'
        ELSE 'FAIL'
    END AS control_status;


-- =============================================================================
-- CONTROL 3 — 2026 CONFIRM
-- =============================================================================
SELECT
    'CONTROL3_2026_CONFIRM' AS control_name,
    @raw_2026 AS RAW_2026_CONFIRM,
    @expected_2026_raw AS RAW_EXPECTED,
    @complete_2026 AS COMPLETE_KEY_PHYSICAL_ROWS,
    @expected_2026_complete AS COMPLETE_EXPECTED,
    @incomplete_2026 AS INCOMPLETE_EXCLUDED,
    @expected_2026_incomplete AS INCOMPLETE_EXPECTED,
    @entities_2026 AS DISTINCT_2026_CONFIRM_ENTITIES,
    @expected_2026_entities AS ENTITIES_EXPECTED,
    @collapsed_2026 AS PHYSICAL_ROWS_COLLAPSED,
    @expected_2026_collapsed AS COLLAPSED_EXPECTED,
    CASE
        WHEN @raw_2026 = @expected_2026_raw
         AND @complete_2026 = @expected_2026_complete
         AND @entities_2026 = @expected_2026_entities
         AND @incomplete_2026 = @expected_2026_incomplete
         AND @collapsed_2026 = @expected_2026_collapsed
            THEN 'PASS'
        ELSE 'FAIL'
    END AS control_status;


-- =============================================================================
-- CONTROL 4 — 2026 REVERSE CATEGORIES
-- =============================================================================
SELECT
    'CONTROL4_REVERSE_CATEGORIES' AS control_name,
    @rev_exact AS EXACT,
    @expected_rev_exact AS EXACT_EXPECTED,
    @rev_eel AS ENROLLEE_DIFFERENT_POLICY,
    @expected_rev_eel AS ENROLLEE_DIFFERENT_POLICY_EXPECTED,
    @rev_pol AS POLICY_DIFFERENT_ENROLLEE,
    @expected_rev_pol AS POLICY_DIFFERENT_ENROLLEE_EXPECTED,
    @rev_nit AS NOT_IN_FFM_TARGET,
    @expected_rev_nit AS NOT_IN_FFM_TARGET_EXPECTED,
    @rev_nonexact AS NON_EXACT_TOTAL,
    @expected_rev_nonexact AS NON_EXACT_TOTAL_EXPECTED,
    (@rev_exact + @rev_eel + @rev_pol + @rev_nit) AS CATEGORY_SUM,
    @entities_2026 AS DISTINCT_2026_CONFIRM_ENTITIES,
    CASE
        WHEN @rev_exact = @expected_rev_exact
         AND @rev_eel = @expected_rev_eel
         AND @rev_pol = @expected_rev_pol
         AND @rev_nit = @expected_rev_nit
         AND @rev_nonexact = @expected_rev_nonexact
         AND (@rev_exact + @rev_eel + @rev_pol + @rev_nit) = @entities_2026
            THEN 'PASS'
        ELSE 'FAIL'
    END AS control_status;


-- =============================================================================
-- CONTROL 5 — MASTER EVIDENCE DISTRIBUTION (derived; not forced)
-- =============================================================================
SELECT
    'CONTROL5_MASTER_EVIDENCE' AS control_name,
    @ev_2025_only AS [2025_CARRY_FORWARD_ONLY],
    @ev_2026_only AS [2026_CONFIRM_ONLY],
    @ev_both AS BOTH_2025_AND_2026,
    @master_total AS FINAL_MASTER_DISTINCT_ENTITIES,
    'DERIVED_AFTER_ENTITY_OVERLAP_NOT_FORCED' AS note;


-- =============================================================================
-- CONTROL 6 — MASTER MATCH CATEGORIES
-- =============================================================================
SELECT
    'CONTROL6_MASTER_MATCH' AS control_name,
    @m_exact AS EXACT_POLICY_ENROLLEE_MATCH,
    @m_eel AS ENROLLEE_IN_TARGET_DIFFERENT_POLICY,
    @m_pol AS POLICY_IN_TARGET_DIFFERENT_ENROLLEE,
    @m_nit AS NOT_IN_FFM_TARGET,
    @m_match_sum AS CATEGORY_SUM,
    @master_total AS FINAL_MASTER_DISTINCT_ENTITIES,
    CASE WHEN @m_match_sum = @master_total THEN 'PASS' ELSE 'FAIL' END AS control_status;


-- =============================================================================
-- FINAL — Row-level MASTER dataset
-- =============================================================================
RAISERROR('FINAL master export starting', 10, 1) WITH NOWAIT;

SELECT
    Master_Entity_Key,
    Evidence_Category,
    Has_2025_Evidence,
    Has_2026_Evidence,
    Evidence_Years,
    Match_Category,
    FFM_Coverage_Year,
    FFM_Issuer,
    FFM_Policy_ID,
    FFM_Enrollee_ID,
    FFM_Enrollment_Status,
    FFM_Enrollee_Status,
    FFM_Benefit_Effective_Date,
    FFM_Benefit_End_Date,
    Inbound_Coverage_Year,
    Inbound_Issuer,
    Inbound_Policy_ID,
    Inbound_Health_Coverage_Policy_No,
    Inbound_Member_ID,
    Inbound_Issuer_Individual_ID,
    Inbound_Exchange_Assigned_Enrollee_ID,
    Inbound_Status,
    Member_Maint_Effective_Date,
    Benefit_Effective_Date,
    Benefit_End_Date,
    Source_File,
    Physical_Rows_Collapsed,
    Matched_Enrollee_ID_Type,
    Matched_Policy_ID_Type,
    CarryForward_2025_Inbound_Year,
    CarryForward_2025_Source_File,
    Confirm_2026_Inbound_Year,
    Confirm_2026_Source_File
FROM #master
ORDER BY
    Evidence_Category,
    Match_Category,
    Inbound_Issuer,
    FFM_Policy_ID,
    FFM_Enrollee_ID;

SET @msg = CONCAT('ALL DONE; total_elapsed_s=', DATEDIFF(second, @t0, SYSDATETIME()));
RAISERROR(@msg, 10, 1) WITH NOWAIT;
