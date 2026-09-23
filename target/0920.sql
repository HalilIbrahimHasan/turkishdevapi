-- =============================================================================
-- FOCUSED 2026 RELEVANT POPULATION (OPTIMIZED)
-- =============================================================================
-- Purpose:
--   Lightweight focused population only:
--     A) 2025 CONFIRM exact carry-forward vs 2026 FFM target (FFM-first; no full
--        2025 CONFIRM load)
--     B) All 2026 CONFIRM business entities classified vs same FFM target
--   Deduplicate 2025+2026 exact at FFM Policy+Enrollee grain.
--
-- Does NOT:
--   - modify year_carry_forward_2025_2026_confirm_population_reconciliation.sql
--   - load full 2025+2026 combined bridges
--   - run all-year Enrollments_TEST diagnostics / STRING_AGG / giant masters
--
-- Safety: READ ONLY. Temp tables/indexes only. No RCNI.
-- =============================================================================

SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @ffm_year INT = 2026;
DECLARE @expected_ffm_total BIGINT = 960531;
DECLARE @expected_ffm_enrolled BIGINT = 945039;
DECLARE @expected_ffm_pending BIGINT = 15492;
DECLARE @expected_2026_confirm_raw BIGINT = 551208;
DECLARE @expected_2026_confirm_entities BIGINT = 501369;

DECLARE @t0 DATETIME2 = SYSDATETIME();
DECLARE @t_phase DATETIME2 = SYSDATETIME();
DECLARE @msg NVARCHAR(400);


-- =============================================================================
-- STEP 1 — FFM 2026 Enrolled/Pending target
-- =============================================================================
RAISERROR('STEP1 start: FFM target', 10, 1) WITH NOWAIT;

IF OBJECT_ID('tempdb..#ffm_target') IS NOT NULL DROP TABLE #ffm_target;

SELECT
    CAST(e.enrollment_id AS VARCHAR(100)) AS FFM_Policy_ID,
    CAST(e.enrollee_id AS VARCHAR(100)) AS FFM_Enrollee_ID,
    CASE
        WHEN UPPER(LTRIM(RTRIM(e.enrollment_status_description))) = 'ENROLLED' THEN 'ENROLLED'
        ELSE 'PENDING'
    END AS FFM_Status_Bucket
INTO #ffm_target
FROM (
    SELECT
        e.enrollment_id,
        e.enrollee_id,
        e.enrollment_status_description,
        ROW_NUMBER() OVER (
            PARTITION BY e.coverage_year, e.enrollment_id, e.enrollee_id
            ORDER BY e.enrollment_last_update_date DESC, e.enrollment_create_date DESC
        ) AS _rn
    FROM dbo.Enrollments_TEST AS e
    WHERE e.coverage_year = @ffm_year
      AND UPPER(LTRIM(RTRIM(e.enrollment_status_description))) IN ('ENROLLED', 'PENDING')
) AS e
WHERE e._rn = 1;

CREATE UNIQUE CLUSTERED INDEX CX_ffm
    ON #ffm_target (FFM_Policy_ID, FFM_Enrollee_ID);
CREATE NONCLUSTERED INDEX IX_ffm_eel
    ON #ffm_target (FFM_Enrollee_ID) INCLUDE (FFM_Policy_ID);
CREATE NONCLUSTERED INDEX IX_ffm_pol
    ON #ffm_target (FFM_Policy_ID) INCLUDE (FFM_Enrollee_ID);

DECLARE @ffm_total BIGINT = (SELECT COUNT(*) FROM #ffm_target);
DECLARE @ffm_enrolled BIGINT = (SELECT COUNT(*) FROM #ffm_target WHERE FFM_Status_Bucket = 'ENROLLED');
DECLARE @ffm_pending BIGINT = (SELECT COUNT(*) FROM #ffm_target WHERE FFM_Status_Bucket = 'PENDING');

SET @msg = CONCAT(
    'STEP1 done in ', DATEDIFF(second, @t_phase, SYSDATETIME()),
    's; total=', @ffm_total, '; enrolled=', @ffm_enrolled, '; pending=', @ffm_pending
);
RAISERROR(@msg, 10, 1) WITH NOWAIT;

IF @ffm_total <> @expected_ffm_total
   OR @ffm_enrolled <> @expected_ffm_enrolled
   OR @ffm_pending <> @expected_ffm_pending
BEGIN
    RAISERROR(
        'FFM TARGET FAILED: total=%I64d (exp %I64d), enrolled=%I64d (exp %I64d), pending=%I64d (exp %I64d). Aborting.',
        16, 1,
        @ffm_total, @expected_ffm_total,
        @ffm_enrolled, @expected_ffm_enrolled,
        @ffm_pending, @expected_ffm_pending
    );
    RETURN;
END;


-- =============================================================================
-- STEP 2 — 2026 CONFIRM only (business entities)
-- =============================================================================
SET @t_phase = SYSDATETIME();
RAISERROR('STEP2 start: 2026 CONFIRM entities', 10, 1) WITH NOWAIT;

IF OBJECT_ID('tempdb..#c2026_raw') IS NOT NULL DROP TABLE #c2026_raw;

SELECT
    ia.id AS inbound_row_id,
    CAST(ia.issuer AS VARCHAR(20)) AS Inbound_Issuer,
    NULLIF(LTRIM(RTRIM(CAST(ia.member_id AS VARCHAR(100)))), '') AS Inbound_Member_ID,
    NULLIF(LTRIM(RTRIM(CAST(ia.issuer_indiv_identifier AS VARCHAR(100)))), '') AS Inbound_Issuer_Indiv_Identifier,
    NULLIF(LTRIM(RTRIM(CAST(ia.exchg_assigned_enrollee_id AS VARCHAR(100)))), '') AS Inbound_Exchange_Assigned_Enrollee_ID,
    NULLIF(LTRIM(RTRIM(CAST(ia.policy_id AS VARCHAR(100)))), '') AS Inbound_Policy_ID,
    NULLIF(LTRIM(RTRIM(CAST(ia.health_coverage_policy_no AS VARCHAR(100)))), '') AS Inbound_Health_Coverage_Policy_No,
    COALESCE(
        NULLIF(LTRIM(RTRIM(CAST(ia.member_id AS VARCHAR(100)))), ''),
        NULLIF(LTRIM(RTRIM(CAST(ia.issuer_indiv_identifier AS VARCHAR(100)))), ''),
        NULLIF(LTRIM(RTRIM(CAST(ia.exchg_assigned_enrollee_id AS VARCHAR(100)))), '')
    ) AS Canonical_Enrollee_Key,
    COALESCE(
        NULLIF(LTRIM(RTRIM(CAST(ia.policy_id AS VARCHAR(100)))), ''),
        NULLIF(LTRIM(RTRIM(CAST(ia.health_coverage_policy_no AS VARCHAR(100)))), '')
    ) AS Canonical_Policy_Key
INTO #c2026_raw
FROM dbo.inbound_automation AS ia
WHERE ia.coverage_year = 2026
  AND UPPER(LTRIM(RTRIM(ia.enrolleeStatus))) = 'CONFIRM';

DECLARE @raw_2026 BIGINT = (SELECT COUNT(*) FROM #c2026_raw);

IF OBJECT_ID('tempdb..#c2026_bridge') IS NOT NULL DROP TABLE #c2026_bridge;

SELECT
    CAST(r.Inbound_Issuer AS VARCHAR(20))
        + N'|' + r.Canonical_Policy_Key
        + N'|' + r.Canonical_Enrollee_Key AS Business_Key,
    r.inbound_row_id,
    r.Inbound_Member_ID,
    r.Inbound_Issuer_Indiv_Identifier,
    r.Inbound_Exchange_Assigned_Enrollee_ID,
    r.Inbound_Policy_ID,
    r.Inbound_Health_Coverage_Policy_No
INTO #c2026_bridge
FROM #c2026_raw AS r
WHERE r.Canonical_Enrollee_Key IS NOT NULL
  AND r.Canonical_Policy_Key IS NOT NULL;

CREATE CLUSTERED INDEX CX_c2026_br ON #c2026_bridge (Business_Key, inbound_row_id);
CREATE NONCLUSTERED INDEX IX_c2026_member ON #c2026_bridge (Inbound_Member_ID) INCLUDE (Business_Key);
CREATE NONCLUSTERED INDEX IX_c2026_ii ON #c2026_bridge (Inbound_Issuer_Indiv_Identifier) INCLUDE (Business_Key);
CREATE NONCLUSTERED INDEX IX_c2026_ex ON #c2026_bridge (Inbound_Exchange_Assigned_Enrollee_ID) INCLUDE (Business_Key);
CREATE NONCLUSTERED INDEX IX_c2026_pol ON #c2026_bridge (Inbound_Policy_ID) INCLUDE (Business_Key);
CREATE NONCLUSTERED INDEX IX_c2026_hc ON #c2026_bridge (Inbound_Health_Coverage_Policy_No) INCLUDE (Business_Key);

IF OBJECT_ID('tempdb..#c2026_entity') IS NOT NULL DROP TABLE #c2026_entity;

SELECT DISTINCT Business_Key
INTO #c2026_entity
FROM #c2026_bridge;

CREATE UNIQUE CLUSTERED INDEX CX_c2026_ent ON #c2026_entity (Business_Key);

DECLARE @entities_2026 BIGINT = (SELECT COUNT(*) FROM #c2026_entity);

SET @msg = CONCAT(
    'STEP2 done in ', DATEDIFF(second, @t_phase, SYSDATETIME()),
    's; raw_2026=', @raw_2026, '; entities_2026=', @entities_2026
);
RAISERROR(@msg, 10, 1) WITH NOWAIT;

IF @raw_2026 <> @expected_2026_confirm_raw OR @entities_2026 <> @expected_2026_confirm_entities
BEGIN
    RAISERROR(
        '2026 CONFIRM CONTROL FLAG: raw=%I64d (exp %I64d), entities=%I64d (exp %I64d). Continuing.',
        10, 1,
        @raw_2026, @expected_2026_confirm_raw,
        @entities_2026, @expected_2026_confirm_entities
    );
END;

DROP TABLE #c2026_raw;


-- =============================================================================
-- STEP 3 — Match 2026 CONFIRM entities -> FFM target
-- =============================================================================
SET @t_phase = SYSDATETIME();
RAISERROR('STEP3 start: match 2026 CONFIRM to FFM', 10, 1) WITH NOWAIT;

IF OBJECT_ID('tempdb..#e2026_hits') IS NOT NULL DROP TABLE #e2026_hits;

;WITH e_raw AS (
    SELECT br.Business_Key, f.FFM_Policy_ID, f.FFM_Enrollee_ID
    FROM #c2026_bridge AS br
    INNER JOIN #ffm_target AS f ON f.FFM_Enrollee_ID = br.Inbound_Member_ID
    WHERE br.Inbound_Member_ID IS NOT NULL

    UNION

    SELECT br.Business_Key, f.FFM_Policy_ID, f.FFM_Enrollee_ID
    FROM #c2026_bridge AS br
    INNER JOIN #ffm_target AS f ON f.FFM_Enrollee_ID = br.Inbound_Issuer_Indiv_Identifier
    WHERE br.Inbound_Issuer_Indiv_Identifier IS NOT NULL

    UNION

    SELECT br.Business_Key, f.FFM_Policy_ID, f.FFM_Enrollee_ID
    FROM #c2026_bridge AS br
    INNER JOIN #ffm_target AS f ON f.FFM_Enrollee_ID = br.Inbound_Exchange_Assigned_Enrollee_ID
    WHERE br.Inbound_Exchange_Assigned_Enrollee_ID IS NOT NULL
)
SELECT DISTINCT Business_Key, FFM_Policy_ID, FFM_Enrollee_ID
INTO #e2026_hits
FROM e_raw;

CREATE CLUSTERED INDEX CX_e2026 ON #e2026_hits (Business_Key, FFM_Policy_ID, FFM_Enrollee_ID);

IF OBJECT_ID('tempdb..#p2026_hits') IS NOT NULL DROP TABLE #p2026_hits;

;WITH p_raw AS (
    SELECT br.Business_Key, f.FFM_Policy_ID, f.FFM_Enrollee_ID
    FROM #c2026_bridge AS br
    INNER JOIN #ffm_target AS f ON f.FFM_Policy_ID = br.Inbound_Policy_ID
    WHERE br.Inbound_Policy_ID IS NOT NULL

    UNION

    SELECT br.Business_Key, f.FFM_Policy_ID, f.FFM_Enrollee_ID
    FROM #c2026_bridge AS br
    INNER JOIN #ffm_target AS f ON f.FFM_Policy_ID = br.Inbound_Health_Coverage_Policy_No
    WHERE br.Inbound_Health_Coverage_Policy_No IS NOT NULL
)
SELECT DISTINCT Business_Key, FFM_Policy_ID, FFM_Enrollee_ID
INTO #p2026_hits
FROM p_raw;

CREATE CLUSTERED INDEX CX_p2026 ON #p2026_hits (Business_Key, FFM_Policy_ID, FFM_Enrollee_ID);

IF OBJECT_ID('tempdb..#exact_2026_entity') IS NOT NULL DROP TABLE #exact_2026_entity;

SELECT DISTINCT
    e.Business_Key,
    e.FFM_Policy_ID,
    e.FFM_Enrollee_ID
INTO #exact_2026_entity
FROM #e2026_hits AS e
INNER JOIN #p2026_hits AS p
    ON p.Business_Key = e.Business_Key
   AND p.FFM_Policy_ID = e.FFM_Policy_ID
   AND p.FFM_Enrollee_ID = e.FFM_Enrollee_ID;

CREATE CLUSTERED INDEX CX_x2026e ON #exact_2026_entity (Business_Key);
CREATE NONCLUSTERED INDEX IX_x2026_ffm ON #exact_2026_entity (FFM_Policy_ID, FFM_Enrollee_ID);

IF OBJECT_ID('tempdb..#c2026_class') IS NOT NULL DROP TABLE #c2026_class;

;WITH exact_ent AS (
    SELECT DISTINCT Business_Key FROM #exact_2026_entity
),
eel_only AS (
    SELECT DISTINCT e.Business_Key
    FROM #e2026_hits AS e
    WHERE NOT EXISTS (SELECT 1 FROM exact_ent x WHERE x.Business_Key = e.Business_Key)
),
pol_only AS (
    SELECT DISTINCT p.Business_Key
    FROM #p2026_hits AS p
    WHERE NOT EXISTS (SELECT 1 FROM exact_ent x WHERE x.Business_Key = p.Business_Key)
      AND NOT EXISTS (SELECT 1 FROM eel_only e WHERE e.Business_Key = p.Business_Key)
)
SELECT
    ent.Business_Key,
    CASE
        WHEN x.Business_Key IS NOT NULL THEN '2026_EXACT_POLICY_ENROLLEE'
        WHEN eo.Business_Key IS NOT NULL THEN '2026_ENROLLEE_DIFFERENT_POLICY'
        WHEN po.Business_Key IS NOT NULL THEN '2026_POLICY_DIFFERENT_ENROLLEE'
        ELSE '2026_NOT_IN_TARGET'
    END AS Entity_Class
INTO #c2026_class
FROM #c2026_entity AS ent
LEFT JOIN exact_ent AS x ON x.Business_Key = ent.Business_Key
LEFT JOIN eel_only AS eo ON eo.Business_Key = ent.Business_Key
LEFT JOIN pol_only AS po ON po.Business_Key = ent.Business_Key;

CREATE UNIQUE CLUSTERED INDEX CX_c2026_class ON #c2026_class (Business_Key);

DECLARE @c2026_exact BIGINT = (SELECT COUNT(*) FROM #c2026_class WHERE Entity_Class = '2026_EXACT_POLICY_ENROLLEE');
DECLARE @c2026_eel BIGINT = (SELECT COUNT(*) FROM #c2026_class WHERE Entity_Class = '2026_ENROLLEE_DIFFERENT_POLICY');
DECLARE @c2026_pol BIGINT = (SELECT COUNT(*) FROM #c2026_class WHERE Entity_Class = '2026_POLICY_DIFFERENT_ENROLLEE');
DECLARE @c2026_nit BIGINT = (SELECT COUNT(*) FROM #c2026_class WHERE Entity_Class = '2026_NOT_IN_TARGET');

IF OBJECT_ID('tempdb..#ffm_exact_2026') IS NOT NULL DROP TABLE #ffm_exact_2026;

SELECT DISTINCT FFM_Policy_ID, FFM_Enrollee_ID
INTO #ffm_exact_2026
FROM #exact_2026_entity;

CREATE UNIQUE CLUSTERED INDEX CX_ffm_x2026 ON #ffm_exact_2026 (FFM_Policy_ID, FFM_Enrollee_ID);

DECLARE @ffm_exact_2026_pairs BIGINT = (SELECT COUNT(*) FROM #ffm_exact_2026);

SET @msg = CONCAT(
    'STEP3 done in ', DATEDIFF(second, @t_phase, SYSDATETIME()),
    's; ent_exact=', @c2026_exact,
    '; eel_diff=', @c2026_eel,
    '; pol_diff=', @c2026_pol,
    '; not_in_target=', @c2026_nit,
    '; ffm_pairs_exact_via_2026=', @ffm_exact_2026_pairs
);
RAISERROR(@msg, 10, 1) WITH NOWAIT;

DROP TABLE #c2026_bridge;
DROP TABLE #e2026_hits;
DROP TABLE #p2026_hits;


-- =============================================================================
-- STEP 4 — 2025 carry-forward EXACT only (FFM-first; no full 2025 load)
-- Established evidence semantics (NOT same-physical-row):
--   A) enrollee-hit set via 3 independent enrollee ID paths
--   B) policy-hit set via 2 independent policy ID paths
--   C) intersect at FFM Policy+Enrollee grain
-- Evidence may come from different physical 2025 CONFIRM rows.
-- =============================================================================
RAISERROR('STEP4 start: 2025 exact carry-forward (FFM-first, split evidence)', 10, 1) WITH NOWAIT;

-- STEP4A — 2025 enrollee evidence -> FFM pairs (dedup immediately)
SET @t_phase = SYSDATETIME();
RAISERROR('STEP4A start: 2025 enrollee evidence', 10, 1) WITH NOWAIT;

IF OBJECT_ID('tempdb..#ffm_eel_2025') IS NOT NULL DROP TABLE #ffm_eel_2025;

;WITH eel_hit AS (
    SELECT f.FFM_Policy_ID, f.FFM_Enrollee_ID
    FROM #ffm_target AS f
    INNER JOIN dbo.inbound_automation AS ia
        ON ia.coverage_year = 2025
       AND UPPER(LTRIM(RTRIM(ia.enrolleeStatus))) = 'CONFIRM'
       AND NULLIF(LTRIM(RTRIM(CAST(ia.member_id AS VARCHAR(100)))), '') = f.FFM_Enrollee_ID

    UNION

    SELECT f.FFM_Policy_ID, f.FFM_Enrollee_ID
    FROM #ffm_target AS f
    INNER JOIN dbo.inbound_automation AS ia
        ON ia.coverage_year = 2025
       AND UPPER(LTRIM(RTRIM(ia.enrolleeStatus))) = 'CONFIRM'
       AND NULLIF(LTRIM(RTRIM(CAST(ia.issuer_indiv_identifier AS VARCHAR(100)))), '') = f.FFM_Enrollee_ID

    UNION

    SELECT f.FFM_Policy_ID, f.FFM_Enrollee_ID
    FROM #ffm_target AS f
    INNER JOIN dbo.inbound_automation AS ia
        ON ia.coverage_year = 2025
       AND UPPER(LTRIM(RTRIM(ia.enrolleeStatus))) = 'CONFIRM'
       AND NULLIF(LTRIM(RTRIM(CAST(ia.exchg_assigned_enrollee_id AS VARCHAR(100)))), '') = f.FFM_Enrollee_ID
)
SELECT DISTINCT FFM_Policy_ID, FFM_Enrollee_ID
INTO #ffm_eel_2025
FROM eel_hit;

CREATE UNIQUE CLUSTERED INDEX CX_ffm_eel_2025
    ON #ffm_eel_2025 (FFM_Policy_ID, FFM_Enrollee_ID);

DECLARE @eel_2025_pairs BIGINT = (SELECT COUNT(*) FROM #ffm_eel_2025);

SET @msg = CONCAT(
    'STEP4A done in ', DATEDIFF(second, @t_phase, SYSDATETIME()),
    's; ffm_pairs_with_2025_enrollee_evidence=', @eel_2025_pairs
);
RAISERROR(@msg, 10, 1) WITH NOWAIT;

-- STEP4B — 2025 policy evidence -> FFM pairs (dedup immediately)
SET @t_phase = SYSDATETIME();
RAISERROR('STEP4B start: 2025 policy evidence', 10, 1) WITH NOWAIT;

IF OBJECT_ID('tempdb..#ffm_pol_2025') IS NOT NULL DROP TABLE #ffm_pol_2025;

;WITH pol_hit AS (
    SELECT f.FFM_Policy_ID, f.FFM_Enrollee_ID
    FROM #ffm_target AS f
    INNER JOIN dbo.inbound_automation AS ia
        ON ia.coverage_year = 2025
       AND UPPER(LTRIM(RTRIM(ia.enrolleeStatus))) = 'CONFIRM'
       AND NULLIF(LTRIM(RTRIM(CAST(ia.policy_id AS VARCHAR(100)))), '') = f.FFM_Policy_ID

    UNION

    SELECT f.FFM_Policy_ID, f.FFM_Enrollee_ID
    FROM #ffm_target AS f
    INNER JOIN dbo.inbound_automation AS ia
        ON ia.coverage_year = 2025
       AND UPPER(LTRIM(RTRIM(ia.enrolleeStatus))) = 'CONFIRM'
       AND NULLIF(LTRIM(RTRIM(CAST(ia.health_coverage_policy_no AS VARCHAR(100)))), '') = f.FFM_Policy_ID
)
SELECT DISTINCT FFM_Policy_ID, FFM_Enrollee_ID
INTO #ffm_pol_2025
FROM pol_hit;

CREATE UNIQUE CLUSTERED INDEX CX_ffm_pol_2025
    ON #ffm_pol_2025 (FFM_Policy_ID, FFM_Enrollee_ID);

DECLARE @pol_2025_pairs BIGINT = (SELECT COUNT(*) FROM #ffm_pol_2025);

SET @msg = CONCAT(
    'STEP4B done in ', DATEDIFF(second, @t_phase, SYSDATETIME()),
    's; ffm_pairs_with_2025_policy_evidence=', @pol_2025_pairs
);
RAISERROR(@msg, 10, 1) WITH NOWAIT;

-- STEP4C — Intersect enrollee + policy evidence at same FFM pair
SET @t_phase = SYSDATETIME();
RAISERROR('STEP4C start: intersect exact FFM pairs', 10, 1) WITH NOWAIT;

IF OBJECT_ID('tempdb..#ffm_exact_2025') IS NOT NULL DROP TABLE #ffm_exact_2025;

SELECT e.FFM_Policy_ID, e.FFM_Enrollee_ID
INTO #ffm_exact_2025
FROM #ffm_eel_2025 AS e
INNER JOIN #ffm_pol_2025 AS p
    ON p.FFM_Policy_ID = e.FFM_Policy_ID
   AND p.FFM_Enrollee_ID = e.FFM_Enrollee_ID;

CREATE UNIQUE CLUSTERED INDEX CX_ffm_x2025
    ON #ffm_exact_2025 (FFM_Policy_ID, FFM_Enrollee_ID);

DECLARE @ffm_exact_2025_pairs BIGINT = (SELECT COUNT(*) FROM #ffm_exact_2025);

SET @msg = CONCAT(
    'STEP4C done in ', DATEDIFF(second, @t_phase, SYSDATETIME()),
    's; ffm_pairs_exact_via_2025=', @ffm_exact_2025_pairs
);
RAISERROR(@msg, 10, 1) WITH NOWAIT;

/* Hit sets no longer needed after intersect */
DROP TABLE #ffm_eel_2025;
DROP TABLE #ffm_pol_2025;


-- =============================================================================
-- STEP 5 — Prevent double-count of exact FFM pairs; focused summary
-- =============================================================================
SET @t_phase = SYSDATETIME();
RAISERROR('STEP5 start: focused mutually exclusive summary', 10, 1) WITH NOWAIT;

DECLARE @exact_2025_only BIGINT = (
    SELECT COUNT(*)
    FROM #ffm_exact_2025 AS a
    WHERE NOT EXISTS (
        SELECT 1 FROM #ffm_exact_2026 AS b
        WHERE b.FFM_Policy_ID = a.FFM_Policy_ID
          AND b.FFM_Enrollee_ID = a.FFM_Enrollee_ID
    )
);

DECLARE @exact_2026_only BIGINT = (
    SELECT COUNT(*)
    FROM #ffm_exact_2026 AS a
    WHERE NOT EXISTS (
        SELECT 1 FROM #ffm_exact_2025 AS b
        WHERE b.FFM_Policy_ID = a.FFM_Policy_ID
          AND b.FFM_Enrollee_ID = a.FFM_Enrollee_ID
    )
);

DECLARE @exact_overlap BIGINT = (
    SELECT COUNT(*)
    FROM #ffm_exact_2025 AS a
    INNER JOIN #ffm_exact_2026 AS b
        ON b.FFM_Policy_ID = a.FFM_Policy_ID
       AND b.FFM_Enrollee_ID = a.FFM_Enrollee_ID
);

DECLARE @focused_total BIGINT =
      @exact_2025_only
    + @exact_2026_only
    + @exact_overlap
    + @c2026_eel
    + @c2026_pol
    + @c2026_nit;

SET @msg = CONCAT(
    'STEP5 done in ', DATEDIFF(second, @t_phase, SYSDATETIME()),
    's; focused_total=', @focused_total,
    '; total_elapsed_s=', DATEDIFF(second, @t0, SYSDATETIME())
);
RAISERROR(@msg, 10, 1) WITH NOWAIT;


-- =============================================================================
-- RESULT 1 — 2026 entity classification counts (validation; not forced)
-- =============================================================================
SELECT
    Entity_Class AS Population_Category,
    COUNT(*) AS Entity_Count,
    CAST(100.0 * COUNT(*) / NULLIF(@entities_2026, 0) AS DECIMAL(10, 4)) AS Percent_of_2026_Entities
FROM #c2026_class
GROUP BY Entity_Class;


-- =============================================================================
-- RESULT 2 — Focused mutually exclusive summary
-- Exact buckets = distinct FFM Policy+Enrollee pairs
-- Non-exact buckets = distinct 2026 inbound business entities
-- =============================================================================
SELECT
    Population_Category,
    Count_Value AS [Count],
    CAST(100.0 * Count_Value / NULLIF(@focused_total, 0) AS DECIMAL(10, 4)) AS Percent_of_Focused_Total
FROM (VALUES
    ('2025_EXACT_CARRY_FORWARD_ONLY', @exact_2025_only),
    ('2026_EXACT', @exact_2026_only),
    ('2025_AND_2026_EXACT_OVERLAP', @exact_overlap),
    ('2026_ENROLLEE_DIFFERENT_POLICY', @c2026_eel),
    ('2026_POLICY_DIFFERENT_ENROLLEE', @c2026_pol),
    ('2026_NOT_IN_TARGET', @c2026_nit)
) AS v(Population_Category, Count_Value);


-- =============================================================================
-- RESULT 3 — Final controls vs FFM 960,531 (signed difference only)
-- =============================================================================
SELECT
    metric,
    value_count,
    note
FROM (VALUES
    ('ffm_target_enrolled', @ffm_enrolled, 'control 945,039'),
    ('ffm_target_pending', @ffm_pending, 'control 15,492'),
    ('ffm_target_total', @ffm_total, 'control 960,531'),
    ('inbound_2026_confirm_raw', @raw_2026, 'control 551,208 if unchanged'),
    ('inbound_2026_confirm_entities', @entities_2026, 'control 501,369 if unchanged'),
    ('ffm_pairs_exact_via_2025_confirm', @ffm_exact_2025_pairs, 'observed; not forced'),
    ('ffm_pairs_exact_via_2026_confirm', @ffm_exact_2026_pairs, 'observed; not forced'),
    ('final_focused_distinct_population', @focused_total,
        '2025_only_exact + 2026_only_exact + overlap + 2026 non-exact entities'),
    ('numeric_difference_focused_minus_FFM', (@focused_total - @ffm_total),
        'Signed difference only — not labeled missing'),
    ('numeric_difference_FFM_minus_focused', (@ffm_total - @focused_total),
        'Signed difference only — not labeled missing')
) AS v(metric, value_count, note);

SET @msg = CONCAT('ALL DONE; total_elapsed_s=', DATEDIFF(second, @t0, SYSDATETIME()));
RAISERROR(@msg, 10, 1) WITH NOWAIT;
