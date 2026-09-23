


-- =============================================================================
-- EXPORT 2 — 2026 CONFIRM business entities NOT exact in FFM target
-- =============================================================================
-- Source: 2026 inbound CONFIRM only (validated reverse entity methodology).
-- Exclude exact Policy+Enrollee matches.
-- Export mutually exclusive:
--   ENROLLEE_IN_TARGET_DIFFERENT_POLICY
--   POLICY_IN_TARGET_DIFFERENT_ENROLLEE
--   INBOUND_CONFIRM_NOT_IN_FFM_TARGET
-- Do NOT include 2025 unmatched. No STRING_AGG. No all-year diagnostics.
-- READ ONLY. Temp tables only. No RCNI.
-- =============================================================================

SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @coverage_year INT = 2026;
DECLARE @expected_ffm BIGINT = 960531;
DECLARE @expected_2026_raw BIGINT = 551208;
DECLARE @expected_2026_entities BIGINT = 501369;

DECLARE @t0 DATETIME2 = SYSDATETIME();
DECLARE @msg NVARCHAR(400);

RAISERROR('EXPORT2 STEP1: FFM target', 10, 1) WITH NOWAIT;

IF OBJECT_ID('tempdb..#ffm_target') IS NOT NULL DROP TABLE #ffm_target;

SELECT
    e.coverage_year AS FFM_Coverage_Year,
    CAST(e.enrollment_id AS VARCHAR(100)) AS FFM_Policy_ID,
    CAST(e.enrollee_id AS VARCHAR(100)) AS FFM_Enrollee_ID,
    CAST(e.hios_issuer_id AS VARCHAR(20)) AS FFM_Issuer,
    e.enrollment_status_description AS FFM_Enrollment_Status,
    e.enrollee_status_description AS FFM_Enrollee_Status
INTO #ffm_target
FROM (
    SELECT
        e.coverage_year,
        e.enrollment_id,
        e.enrollee_id,
        e.hios_issuer_id,
        e.enrollment_status_description,
        e.enrollee_status_description,
        ROW_NUMBER() OVER (
            PARTITION BY e.coverage_year, e.enrollment_id, e.enrollee_id
            ORDER BY e.enrollment_last_update_date DESC, e.enrollment_create_date DESC
        ) AS _rn
    FROM dbo.Enrollments_TEST AS e
    WHERE e.coverage_year = @coverage_year
      AND UPPER(LTRIM(RTRIM(e.enrollment_status_description))) IN ('ENROLLED', 'PENDING')
) AS e
WHERE e._rn = 1;

CREATE UNIQUE CLUSTERED INDEX CX_ffm
    ON #ffm_target (FFM_Coverage_Year, FFM_Policy_ID, FFM_Enrollee_ID);
CREATE NONCLUSTERED INDEX IX_ffm_eel
    ON #ffm_target (FFM_Enrollee_ID) INCLUDE (FFM_Policy_ID, FFM_Issuer, FFM_Enrollment_Status, FFM_Enrollee_Status);
CREATE NONCLUSTERED INDEX IX_ffm_pol
    ON #ffm_target (FFM_Policy_ID) INCLUDE (FFM_Enrollee_ID, FFM_Issuer, FFM_Enrollment_Status, FFM_Enrollee_Status);

DECLARE @ffm_count BIGINT = (SELECT COUNT(*) FROM #ffm_target);
SET @msg = CONCAT('EXPORT2 FFM=', @ffm_count, ' elapsed_s=', DATEDIFF(second, @t0, SYSDATETIME()));
RAISERROR(@msg, 10, 1) WITH NOWAIT;

IF @ffm_count <> @expected_ffm
BEGIN
    RAISERROR('EXPORT2 STOP: FFM target %I64d <> expected %I64d', 16, 1, @ffm_count, @expected_ffm);
    RETURN;
END;

RAISERROR('EXPORT2 STEP2: 2026 CONFIRM entities', 10, 1) WITH NOWAIT;

IF OBJECT_ID('tempdb..#c2026_raw') IS NOT NULL DROP TABLE #c2026_raw;

SELECT
    ia.id AS inbound_row_id,
    CAST(ia.issuer AS VARCHAR(20)) AS Inbound_Issuer,
    ia.coverage_year AS Inbound_Coverage_Year,
    NULLIF(LTRIM(RTRIM(CAST(ia.member_id AS VARCHAR(100)))), '') AS Inbound_Member_ID,
    NULLIF(LTRIM(RTRIM(CAST(ia.issuer_indiv_identifier AS VARCHAR(100)))), '') AS Inbound_Issuer_Indiv_Identifier,
    NULLIF(LTRIM(RTRIM(CAST(ia.exchg_assigned_enrollee_id AS VARCHAR(100)))), '') AS Inbound_Exchange_Assigned_Enrollee_ID,
    NULLIF(LTRIM(RTRIM(CAST(ia.policy_id AS VARCHAR(100)))), '') AS Inbound_Policy_ID,
    NULLIF(LTRIM(RTRIM(CAST(ia.health_coverage_policy_no AS VARCHAR(100)))), '') AS Inbound_Health_Coverage_Policy_No,
    ia.enrolleeStatus AS Inbound_Status,
    ia.member_maint_effective_date,
    ia.benefit_effective_date,
    ia.benefit_end_date,
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
INTO #c2026_raw
FROM dbo.inbound_automation AS ia
WHERE ia.coverage_year = 2026
  AND UPPER(LTRIM(RTRIM(ia.enrolleeStatus))) = 'CONFIRM';

DECLARE @raw_2026 BIGINT = (SELECT COUNT(*) FROM #c2026_raw);

IF OBJECT_ID('tempdb..#bridge') IS NOT NULL DROP TABLE #bridge;

SELECT
    CAST(r.Inbound_Issuer AS VARCHAR(20))
        + N'|' + CAST(r.Inbound_Coverage_Year AS VARCHAR(10))
        + N'|' + r.Canonical_Policy_Key
        + N'|' + r.Canonical_Enrollee_Key AS Inbound_Business_Key,
    r.*
INTO #bridge
FROM #c2026_raw AS r
WHERE r.Canonical_Enrollee_Key IS NOT NULL
  AND r.Canonical_Policy_Key IS NOT NULL;

DROP TABLE #c2026_raw;

CREATE CLUSTERED INDEX CX_bridge ON #bridge (Inbound_Business_Key, inbound_row_id);
CREATE NONCLUSTERED INDEX IX_br_member ON #bridge (Inbound_Member_ID) INCLUDE (Inbound_Business_Key);
CREATE NONCLUSTERED INDEX IX_br_ii ON #bridge (Inbound_Issuer_Indiv_Identifier) INCLUDE (Inbound_Business_Key);
CREATE NONCLUSTERED INDEX IX_br_ex ON #bridge (Inbound_Exchange_Assigned_Enrollee_ID) INCLUDE (Inbound_Business_Key);
CREATE NONCLUSTERED INDEX IX_br_pol ON #bridge (Inbound_Policy_ID) INCLUDE (Inbound_Business_Key);
CREATE NONCLUSTERED INDEX IX_br_hc ON #bridge (Inbound_Health_Coverage_Policy_No) INCLUDE (Inbound_Business_Key);

IF OBJECT_ID('tempdb..#entity') IS NOT NULL DROP TABLE #entity;

SELECT DISTINCT
    Inbound_Business_Key,
    Inbound_Issuer,
    Inbound_Coverage_Year,
    Canonical_Policy_Key,
    Canonical_Enrollee_Key
INTO #entity
FROM #bridge;

CREATE UNIQUE CLUSTERED INDEX CX_entity ON #entity (Inbound_Business_Key);

DECLARE @entities BIGINT = (SELECT COUNT(*) FROM #entity);
SET @msg = CONCAT(
    'EXPORT2 raw=', @raw_2026, ' entities=', @entities,
    ' elapsed_s=', DATEDIFF(second, @t0, SYSDATETIME())
);
RAISERROR(@msg, 10, 1) WITH NOWAIT;

IF @raw_2026 <> @expected_2026_raw OR @entities <> @expected_2026_entities
BEGIN
    RAISERROR(
        'EXPORT2 FLAG: 2026 CONFIRM raw=%I64d (exp %I64d), entities=%I64d (exp %I64d). Continuing with observed.',
        10, 1, @raw_2026, @expected_2026_raw, @entities, @expected_2026_entities
    );
END;

RAISERROR('EXPORT2 STEP3: match to FFM (validated reverse semantics)', 10, 1) WITH NOWAIT;

IF OBJECT_ID('tempdb..#eel_hits') IS NOT NULL DROP TABLE #eel_hits;

;WITH e_raw AS (
    SELECT br.Inbound_Business_Key, f.FFM_Coverage_Year, f.FFM_Policy_ID, f.FFM_Enrollee_ID,
           f.FFM_Issuer, f.FFM_Enrollment_Status, f.FFM_Enrollee_Status
    FROM #bridge AS br
    INNER JOIN #ffm_target AS f ON f.FFM_Enrollee_ID = br.Inbound_Member_ID
    WHERE br.Inbound_Member_ID IS NOT NULL
    UNION
    SELECT br.Inbound_Business_Key, f.FFM_Coverage_Year, f.FFM_Policy_ID, f.FFM_Enrollee_ID,
           f.FFM_Issuer, f.FFM_Enrollment_Status, f.FFM_Enrollee_Status
    FROM #bridge AS br
    INNER JOIN #ffm_target AS f ON f.FFM_Enrollee_ID = br.Inbound_Issuer_Indiv_Identifier
    WHERE br.Inbound_Issuer_Indiv_Identifier IS NOT NULL
    UNION
    SELECT br.Inbound_Business_Key, f.FFM_Coverage_Year, f.FFM_Policy_ID, f.FFM_Enrollee_ID,
           f.FFM_Issuer, f.FFM_Enrollment_Status, f.FFM_Enrollee_Status
    FROM #bridge AS br
    INNER JOIN #ffm_target AS f ON f.FFM_Enrollee_ID = br.Inbound_Exchange_Assigned_Enrollee_ID
    WHERE br.Inbound_Exchange_Assigned_Enrollee_ID IS NOT NULL
)
SELECT DISTINCT *
INTO #eel_hits
FROM e_raw;

CREATE CLUSTERED INDEX CX_eel ON #eel_hits (Inbound_Business_Key, FFM_Policy_ID, FFM_Enrollee_ID);

IF OBJECT_ID('tempdb..#pol_hits') IS NOT NULL DROP TABLE #pol_hits;

;WITH p_raw AS (
    SELECT br.Inbound_Business_Key, f.FFM_Coverage_Year, f.FFM_Policy_ID, f.FFM_Enrollee_ID,
           f.FFM_Issuer, f.FFM_Enrollment_Status, f.FFM_Enrollee_Status
    FROM #bridge AS br
    INNER JOIN #ffm_target AS f ON f.FFM_Policy_ID = br.Inbound_Policy_ID
    WHERE br.Inbound_Policy_ID IS NOT NULL
    UNION
    SELECT br.Inbound_Business_Key, f.FFM_Coverage_Year, f.FFM_Policy_ID, f.FFM_Enrollee_ID,
           f.FFM_Issuer, f.FFM_Enrollment_Status, f.FFM_Enrollee_Status
    FROM #bridge AS br
    INNER JOIN #ffm_target AS f ON f.FFM_Policy_ID = br.Inbound_Health_Coverage_Policy_No
    WHERE br.Inbound_Health_Coverage_Policy_No IS NOT NULL
)
SELECT DISTINCT *
INTO #pol_hits
FROM p_raw;

CREATE CLUSTERED INDEX CX_pol ON #pol_hits (Inbound_Business_Key, FFM_Policy_ID, FFM_Enrollee_ID);

IF OBJECT_ID('tempdb..#exact_hits') IS NOT NULL DROP TABLE #exact_hits;

SELECT DISTINCT e.Inbound_Business_Key
INTO #exact_hits
FROM #eel_hits AS e
INNER JOIN #pol_hits AS p
    ON p.Inbound_Business_Key = e.Inbound_Business_Key
   AND p.FFM_Policy_ID = e.FFM_Policy_ID
   AND p.FFM_Enrollee_ID = e.FFM_Enrollee_ID;

CREATE UNIQUE CLUSTERED INDEX CX_exact ON #exact_hits (Inbound_Business_Key);

/* One best FFM evidence row per entity for non-exact categories */
IF OBJECT_ID('tempdb..#eel_only_best') IS NOT NULL DROP TABLE #eel_only_best;
SELECT * INTO #eel_only_best FROM (
    SELECT e.*,
           ROW_NUMBER() OVER (
               PARTITION BY e.Inbound_Business_Key
               ORDER BY e.FFM_Policy_ID, e.FFM_Enrollee_ID
           ) AS rn
    FROM #eel_hits AS e
    WHERE NOT EXISTS (SELECT 1 FROM #exact_hits x WHERE x.Inbound_Business_Key = e.Inbound_Business_Key)
) z WHERE rn = 1;

CREATE UNIQUE CLUSTERED INDEX CX_eel_only ON #eel_only_best (Inbound_Business_Key);

IF OBJECT_ID('tempdb..#pol_only_best') IS NOT NULL DROP TABLE #pol_only_best;
SELECT * INTO #pol_only_best FROM (
    SELECT p.*,
           ROW_NUMBER() OVER (
               PARTITION BY p.Inbound_Business_Key
               ORDER BY p.FFM_Policy_ID, p.FFM_Enrollee_ID
           ) AS rn
    FROM #pol_hits AS p
    WHERE NOT EXISTS (SELECT 1 FROM #exact_hits x WHERE x.Inbound_Business_Key = p.Inbound_Business_Key)
      AND NOT EXISTS (SELECT 1 FROM #eel_only_best e WHERE e.Inbound_Business_Key = p.Inbound_Business_Key)
) z WHERE rn = 1;

CREATE UNIQUE CLUSTERED INDEX CX_pol_only ON #pol_only_best (Inbound_Business_Key);

/* Representative physical inbound row per entity (latest maint / id) for export display */
IF OBJECT_ID('tempdb..#rep') IS NOT NULL DROP TABLE #rep;
SELECT * INTO #rep FROM (
    SELECT
        b.*,
        ROW_NUMBER() OVER (
            PARTITION BY b.Inbound_Business_Key
            ORDER BY
                b.member_maint_effective_date DESC,
                b.inbound_row_id DESC
        ) AS rn
    FROM #bridge AS b
) z WHERE rn = 1;

CREATE UNIQUE CLUSTERED INDEX CX_rep ON #rep (Inbound_Business_Key);

IF OBJECT_ID('tempdb..#non_exact') IS NOT NULL DROP TABLE #non_exact;

SELECT
    CASE
        WHEN eo.Inbound_Business_Key IS NOT NULL THEN 'ENROLLEE_IN_TARGET_DIFFERENT_POLICY'
        WHEN po.Inbound_Business_Key IS NOT NULL THEN 'POLICY_IN_TARGET_DIFFERENT_ENROLLEE'
        ELSE 'INBOUND_CONFIRM_NOT_IN_FFM_TARGET'
    END AS Difference_Category,
    CASE
        WHEN eo.Inbound_Business_Key IS NOT NULL
            THEN 'Enrollee ID found in 2026 FFM target; policy IDs differ'
        WHEN po.Inbound_Business_Key IS NOT NULL
            THEN 'Policy ID found in 2026 FFM target; enrollee IDs differ'
        ELSE 'No enrollee or policy evidence in 2026 FFM Enrolled/Pending target'
    END AS Match_Reason,
    r.Inbound_Coverage_Year,
    r.Inbound_Issuer,
    r.Inbound_Policy_ID,
    r.Inbound_Health_Coverage_Policy_No,
    r.Inbound_Member_ID,
    r.Inbound_Issuer_Indiv_Identifier,
    r.Inbound_Exchange_Assigned_Enrollee_ID,
    r.Inbound_Status,
    r.member_maint_effective_date AS Member_Maint_Effective_Date,
    r.benefit_effective_date AS Benefit_Effective_Date,
    r.benefit_end_date AS Benefit_End_Date,
    r.Inbound_Source_File AS Source_File,
    COALESCE(eo.FFM_Coverage_Year, po.FFM_Coverage_Year) AS FFM_Coverage_Year,
    COALESCE(eo.FFM_Issuer, po.FFM_Issuer) AS FFM_Issuer,
    COALESCE(eo.FFM_Policy_ID, po.FFM_Policy_ID) AS FFM_Policy_ID,
    COALESCE(eo.FFM_Enrollee_ID, po.FFM_Enrollee_ID) AS FFM_Enrollee_ID,
    COALESCE(eo.FFM_Enrollment_Status, po.FFM_Enrollment_Status) AS FFM_Enrollment_Status,
    COALESCE(eo.FFM_Enrollee_Status, po.FFM_Enrollee_Status) AS FFM_Enrollee_Status,
    ent.Inbound_Business_Key
INTO #non_exact
FROM #entity AS ent
INNER JOIN #rep AS r
    ON r.Inbound_Business_Key = ent.Inbound_Business_Key
LEFT JOIN #eel_only_best AS eo
    ON eo.Inbound_Business_Key = ent.Inbound_Business_Key
LEFT JOIN #pol_only_best AS po
    ON po.Inbound_Business_Key = ent.Inbound_Business_Key
WHERE NOT EXISTS (
    SELECT 1 FROM #exact_hits x WHERE x.Inbound_Business_Key = ent.Inbound_Business_Key
);

CREATE CLUSTERED INDEX CX_non_exact ON #non_exact (Difference_Category, Inbound_Business_Key);

DECLARE @export_count BIGINT = (SELECT COUNT(*) FROM #non_exact);
DECLARE @exact_excluded BIGINT = (SELECT COUNT(*) FROM #exact_hits);
DECLARE @cat_eel BIGINT = (SELECT COUNT(*) FROM #non_exact WHERE Difference_Category = 'ENROLLEE_IN_TARGET_DIFFERENT_POLICY');
DECLARE @cat_pol BIGINT = (SELECT COUNT(*) FROM #non_exact WHERE Difference_Category = 'POLICY_IN_TARGET_DIFFERENT_ENROLLEE');
DECLARE @cat_nit BIGINT = (SELECT COUNT(*) FROM #non_exact WHERE Difference_Category = 'INBOUND_CONFIRM_NOT_IN_FFM_TARGET');

SET @msg = CONCAT(
    'EXPORT2 non_exact=', @export_count,
    ' exact_excluded=', @exact_excluded,
    ' elapsed_s=', DATEDIFF(second, @t0, SYSDATETIME())
);
RAISERROR(@msg, 10, 1) WITH NOWAIT;

-- CONTROL
SELECT
    @entities AS confirm_2026_entities,
    @exact_excluded AS exact_excluded,
    @export_count AS non_exact_export_count,
    @cat_eel AS enrollee_different_policy_count,
    @cat_pol AS policy_different_enrollee_count,
    @cat_nit AS not_in_ffm_target_count,
    CASE
        WHEN (@exact_excluded + @export_count) = @entities THEN 'PASS_PARTITION'
        ELSE 'FLAG_PARTITION_DRIFT'
    END AS partition_control,
    CASE
        WHEN @export_count = (@cat_eel + @cat_pol + @cat_nit) THEN 'PASS_CATEGORY_SUM'
        ELSE 'FAIL_CATEGORY_SUM'
    END AS category_control;

-- EXPORT ROWS
SELECT
    Difference_Category,
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
    FFM_Coverage_Year,
    FFM_Issuer,
    FFM_Policy_ID,
    FFM_Enrollee_ID,
    FFM_Enrollment_Status,
    FFM_Enrollee_Status,
    Match_Reason
FROM #non_exact;

RAISERROR('EXPORT2 DONE', 10, 1) WITH NOWAIT;
