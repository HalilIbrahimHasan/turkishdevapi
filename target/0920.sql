-- =============================================================================
-- YEAR-CARRY-FORWARD HYPOTHESIS — Independent population reconciliation
-- =============================================================================
-- Business question:
--   Is the gap between 2026 inbound CONFIRM and the 2026 FFM Enrolled/Pending
--   target largely explained by CONFIRM entities stored under inbound CY 2025?
--
-- Populations built INDEPENDENTLY (not from the 755,548 forward exact subset):
--   A) dbo.Enrollments_TEST 2026 Enrolled/Pending  (expected 960,531)
--   B) dbo.inbound_automation CONFIRM for CY 2025 + CY 2026
--
-- Entity methodology (from reverse reconciliation):
--   Per-year key:   issuer | coverage_year | Canonical_Policy | Canonical_Enrollee
--   Cross-year key: issuer | Canonical_Policy | Canonical_Enrollee
--                   (used for 2025/2026 overlap + combined UNION DISTINCT)
--   Matching uses FULL physical evidence bridges (no COALESCE-hidden IDs).
--
-- Does NOT modify forward/reverse queries. READ ONLY. Temp tables only. No RCNI.
-- Do NOT force ~900K — test the hypothesis.
-- =============================================================================

SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @ffm_year INT = 2026;
DECLARE @expected_ffm_total BIGINT = 960531;
DECLARE @expected_ffm_enrolled BIGINT = 945039;
DECLARE @expected_ffm_pending BIGINT = 15492;
DECLARE @expected_2026_confirm_raw BIGINT = 551208;
DECLARE @expected_2026_confirm_entities BIGINT = 501369;
DECLARE @enforce_expected BIT = 1;

DECLARE @t0 DATETIME2 = SYSDATETIME();
DECLARE @t_phase DATETIME2 = SYSDATETIME();
DECLARE @msg NVARCHAR(400);


-- =============================================================================
-- POPULATION A — 2026 FFM Enrolled/Pending target
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
        WHEN UPPER(LTRIM(RTRIM(e.enrollment_status_description))) = 'ENROLLED' THEN 'ENROLLED'
        WHEN UPPER(LTRIM(RTRIM(e.enrollment_status_description))) = 'PENDING'  THEN 'PENDING'
        ELSE 'OTHER'
    END AS FFM_Enrollment_Status_Bucket
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
    WHERE e.coverage_year = @ffm_year
      AND UPPER(LTRIM(RTRIM(e.enrollment_status_description))) IN ('ENROLLED', 'PENDING')
) AS e
WHERE e._rn = 1;

CREATE UNIQUE CLUSTERED INDEX CX_ffm
    ON #ffm_target (FFM_Coverage_Year, FFM_Policy_ID, FFM_Enrollee_ID);
CREATE NONCLUSTERED INDEX IX_ffm_eel
    ON #ffm_target (FFM_Enrollee_ID) INCLUDE (FFM_Policy_ID, FFM_Issuer, FFM_Enrollment_Status);
CREATE NONCLUSTERED INDEX IX_ffm_pol
    ON #ffm_target (FFM_Policy_ID) INCLUDE (FFM_Enrollee_ID, FFM_Issuer, FFM_Enrollment_Status);

DECLARE @ffm_total BIGINT = (SELECT COUNT(*) FROM #ffm_target);
DECLARE @ffm_enrolled BIGINT = (
    SELECT COUNT(*) FROM #ffm_target WHERE FFM_Enrollment_Status_Bucket = 'ENROLLED'
);
DECLARE @ffm_pending BIGINT = (
    SELECT COUNT(*) FROM #ffm_target WHERE FFM_Enrollment_Status_Bucket = 'PENDING'
);

SET @msg = CONCAT(
    'PHASE1 done in ', DATEDIFF(second, @t_phase, SYSDATETIME()),
    's; ffm_total=', @ffm_total,
    '; enrolled=', @ffm_enrolled,
    '; pending=', @ffm_pending
);
RAISERROR(@msg, 10, 1) WITH NOWAIT;

IF @enforce_expected = 1 AND (
       @ffm_total <> @expected_ffm_total
    OR @ffm_enrolled <> @expected_ffm_enrolled
    OR @ffm_pending <> @expected_ffm_pending
)
BEGIN
    RAISERROR(
        'FFM TARGET DRIFT: total=%I64d (exp %I64d), enrolled=%I64d (exp %I64d), pending=%I64d (exp %I64d). Aborting.',
        16, 1,
        @ffm_total, @expected_ffm_total,
        @ffm_enrolled, @expected_ffm_enrolled,
        @ffm_pending, @expected_ffm_pending
    );
    RETURN;
END;


-- =============================================================================
-- POPULATION B — Independent inbound CONFIRM (2025 + 2026)
-- =============================================================================
SET @t_phase = SYSDATETIME();
RAISERROR('PHASE2 start: independent inbound CONFIRM 2025+2026', 10, 1) WITH NOWAIT;

IF OBJECT_ID('tempdb..#confirm_raw') IS NOT NULL DROP TABLE #confirm_raw;

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
INTO #confirm_raw
FROM dbo.inbound_automation AS ia
WHERE ia.coverage_year IN (2025, 2026)
  AND UPPER(LTRIM(RTRIM(ia.enrolleeStatus))) = 'CONFIRM';

CREATE CLUSTERED INDEX CX_confirm_raw
    ON #confirm_raw (Inbound_Coverage_Year, inbound_row_id);

DECLARE @raw_2025 BIGINT = (SELECT COUNT(*) FROM #confirm_raw WHERE Inbound_Coverage_Year = 2025);
DECLARE @raw_2026 BIGINT = (SELECT COUNT(*) FROM #confirm_raw WHERE Inbound_Coverage_Year = 2026);
DECLARE @complete_2025 BIGINT = (
    SELECT COUNT(*) FROM #confirm_raw
    WHERE Inbound_Coverage_Year = 2025
      AND Canonical_Enrollee_Key IS NOT NULL
      AND Canonical_Policy_Key IS NOT NULL
);
DECLARE @complete_2026 BIGINT = (
    SELECT COUNT(*) FROM #confirm_raw
    WHERE Inbound_Coverage_Year = 2026
      AND Canonical_Enrollee_Key IS NOT NULL
      AND Canonical_Policy_Key IS NOT NULL
);

IF OBJECT_ID('tempdb..#confirm_bridge') IS NOT NULL DROP TABLE #confirm_bridge;

SELECT
    CAST(r.Inbound_Issuer AS VARCHAR(20))
        + N'|' + CAST(r.Inbound_Coverage_Year AS VARCHAR(10))
        + N'|' + r.Canonical_Policy_Key
        + N'|' + r.Canonical_Enrollee_Key AS Year_Business_Key,
    CAST(r.Inbound_Issuer AS VARCHAR(20))
        + N'|' + r.Canonical_Policy_Key
        + N'|' + r.Canonical_Enrollee_Key AS Combined_Business_Key,
    r.*
INTO #confirm_bridge
FROM #confirm_raw AS r
WHERE r.Canonical_Enrollee_Key IS NOT NULL
  AND r.Canonical_Policy_Key IS NOT NULL;

CREATE CLUSTERED INDEX CX_bridge_comb
    ON #confirm_bridge (Combined_Business_Key, Inbound_Coverage_Year, inbound_row_id);
CREATE NONCLUSTERED INDEX IX_bridge_year_key
    ON #confirm_bridge (Year_Business_Key);
CREATE NONCLUSTERED INDEX IX_br_member
    ON #confirm_bridge (Inbound_Member_ID) INCLUDE (Combined_Business_Key);
CREATE NONCLUSTERED INDEX IX_br_issuer_indiv
    ON #confirm_bridge (Inbound_Issuer_Indiv_Identifier) INCLUDE (Combined_Business_Key);
CREATE NONCLUSTERED INDEX IX_br_exchg
    ON #confirm_bridge (Inbound_Exchange_Assigned_Enrollee_ID) INCLUDE (Combined_Business_Key);
CREATE NONCLUSTERED INDEX IX_br_policy
    ON #confirm_bridge (Inbound_Policy_ID) INCLUDE (Combined_Business_Key);
CREATE NONCLUSTERED INDEX IX_br_hc
    ON #confirm_bridge (Inbound_Health_Coverage_Policy_No) INCLUDE (Combined_Business_Key);

IF OBJECT_ID('tempdb..#entity_2025') IS NOT NULL DROP TABLE #entity_2025;
IF OBJECT_ID('tempdb..#entity_2026') IS NOT NULL DROP TABLE #entity_2026;

SELECT DISTINCT
    Year_Business_Key,
    Combined_Business_Key,
    Inbound_Issuer,
    Canonical_Policy_Key,
    Canonical_Enrollee_Key
INTO #entity_2025
FROM #confirm_bridge
WHERE Inbound_Coverage_Year = 2025;

SELECT DISTINCT
    Year_Business_Key,
    Combined_Business_Key,
    Inbound_Issuer,
    Canonical_Policy_Key,
    Canonical_Enrollee_Key
INTO #entity_2026
FROM #confirm_bridge
WHERE Inbound_Coverage_Year = 2026;

CREATE UNIQUE CLUSTERED INDEX CX_e2025 ON #entity_2025 (Year_Business_Key);
CREATE NONCLUSTERED INDEX IX_e2025_comb ON #entity_2025 (Combined_Business_Key);
CREATE UNIQUE CLUSTERED INDEX CX_e2026 ON #entity_2026 (Year_Business_Key);
CREATE NONCLUSTERED INDEX IX_e2026_comb ON #entity_2026 (Combined_Business_Key);

DECLARE @entities_2025 BIGINT = (SELECT COUNT(*) FROM #entity_2025);
DECLARE @entities_2026 BIGINT = (SELECT COUNT(*) FROM #entity_2026);

SET @msg = CONCAT(
    'PHASE2 done in ', DATEDIFF(second, @t_phase, SYSDATETIME()),
    's; raw_2025=', @raw_2025, '; entities_2025=', @entities_2025,
    '; raw_2026=', @raw_2026, '; entities_2026=', @entities_2026
);
RAISERROR(@msg, 10, 1) WITH NOWAIT;

IF @enforce_expected = 1 AND (
       @raw_2026 <> @expected_2026_confirm_raw
    OR @entities_2026 <> @expected_2026_confirm_entities
)
BEGIN
    RAISERROR(
        '2026 INBOUND CONFIRM DRIFT: raw=%I64d (exp %I64d), entities=%I64d (exp %I64d). Continuing with FLAG.',
        10, 1,
        @raw_2026, @expected_2026_confirm_raw,
        @entities_2026, @expected_2026_confirm_entities
    );
END;


-- =============================================================================
-- Combined cross-year CONFIRM universe
-- =============================================================================
SET @t_phase = SYSDATETIME();
RAISERROR('PHASE3 start: combined universe + overlap', 10, 1) WITH NOWAIT;

IF OBJECT_ID('tempdb..#combined_entity') IS NOT NULL DROP TABLE #combined_entity;

SELECT
    b.Combined_Business_Key,
    MAX(b.Inbound_Issuer) AS Inbound_Issuer,
    MAX(b.Canonical_Policy_Key) AS Canonical_Policy_Key,
    MAX(b.Canonical_Enrollee_Key) AS Canonical_Enrollee_Key,
    MAX(CASE WHEN b.Inbound_Coverage_Year = 2025 THEN 1 ELSE 0 END) AS Has_2025_CONFIRM,
    MAX(CASE WHEN b.Inbound_Coverage_Year = 2026 THEN 1 ELSE 0 END) AS Has_2026_CONFIRM,
    CASE
        WHEN MAX(CASE WHEN b.Inbound_Coverage_Year = 2025 THEN 1 ELSE 0 END) = 1
         AND MAX(CASE WHEN b.Inbound_Coverage_Year = 2026 THEN 1 ELSE 0 END) = 1
            THEN 'BOTH_2025_AND_2026'
        WHEN MAX(CASE WHEN b.Inbound_Coverage_Year = 2025 THEN 1 ELSE 0 END) = 1
            THEN '2025_ONLY'
        WHEN MAX(CASE WHEN b.Inbound_Coverage_Year = 2026 THEN 1 ELSE 0 END) = 1
            THEN '2026_ONLY'
        ELSE 'UNEXPECTED'
    END AS Year_Pattern,
    COUNT(*) AS Physical_Confirm_Row_Count,
    MIN(b.benefit_effective_date) AS Earliest_Benefit_Effective_Date,
    MAX(b.benefit_effective_date) AS Latest_Benefit_Effective_Date,
    MIN(b.benefit_end_date) AS Earliest_Benefit_End_Date,
    MAX(b.benefit_end_date) AS Latest_Benefit_End_Date,
    MIN(b.member_maint_effective_date) AS Earliest_Member_Maint_Date,
    MAX(b.member_maint_effective_date) AS Latest_Member_Maint_Date
INTO #combined_entity
FROM #confirm_bridge AS b
GROUP BY b.Combined_Business_Key;

CREATE UNIQUE CLUSTERED INDEX CX_combined ON #combined_entity (Combined_Business_Key);
CREATE NONCLUSTERED INDEX IX_combined_pattern ON #combined_entity (Year_Pattern) INCLUDE (Inbound_Issuer);

DECLARE @combined_union BIGINT = (SELECT COUNT(*) FROM #combined_entity);
DECLARE @overlap_both BIGINT = (SELECT COUNT(*) FROM #combined_entity WHERE Year_Pattern = 'BOTH_2025_AND_2026');
DECLARE @only_2025 BIGINT = (SELECT COUNT(*) FROM #combined_entity WHERE Year_Pattern = '2025_ONLY');
DECLARE @only_2026 BIGINT = (SELECT COUNT(*) FROM #combined_entity WHERE Year_Pattern = '2026_ONLY');

-- Distinct ID lists + source files for master
IF OBJECT_ID('tempdb..#id_member') IS NOT NULL DROP TABLE #id_member;
IF OBJECT_ID('tempdb..#id_issuer_indiv') IS NOT NULL DROP TABLE #id_issuer_indiv;
IF OBJECT_ID('tempdb..#id_exchg') IS NOT NULL DROP TABLE #id_exchg;
IF OBJECT_ID('tempdb..#id_policy') IS NOT NULL DROP TABLE #id_policy;
IF OBJECT_ID('tempdb..#id_hc') IS NOT NULL DROP TABLE #id_hc;
IF OBJECT_ID('tempdb..#id_files') IS NOT NULL DROP TABLE #id_files;

SELECT Combined_Business_Key,
       STRING_AGG(CAST(v AS NVARCHAR(100)), N' | ') WITHIN GROUP (ORDER BY v) AS All_Member_IDs
INTO #id_member
FROM (SELECT DISTINCT Combined_Business_Key, Inbound_Member_ID AS v FROM #confirm_bridge WHERE Inbound_Member_ID IS NOT NULL) d
GROUP BY Combined_Business_Key;

SELECT Combined_Business_Key,
       STRING_AGG(CAST(v AS NVARCHAR(100)), N' | ') WITHIN GROUP (ORDER BY v) AS All_Issuer_Indiv_IDs
INTO #id_issuer_indiv
FROM (SELECT DISTINCT Combined_Business_Key, Inbound_Issuer_Indiv_Identifier AS v FROM #confirm_bridge WHERE Inbound_Issuer_Indiv_Identifier IS NOT NULL) d
GROUP BY Combined_Business_Key;

SELECT Combined_Business_Key,
       STRING_AGG(CAST(v AS NVARCHAR(100)), N' | ') WITHIN GROUP (ORDER BY v) AS All_Exchg_Enrollee_IDs
INTO #id_exchg
FROM (SELECT DISTINCT Combined_Business_Key, Inbound_Exchange_Assigned_Enrollee_ID AS v FROM #confirm_bridge WHERE Inbound_Exchange_Assigned_Enrollee_ID IS NOT NULL) d
GROUP BY Combined_Business_Key;

SELECT Combined_Business_Key,
       STRING_AGG(CAST(v AS NVARCHAR(100)), N' | ') WITHIN GROUP (ORDER BY v) AS All_Policy_IDs
INTO #id_policy
FROM (SELECT DISTINCT Combined_Business_Key, Inbound_Policy_ID AS v FROM #confirm_bridge WHERE Inbound_Policy_ID IS NOT NULL) d
GROUP BY Combined_Business_Key;

SELECT Combined_Business_Key,
       STRING_AGG(CAST(v AS NVARCHAR(100)), N' | ') WITHIN GROUP (ORDER BY v) AS All_Health_Coverage_Policy_Nos
INTO #id_hc
FROM (SELECT DISTINCT Combined_Business_Key, Inbound_Health_Coverage_Policy_No AS v FROM #confirm_bridge WHERE Inbound_Health_Coverage_Policy_No IS NOT NULL) d
GROUP BY Combined_Business_Key;

SELECT Combined_Business_Key,
       STRING_AGG(CAST(v AS NVARCHAR(400)), N' | ') WITHIN GROUP (ORDER BY v) AS All_Source_Files
INTO #id_files
FROM (
    SELECT DISTINCT Combined_Business_Key, Inbound_Source_File AS v
    FROM #confirm_bridge
    WHERE Inbound_Source_File IS NOT NULL
) d
GROUP BY Combined_Business_Key;

SET @msg = CONCAT(
    'PHASE3 done in ', DATEDIFF(second, @t_phase, SYSDATETIME()),
    's; combined_union=', @combined_union,
    '; both=', @overlap_both, '; only_2025=', @only_2025, '; only_2026=', @only_2026
);
RAISERROR(@msg, 10, 1) WITH NOWAIT;


-- =============================================================================
-- Match combined inbound universe -> 2026 FFM target (independent ID paths)
-- =============================================================================
SET @t_phase = SYSDATETIME();
RAISERROR('PHASE4 start: match combined CONFIRM -> FFM target', 10, 1) WITH NOWAIT;

IF OBJECT_ID('tempdb..#enrollee_hits') IS NOT NULL DROP TABLE #enrollee_hits;

;WITH e_raw AS (
    SELECT br.Combined_Business_Key, f.FFM_Coverage_Year, f.FFM_Policy_ID, f.FFM_Enrollee_ID, f.FFM_Issuer,
           f.FFM_Enrollment_Status, f.FFM_Enrollee_Status,
           CAST('MEMBER_ID' AS VARCHAR(40)) AS Enrollee_Hit_Type
    FROM #confirm_bridge AS br
    INNER JOIN #ffm_target AS f ON f.FFM_Enrollee_ID = br.Inbound_Member_ID
    WHERE br.Inbound_Member_ID IS NOT NULL

    UNION ALL

    SELECT br.Combined_Business_Key, f.FFM_Coverage_Year, f.FFM_Policy_ID, f.FFM_Enrollee_ID, f.FFM_Issuer,
           f.FFM_Enrollment_Status, f.FFM_Enrollee_Status,
           CAST('ISSUER_INDIV_IDENTIFIER' AS VARCHAR(40))
    FROM #confirm_bridge AS br
    INNER JOIN #ffm_target AS f ON f.FFM_Enrollee_ID = br.Inbound_Issuer_Indiv_Identifier
    WHERE br.Inbound_Issuer_Indiv_Identifier IS NOT NULL

    UNION ALL

    SELECT br.Combined_Business_Key, f.FFM_Coverage_Year, f.FFM_Policy_ID, f.FFM_Enrollee_ID, f.FFM_Issuer,
           f.FFM_Enrollment_Status, f.FFM_Enrollee_Status,
           CAST('EXCHG_ASSIGNED_ENROLLEE_ID' AS VARCHAR(40))
    FROM #confirm_bridge AS br
    INNER JOIN #ffm_target AS f ON f.FFM_Enrollee_ID = br.Inbound_Exchange_Assigned_Enrollee_ID
    WHERE br.Inbound_Exchange_Assigned_Enrollee_ID IS NOT NULL
)
SELECT
    Combined_Business_Key,
    FFM_Coverage_Year,
    FFM_Policy_ID,
    FFM_Enrollee_ID,
    FFM_Issuer,
    MAX(FFM_Enrollment_Status) AS FFM_Enrollment_Status,
    MAX(FFM_Enrollee_Status) AS FFM_Enrollee_Status,
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
INTO #enrollee_hits
FROM e_raw
GROUP BY Combined_Business_Key, FFM_Coverage_Year, FFM_Policy_ID, FFM_Enrollee_ID, FFM_Issuer;

CREATE CLUSTERED INDEX CX_eh ON #enrollee_hits (Combined_Business_Key, FFM_Policy_ID, FFM_Enrollee_ID);

IF OBJECT_ID('tempdb..#policy_hits') IS NOT NULL DROP TABLE #policy_hits;

;WITH p_raw AS (
    SELECT br.Combined_Business_Key, f.FFM_Coverage_Year, f.FFM_Policy_ID, f.FFM_Enrollee_ID, f.FFM_Issuer,
           CAST('POLICY_ID' AS VARCHAR(40)) AS Policy_Hit_Type
    FROM #confirm_bridge AS br
    INNER JOIN #ffm_target AS f ON f.FFM_Policy_ID = br.Inbound_Policy_ID
    WHERE br.Inbound_Policy_ID IS NOT NULL

    UNION ALL

    SELECT br.Combined_Business_Key, f.FFM_Coverage_Year, f.FFM_Policy_ID, f.FFM_Enrollee_ID, f.FFM_Issuer,
           CAST('HEALTH_COVERAGE_POLICY_NO' AS VARCHAR(40))
    FROM #confirm_bridge AS br
    INNER JOIN #ffm_target AS f ON f.FFM_Policy_ID = br.Inbound_Health_Coverage_Policy_No
    WHERE br.Inbound_Health_Coverage_Policy_No IS NOT NULL
)
SELECT
    Combined_Business_Key,
    FFM_Coverage_Year,
    FFM_Policy_ID,
    FFM_Enrollee_ID,
    FFM_Issuer,
    CASE
        WHEN MAX(CASE WHEN Policy_Hit_Type = 'POLICY_ID' THEN 1 ELSE 0 END) = 1
         AND MAX(CASE WHEN Policy_Hit_Type = 'HEALTH_COVERAGE_POLICY_NO' THEN 1 ELSE 0 END) = 1
            THEN 'BOTH'
        WHEN MAX(CASE WHEN Policy_Hit_Type = 'POLICY_ID' THEN 1 ELSE 0 END) = 1 THEN 'POLICY_ID'
        ELSE 'HEALTH_COVERAGE_POLICY_NO'
    END AS Matched_Policy_ID_Type
INTO #policy_hits
FROM p_raw
GROUP BY Combined_Business_Key, FFM_Coverage_Year, FFM_Policy_ID, FFM_Enrollee_ID, FFM_Issuer;

CREATE CLUSTERED INDEX CX_ph ON #policy_hits (Combined_Business_Key, FFM_Policy_ID, FFM_Enrollee_ID);

IF OBJECT_ID('tempdb..#exact_hits') IS NOT NULL DROP TABLE #exact_hits;

SELECT
    e.Combined_Business_Key,
    e.FFM_Coverage_Year,
    e.FFM_Policy_ID AS Matched_FFM_Policy_ID,
    e.FFM_Enrollee_ID AS Matched_FFM_Enrollee_ID,
    e.FFM_Issuer AS Matched_FFM_Issuer,
    e.FFM_Enrollment_Status AS Matched_FFM_Enrollment_Status,
    e.FFM_Enrollee_Status AS Matched_FFM_Enrollee_Status,
    e.Matched_Enrollee_ID_Type,
    p.Matched_Policy_ID_Type
INTO #exact_hits
FROM #enrollee_hits AS e
INNER JOIN #policy_hits AS p
    ON p.Combined_Business_Key = e.Combined_Business_Key
   AND p.FFM_Coverage_Year = e.FFM_Coverage_Year
   AND p.FFM_Policy_ID = e.FFM_Policy_ID
   AND p.FFM_Enrollee_ID = e.FFM_Enrollee_ID;

CREATE CLUSTERED INDEX CX_exact ON #exact_hits (Combined_Business_Key);
CREATE NONCLUSTERED INDEX IX_exact_ffm
    ON #exact_hits (Matched_FFM_Policy_ID, Matched_FFM_Enrollee_ID);

IF OBJECT_ID('tempdb..#exact_best') IS NOT NULL DROP TABLE #exact_best;
SELECT * INTO #exact_best FROM (
    SELECT *, ROW_NUMBER() OVER (
        PARTITION BY Combined_Business_Key
        ORDER BY Matched_FFM_Policy_ID, Matched_FFM_Enrollee_ID
    ) AS rn FROM #exact_hits
) x WHERE rn = 1;

IF OBJECT_ID('tempdb..#enrollee_only_best') IS NOT NULL DROP TABLE #enrollee_only_best;
SELECT * INTO #enrollee_only_best FROM (
    SELECT e.*, ROW_NUMBER() OVER (
        PARTITION BY e.Combined_Business_Key ORDER BY e.FFM_Policy_ID, e.FFM_Enrollee_ID
    ) AS rn
    FROM #enrollee_hits e
    WHERE NOT EXISTS (SELECT 1 FROM #exact_hits x WHERE x.Combined_Business_Key = e.Combined_Business_Key)
) x WHERE rn = 1;

IF OBJECT_ID('tempdb..#policy_only_best') IS NOT NULL DROP TABLE #policy_only_best;
SELECT * INTO #policy_only_best FROM (
    SELECT p.*, ROW_NUMBER() OVER (
        PARTITION BY p.Combined_Business_Key ORDER BY p.FFM_Policy_ID, p.FFM_Enrollee_ID
    ) AS rn
    FROM #policy_hits p
    WHERE NOT EXISTS (SELECT 1 FROM #exact_hits x WHERE x.Combined_Business_Key = p.Combined_Business_Key)
      AND NOT EXISTS (SELECT 1 FROM #enrollee_hits e WHERE e.Combined_Business_Key = p.Combined_Business_Key)
) x WHERE rn = 1;

CREATE UNIQUE CLUSTERED INDEX CX_exact_best ON #exact_best (Combined_Business_Key);
CREATE UNIQUE CLUSTERED INDEX CX_eel_only ON #enrollee_only_best (Combined_Business_Key);
CREATE UNIQUE CLUSTERED INDEX CX_pol_only ON #policy_only_best (Combined_Business_Key);

DECLARE @ffm_exact_in_inbound BIGINT = (
    SELECT COUNT(DISTINCT CAST(Matched_FFM_Policy_ID AS VARCHAR(100)) + N'|' + CAST(Matched_FFM_Enrollee_ID AS VARCHAR(100)))
    FROM #exact_hits
);

SET @msg = CONCAT(
    'PHASE4 matching done in ', DATEDIFF(second, @t_phase, SYSDATETIME()),
    's; ffm_pairs_exact_in_inbound=', @ffm_exact_in_inbound
);
RAISERROR(@msg, 10, 1) WITH NOWAIT;


-- =============================================================================
-- Master: one row per combined inbound entity
-- =============================================================================
SET @t_phase = SYSDATETIME();
RAISERROR('PHASE5 start: assemble master', 10, 1) WITH NOWAIT;

IF OBJECT_ID('tempdb..#master') IS NOT NULL DROP TABLE #master;

SELECT
    c.Combined_Business_Key,
    c.Inbound_Issuer,
    c.Canonical_Policy_Key,
    c.Canonical_Enrollee_Key,
    c.Has_2025_CONFIRM,
    c.Has_2026_CONFIRM,
    c.Year_Pattern,
    c.Physical_Confirm_Row_Count,
    c.Earliest_Benefit_Effective_Date,
    c.Latest_Benefit_Effective_Date,
    c.Earliest_Benefit_End_Date,
    c.Latest_Benefit_End_Date,
    c.Earliest_Member_Maint_Date,
    c.Latest_Member_Maint_Date,
    mid.All_Member_IDs,
    iid.All_Issuer_Indiv_IDs,
    xid.All_Exchg_Enrollee_IDs,
    pid.All_Policy_IDs,
    hid.All_Health_Coverage_Policy_Nos,
    fl.All_Source_Files,
    CASE
        WHEN ex.Combined_Business_Key IS NOT NULL THEN 'EXACT_POLICY_ENROLLEE_IN_2026_FFM_TARGET'
        WHEN eo.Combined_Business_Key IS NOT NULL THEN 'ENROLLEE_IN_2026_TARGET_DIFFERENT_POLICY'
        WHEN po.Combined_Business_Key IS NOT NULL THEN 'POLICY_IN_2026_TARGET_DIFFERENT_ENROLLEE'
        ELSE 'INBOUND_CONFIRM_NOT_IN_2026_FFM_TARGET'
    END AS Reconciliation_Category,
    COALESCE(ex.Matched_FFM_Issuer, eo.FFM_Issuer, po.FFM_Issuer) AS Matched_FFM_Issuer,
    COALESCE(ex.Matched_FFM_Policy_ID, eo.FFM_Policy_ID, po.FFM_Policy_ID) AS Matched_FFM_Policy_ID,
    COALESCE(ex.Matched_FFM_Enrollee_ID, eo.FFM_Enrollee_ID, po.FFM_Enrollee_ID) AS Matched_FFM_Enrollee_ID,
    COALESCE(ex.Matched_FFM_Enrollment_Status, eo.FFM_Enrollment_Status) AS Matched_FFM_Enrollment_Status,
    COALESCE(ex.Matched_FFM_Enrollee_Status, eo.FFM_Enrollee_Status) AS Matched_FFM_Enrollee_Status,
    ex.Matched_Enrollee_ID_Type,
    ex.Matched_Policy_ID_Type
INTO #master
FROM #combined_entity AS c
LEFT JOIN #exact_best AS ex ON ex.Combined_Business_Key = c.Combined_Business_Key
LEFT JOIN #enrollee_only_best AS eo ON eo.Combined_Business_Key = c.Combined_Business_Key
LEFT JOIN #policy_only_best AS po ON po.Combined_Business_Key = c.Combined_Business_Key
LEFT JOIN #id_member AS mid ON mid.Combined_Business_Key = c.Combined_Business_Key
LEFT JOIN #id_issuer_indiv AS iid ON iid.Combined_Business_Key = c.Combined_Business_Key
LEFT JOIN #id_exchg AS xid ON xid.Combined_Business_Key = c.Combined_Business_Key
LEFT JOIN #id_policy AS pid ON pid.Combined_Business_Key = c.Combined_Business_Key
LEFT JOIN #id_hc AS hid ON hid.Combined_Business_Key = c.Combined_Business_Key
LEFT JOIN #id_files AS fl ON fl.Combined_Business_Key = c.Combined_Business_Key;

CREATE UNIQUE CLUSTERED INDEX CX_master ON #master (Combined_Business_Key);
CREATE NONCLUSTERED INDEX IX_master_cat ON #master (Reconciliation_Category, Year_Pattern, Inbound_Issuer);

DECLARE @inbound_exact BIGINT = (
    SELECT COUNT(*) FROM #master WHERE Reconciliation_Category = 'EXACT_POLICY_ENROLLEE_IN_2026_FFM_TARGET'
);
DECLARE @inbound_not_exact BIGINT = @combined_union - @inbound_exact;
DECLARE @ffm_not_exact BIGINT = @ffm_total - @ffm_exact_in_inbound;

SET @msg = CONCAT(
    'PHASE5 master done in ', DATEDIFF(second, @t_phase, SYSDATETIME()),
    's; inbound_exact=', @inbound_exact, '; inbound_not_exact=', @inbound_not_exact
);
RAISERROR(@msg, 10, 1) WITH NOWAIT;


-- =============================================================================
-- Result 4 diagnostic — not-in-target entities vs ALL Enrollments_TEST
-- =============================================================================
SET @t_phase = SYSDATETIME();
RAISERROR('PHASE6 start: ours-but-not-theirs Enrollments_TEST diagnostic', 10, 1) WITH NOWAIT;

IF OBJECT_ID('tempdb..#not_in_target') IS NOT NULL DROP TABLE #not_in_target;

SELECT *
INTO #not_in_target
FROM #master
WHERE Reconciliation_Category <> 'EXACT_POLICY_ENROLLEE_IN_2026_FFM_TARGET';

CREATE UNIQUE CLUSTERED INDEX CX_nit ON #not_in_target (Combined_Business_Key);

-- Bridge of not-in-target physical IDs; search Enrollments_TEST by ID (all years/statuses)
IF OBJECT_ID('tempdb..#nit_bridge') IS NOT NULL DROP TABLE #nit_bridge;

SELECT b.*
INTO #nit_bridge
FROM #confirm_bridge AS b
INNER JOIN #not_in_target AS n ON n.Combined_Business_Key = b.Combined_Business_Key;

CREATE CLUSTERED INDEX CX_nit_br ON #nit_bridge (Combined_Business_Key, inbound_row_id);
CREATE NONCLUSTERED INDEX IX_nit_member ON #nit_bridge (Inbound_Member_ID) INCLUDE (Combined_Business_Key);
CREATE NONCLUSTERED INDEX IX_nit_ii ON #nit_bridge (Inbound_Issuer_Indiv_Identifier) INCLUDE (Combined_Business_Key);
CREATE NONCLUSTERED INDEX IX_nit_ex ON #nit_bridge (Inbound_Exchange_Assigned_Enrollee_ID) INCLUDE (Combined_Business_Key);
CREATE NONCLUSTERED INDEX IX_nit_pol ON #nit_bridge (Inbound_Policy_ID) INCLUDE (Combined_Business_Key);
CREATE NONCLUSTERED INDEX IX_nit_hc ON #nit_bridge (Inbound_Health_Coverage_Policy_No) INCLUDE (Combined_Business_Key);

IF OBJECT_ID('tempdb..#nit_eel_hits') IS NOT NULL DROP TABLE #nit_eel_hits;

;WITH e_raw AS (
    SELECT br.Combined_Business_Key,
           CAST(e.coverage_year AS INT) AS Enr_Coverage_Year,
           CAST(e.enrollment_id AS VARCHAR(100)) AS Enr_Policy_ID,
           CAST(e.enrollee_id AS VARCHAR(100)) AS Enr_Enrollee_ID,
           CAST(e.hios_issuer_id AS VARCHAR(20)) AS Enr_Issuer,
           e.enrollment_status_description AS Enr_Enrollment_Status
    FROM #nit_bridge AS br
    INNER JOIN dbo.Enrollments_TEST AS e
        ON CAST(e.enrollee_id AS VARCHAR(100)) = br.Inbound_Member_ID
    WHERE br.Inbound_Member_ID IS NOT NULL

    UNION

    SELECT br.Combined_Business_Key,
           CAST(e.coverage_year AS INT),
           CAST(e.enrollment_id AS VARCHAR(100)),
           CAST(e.enrollee_id AS VARCHAR(100)),
           CAST(e.hios_issuer_id AS VARCHAR(20)),
           e.enrollment_status_description
    FROM #nit_bridge AS br
    INNER JOIN dbo.Enrollments_TEST AS e
        ON CAST(e.enrollee_id AS VARCHAR(100)) = br.Inbound_Issuer_Indiv_Identifier
    WHERE br.Inbound_Issuer_Indiv_Identifier IS NOT NULL

    UNION

    SELECT br.Combined_Business_Key,
           CAST(e.coverage_year AS INT),
           CAST(e.enrollment_id AS VARCHAR(100)),
           CAST(e.enrollee_id AS VARCHAR(100)),
           CAST(e.hios_issuer_id AS VARCHAR(20)),
           e.enrollment_status_description
    FROM #nit_bridge AS br
    INNER JOIN dbo.Enrollments_TEST AS e
        ON CAST(e.enrollee_id AS VARCHAR(100)) = br.Inbound_Exchange_Assigned_Enrollee_ID
    WHERE br.Inbound_Exchange_Assigned_Enrollee_ID IS NOT NULL
)
SELECT DISTINCT * INTO #nit_eel_hits FROM e_raw;

CREATE CLUSTERED INDEX CX_nit_eel ON #nit_eel_hits (Combined_Business_Key, Enr_Policy_ID, Enr_Enrollee_ID);

IF OBJECT_ID('tempdb..#nit_pol_hits') IS NOT NULL DROP TABLE #nit_pol_hits;

;WITH p_raw AS (
    SELECT br.Combined_Business_Key,
           CAST(e.coverage_year AS INT) AS Enr_Coverage_Year,
           CAST(e.enrollment_id AS VARCHAR(100)) AS Enr_Policy_ID,
           CAST(e.enrollee_id AS VARCHAR(100)) AS Enr_Enrollee_ID,
           CAST(e.hios_issuer_id AS VARCHAR(20)) AS Enr_Issuer,
           e.enrollment_status_description AS Enr_Enrollment_Status
    FROM #nit_bridge AS br
    INNER JOIN dbo.Enrollments_TEST AS e
        ON CAST(e.enrollment_id AS VARCHAR(100)) = br.Inbound_Policy_ID
    WHERE br.Inbound_Policy_ID IS NOT NULL

    UNION

    SELECT br.Combined_Business_Key,
           CAST(e.coverage_year AS INT),
           CAST(e.enrollment_id AS VARCHAR(100)),
           CAST(e.enrollee_id AS VARCHAR(100)),
           CAST(e.hios_issuer_id AS VARCHAR(20)),
           e.enrollment_status_description
    FROM #nit_bridge AS br
    INNER JOIN dbo.Enrollments_TEST AS e
        ON CAST(e.enrollment_id AS VARCHAR(100)) = br.Inbound_Health_Coverage_Policy_No
    WHERE br.Inbound_Health_Coverage_Policy_No IS NOT NULL
)
SELECT DISTINCT * INTO #nit_pol_hits FROM p_raw;

CREATE CLUSTERED INDEX CX_nit_pol ON #nit_pol_hits (Combined_Business_Key, Enr_Policy_ID, Enr_Enrollee_ID);

IF OBJECT_ID('tempdb..#nit_diag') IS NOT NULL DROP TABLE #nit_diag;

SELECT
    n.Combined_Business_Key,
    n.Inbound_Issuer,
    n.Year_Pattern,
    n.Reconciliation_Category,
    CASE WHEN eel.Combined_Business_Key IS NOT NULL THEN 1 ELSE 0 END AS Has_Enrollee_Anywhere_In_Enrollments,
    CASE WHEN pol.Combined_Business_Key IS NOT NULL THEN 1 ELSE 0 END AS Has_Policy_Anywhere_In_Enrollments,
    CASE
        WHEN EXISTS (
            SELECT 1 FROM #nit_eel_hits e
            INNER JOIN #nit_pol_hits p
                ON p.Combined_Business_Key = e.Combined_Business_Key
               AND p.Enr_Coverage_Year = e.Enr_Coverage_Year
               AND p.Enr_Policy_ID = e.Enr_Policy_ID
               AND p.Enr_Enrollee_ID = e.Enr_Enrollee_ID
            WHERE e.Combined_Business_Key = n.Combined_Business_Key
              AND e.Enr_Coverage_Year = 2026
              AND UPPER(LTRIM(RTRIM(e.Enr_Enrollment_Status))) NOT IN ('ENROLLED', 'PENDING')
        ) THEN 'EXISTS_IN_2026_OUTSIDE_ENROLLED_PENDING'
        WHEN EXISTS (
            SELECT 1 FROM #nit_eel_hits e
            INNER JOIN #nit_pol_hits p
                ON p.Combined_Business_Key = e.Combined_Business_Key
               AND p.Enr_Coverage_Year = e.Enr_Coverage_Year
               AND p.Enr_Policy_ID = e.Enr_Policy_ID
               AND p.Enr_Enrollee_ID = e.Enr_Enrollee_ID
            WHERE e.Combined_Business_Key = n.Combined_Business_Key
              AND e.Enr_Coverage_Year <> 2026
        ) THEN 'EXISTS_IN_ANOTHER_COVERAGE_YEAR'
        WHEN EXISTS (
            SELECT 1 FROM #nit_eel_hits e
            WHERE e.Combined_Business_Key = n.Combined_Business_Key
              AND e.Enr_Issuer = n.Inbound_Issuer
              AND NOT EXISTS (
                    SELECT 1 FROM #nit_pol_hits p
                    WHERE p.Combined_Business_Key = e.Combined_Business_Key
                      AND p.Enr_Coverage_Year = e.Enr_Coverage_Year
                      AND p.Enr_Policy_ID = e.Enr_Policy_ID
                      AND p.Enr_Enrollee_ID = e.Enr_Enrollee_ID
              )
        ) THEN 'ENROLLEE_EXISTS_UNDER_DIFFERENT_POLICY'
        WHEN EXISTS (
            SELECT 1 FROM #nit_eel_hits e
            WHERE e.Combined_Business_Key = n.Combined_Business_Key
              AND e.Enr_Issuer <> n.Inbound_Issuer
        ) THEN 'ENROLLEE_EXISTS_UNDER_DIFFERENT_ISSUER'
        WHEN EXISTS (
            SELECT 1 FROM #nit_pol_hits p
            WHERE p.Combined_Business_Key = n.Combined_Business_Key
              AND NOT EXISTS (
                    SELECT 1 FROM #nit_eel_hits e
                    WHERE e.Combined_Business_Key = p.Combined_Business_Key
                      AND e.Enr_Coverage_Year = p.Enr_Coverage_Year
                      AND e.Enr_Policy_ID = p.Enr_Policy_ID
                      AND e.Enr_Enrollee_ID = p.Enr_Enrollee_ID
              )
        ) THEN 'POLICY_EXISTS_WITH_DIFFERENT_ENROLLEE'
        WHEN eel.Combined_Business_Key IS NULL AND pol.Combined_Business_Key IS NULL
            THEN 'NOWHERE_IN_ENROLLMENTS_TEST'
        ELSE 'OTHER_ENROLLMENTS_TEST_EVIDENCE'
    END AS Diagnostic_Category
INTO #nit_diag
FROM #not_in_target AS n
LEFT JOIN (SELECT DISTINCT Combined_Business_Key FROM #nit_eel_hits) AS eel
    ON eel.Combined_Business_Key = n.Combined_Business_Key
LEFT JOIN (SELECT DISTINCT Combined_Business_Key FROM #nit_pol_hits) AS pol
    ON pol.Combined_Business_Key = n.Combined_Business_Key;

CREATE UNIQUE CLUSTERED INDEX CX_nit_diag ON #nit_diag (Combined_Business_Key);

-- Attach diagnostic onto master for Result 6
IF OBJECT_ID('tempdb..#master_final') IS NOT NULL DROP TABLE #master_final;

SELECT
    m.*,
    d.Diagnostic_Category
INTO #master_final
FROM #master AS m
LEFT JOIN #nit_diag AS d ON d.Combined_Business_Key = m.Combined_Business_Key;

CREATE UNIQUE CLUSTERED INDEX CX_master_final ON #master_final (Combined_Business_Key);

SET @msg = CONCAT(
    'PHASE6 diagnostic done in ', DATEDIFF(second, @t_phase, SYSDATETIME()),
    's; not_in_target=', (SELECT COUNT(*) FROM #not_in_target)
);
RAISERROR(@msg, 10, 1) WITH NOWAIT;
RAISERROR('RESULT SETS start', 10, 1) WITH NOWAIT;


-- =============================================================================
-- RESULT 1 — Independent inbound population controls
-- =============================================================================
SELECT
    @raw_2025 AS confirm_2025_physical_rows,
    @complete_2025 AS confirm_2025_complete_key_physical_rows,
    @entities_2025 AS confirm_2025_distinct_business_entities,
    @raw_2026 AS confirm_2026_physical_rows,
    @complete_2026 AS confirm_2026_complete_key_physical_rows,
    @entities_2026 AS confirm_2026_distinct_business_entities,
    @expected_2026_confirm_raw AS expected_2026_confirm_raw,
    @expected_2026_confirm_entities AS expected_2026_confirm_entities,
    CASE
        WHEN @raw_2026 = @expected_2026_confirm_raw
         AND @entities_2026 = @expected_2026_confirm_entities
            THEN 'PASS'
        ELSE 'FLAG_2026_INBOUND_DRIFT'
    END AS inbound_2026_control_status;


-- =============================================================================
-- RESULT 2 — 2025/2026 inbound overlap (cross-year Combined_Business_Key)
-- =============================================================================
SELECT
    metric,
    entity_count,
    CAST(100.0 * entity_count / NULLIF(@combined_union, 0) AS DECIMAL(10, 4)) AS pct_of_combined_union,
    CAST(100.0 * entity_count / NULLIF(@entities_2025, 0) AS DECIMAL(10, 4)) AS pct_of_2025_entities,
    CAST(100.0 * entity_count / NULLIF(@entities_2026, 0) AS DECIMAL(10, 4)) AS pct_of_2026_entities
FROM (VALUES
    ('2025_CONFIRM_ONLY', @only_2025),
    ('2026_CONFIRM_ONLY', @only_2026),
    ('PRESENT_IN_BOTH_2025_AND_2026', @overlap_both),
    ('UNION_DISTINCT_2025_PLUS_2026', @combined_union)
) AS v(metric, entity_count);


-- =============================================================================
-- RESULT 3 — Combined inbound vs 2026 FFM target (with year-pattern split)
-- =============================================================================
SELECT
    Reconciliation_Category,
    Year_Pattern,
    COUNT(*) AS entity_count,
    CAST(100.0 * COUNT(*) / NULLIF(@combined_union, 0) AS DECIMAL(10, 4)) AS pct_of_combined_union
FROM #master_final
GROUP BY Reconciliation_Category, Year_Pattern
ORDER BY Reconciliation_Category, Year_Pattern;

SELECT
    Reconciliation_Category,
    COUNT(*) AS entity_count,
    CAST(100.0 * COUNT(*) / NULLIF(@combined_union, 0) AS DECIMAL(10, 4)) AS pct_of_combined_union
FROM #master_final
GROUP BY Reconciliation_Category
ORDER BY entity_count DESC;


-- =============================================================================
-- RESULT 4 — Ours but not theirs (not exact in 960,531) + Enrollments_TEST diag
-- =============================================================================
SELECT
    Year_Pattern,
    Inbound_Issuer,
    Reconciliation_Category,
    COUNT(*) AS entity_count
FROM #not_in_target
GROUP BY Year_Pattern, Inbound_Issuer, Reconciliation_Category
ORDER BY entity_count DESC, Year_Pattern, Inbound_Issuer, Reconciliation_Category;

SELECT
    Diagnostic_Category,
    Year_Pattern,
    COUNT(*) AS entity_count,
    CAST(100.0 * COUNT(*) / NULLIF((SELECT COUNT(*) FROM #not_in_target), 0) AS DECIMAL(10, 4))
        AS pct_of_not_exact_inbound
FROM #nit_diag
GROUP BY Diagnostic_Category, Year_Pattern
ORDER BY entity_count DESC;


-- =============================================================================
-- RESULT 5 — Two-way population comparison control table
-- =============================================================================
SELECT
    section,
    metric,
    value_count,
    denominator_label,
    denominator_count,
    CAST(100.0 * value_count / NULLIF(denominator_count, 0) AS DECIMAL(10, 4)) AS pct,
    control_note
FROM (VALUES
    ('FFM', '2026_Enrolled', @ffm_enrolled, 'expected', @expected_ffm_enrolled,
        CASE WHEN @ffm_enrolled = @expected_ffm_enrolled THEN 'PASS' ELSE 'FAIL' END),
    ('FFM', '2026_Pending', @ffm_pending, 'expected', @expected_ffm_pending,
        CASE WHEN @ffm_pending = @expected_ffm_pending THEN 'PASS' ELSE 'FAIL' END),
    ('FFM', '2026_Enrolled_plus_Pending', @ffm_total, 'expected', @expected_ffm_total,
        CASE WHEN @ffm_total = @expected_ffm_total THEN 'PASS' ELSE 'FAIL' END),

    ('INBOUND', '2025_distinct_CONFIRM_entities', @entities_2025, 'n/a', CAST(NULL AS BIGINT), 'observed'),
    ('INBOUND', '2026_distinct_CONFIRM_entities', @entities_2026, 'expected_if_unchanged', @expected_2026_confirm_entities,
        CASE WHEN @entities_2026 = @expected_2026_confirm_entities THEN 'PASS' ELSE 'FLAG' END),
    ('INBOUND', '2025_2026_overlap_both', @overlap_both, 'combined_union', @combined_union, 'observed'),
    ('INBOUND', 'combined_2025_plus_2026_UNION_DISTINCT', @combined_union, 'hypothesis_band_~900K', CAST(900000 AS BIGINT), 'TEST_DO_NOT_FORCE'),

    ('RECON', 'combined_inbound_exact_in_FFM_target', @inbound_exact, 'combined_union', @combined_union, 'inbound_denominator'),
    ('RECON', 'combined_inbound_not_exact_in_FFM_target', @inbound_not_exact, 'combined_union', @combined_union, 'inbound_denominator'),
    ('RECON', 'FFM_target_pairs_exact_in_combined_inbound', @ffm_exact_in_inbound, 'ffm_target', @ffm_total, 'ffm_denominator'),
    ('RECON', 'FFM_target_pairs_not_exact_in_combined_inbound', @ffm_not_exact, 'ffm_target', @ffm_total, 'ffm_denominator')
) AS v(section, metric, value_count, denominator_label, denominator_count, control_note);


-- =============================================================================
-- RESULT 6 — Record-level master (one row per combined inbound entity)
-- =============================================================================
SELECT
    Inbound_Issuer,
    Canonical_Policy_Key AS Canonical_Policy,
    Canonical_Enrollee_Key AS Canonical_Enrollee,
    Has_2025_CONFIRM,
    Has_2026_CONFIRM,
    Year_Pattern,
    All_Policy_IDs,
    All_Health_Coverage_Policy_Nos,
    All_Member_IDs,
    All_Issuer_Indiv_IDs,
    All_Exchg_Enrollee_IDs,
    Earliest_Benefit_Effective_Date,
    Latest_Benefit_Effective_Date,
    Earliest_Benefit_End_Date,
    Latest_Benefit_End_Date,
    Earliest_Member_Maint_Date,
    Latest_Member_Maint_Date,
    All_Source_Files,
    Matched_FFM_Issuer,
    Matched_FFM_Policy_ID,
    Matched_FFM_Enrollee_ID,
    Matched_FFM_Enrollment_Status,
    Matched_FFM_Enrollee_Status,
    Reconciliation_Category,
    Diagnostic_Category,
    Physical_Confirm_Row_Count,
    Combined_Business_Key
FROM #master_final
ORDER BY
    Year_Pattern,
    Reconciliation_Category,
    Inbound_Issuer,
    Canonical_Policy_Key,
    Canonical_Enrollee_Key;


-- =============================================================================
-- RESULT 7 — Focused mutually exclusive population summary
-- =============================================================================
-- EXCLUDES: 2025_ONLY entities that do NOT exact-match the 2026 FFM target.
-- BOTH_2025_AND_2026 kept as separate buckets (no double-count with 2025/2026).
-- Matching logic unchanged — classification only.
-- =============================================================================
IF OBJECT_ID('tempdb..#focused_pop') IS NOT NULL DROP TABLE #focused_pop;

SELECT
    Combined_Business_Key,
    Year_Pattern,
    Reconciliation_Category,
    CASE
        /* 2025-only carry-forward that hits 2026 FFM target */
        WHEN Year_Pattern = '2025_ONLY'
         AND Reconciliation_Category = 'EXACT_POLICY_ENROLLEE_IN_2026_FFM_TARGET'
            THEN '2025_CARRY_FORWARD_MATCHED'

        /* BOTH: separate so not double-counted into 2025 + 2026 */
        WHEN Year_Pattern = 'BOTH_2025_AND_2026'
         AND Reconciliation_Category = 'EXACT_POLICY_ENROLLEE_IN_2026_FFM_TARGET'
            THEN 'BOTH_2025_AND_2026_EXACT_POLICY_ENROLLEE'
        WHEN Year_Pattern = 'BOTH_2025_AND_2026'
         AND Reconciliation_Category = 'ENROLLEE_IN_2026_TARGET_DIFFERENT_POLICY'
            THEN 'BOTH_2025_AND_2026_ENROLLEE_DIFFERENT_POLICY'
        WHEN Year_Pattern = 'BOTH_2025_AND_2026'
         AND Reconciliation_Category = 'POLICY_IN_2026_TARGET_DIFFERENT_ENROLLEE'
            THEN 'BOTH_2025_AND_2026_POLICY_DIFFERENT_ENROLLEE'
        WHEN Year_Pattern = 'BOTH_2025_AND_2026'
         AND Reconciliation_Category = 'INBOUND_CONFIRM_NOT_IN_2026_FFM_TARGET'
            THEN 'BOTH_2025_AND_2026_NOT_IN_FFM_TARGET'

        /* 2026-only CONFIRM classifications */
        WHEN Year_Pattern = '2026_ONLY'
         AND Reconciliation_Category = 'EXACT_POLICY_ENROLLEE_IN_2026_FFM_TARGET'
            THEN '2026_ONLY_EXACT_POLICY_ENROLLEE'
        WHEN Year_Pattern = '2026_ONLY'
         AND Reconciliation_Category = 'ENROLLEE_IN_2026_TARGET_DIFFERENT_POLICY'
            THEN '2026_ONLY_ENROLLEE_DIFFERENT_POLICY'
        WHEN Year_Pattern = '2026_ONLY'
         AND Reconciliation_Category = 'POLICY_IN_2026_TARGET_DIFFERENT_ENROLLEE'
            THEN '2026_ONLY_POLICY_DIFFERENT_ENROLLEE'
        WHEN Year_Pattern = '2026_ONLY'
         AND Reconciliation_Category = 'INBOUND_CONFIRM_NOT_IN_2026_FFM_TARGET'
            THEN '2026_ONLY_NOT_IN_FFM_TARGET'

        ELSE NULL  /* 2025_ONLY non-exact → excluded */
    END AS Population_Category
INTO #focused_pop
FROM #master_final
WHERE NOT (
        Year_Pattern = '2025_ONLY'
    AND Reconciliation_Category <> 'EXACT_POLICY_ENROLLEE_IN_2026_FFM_TARGET'
);

DELETE FROM #focused_pop WHERE Population_Category IS NULL;

DECLARE @focused_total BIGINT = (SELECT COUNT(*) FROM #focused_pop);

DECLARE @cf_2025 BIGINT = (
    SELECT COUNT(*) FROM #focused_pop WHERE Population_Category = '2025_CARRY_FORWARD_MATCHED'
);
DECLARE @pop_2026_included BIGINT = (
    SELECT COUNT(*) FROM #focused_pop
    WHERE Population_Category LIKE '2026_ONLY_%'
       OR Population_Category LIKE 'BOTH_2025_AND_2026_%'
);
DECLARE @both_adj BIGINT = (
    SELECT COUNT(*) FROM #focused_pop WHERE Population_Category LIKE 'BOTH_2025_AND_2026_%'
);
DECLARE @final_relevant BIGINT = @focused_total; /* = @cf_2025 + @pop_2026_included */

SELECT
    Population_Category,
    COUNT(*) AS Entity_Count,
    CAST(100.0 * COUNT(*) / NULLIF(@focused_total, 0) AS DECIMAL(10, 4)) AS Percentage_of_Total
FROM #focused_pop
GROUP BY Population_Category
ORDER BY
    CASE Population_Category
        WHEN '2025_CARRY_FORWARD_MATCHED' THEN 1
        WHEN 'BOTH_2025_AND_2026_EXACT_POLICY_ENROLLEE' THEN 2
        WHEN 'BOTH_2025_AND_2026_ENROLLEE_DIFFERENT_POLICY' THEN 3
        WHEN 'BOTH_2025_AND_2026_POLICY_DIFFERENT_ENROLLEE' THEN 4
        WHEN 'BOTH_2025_AND_2026_NOT_IN_FFM_TARGET' THEN 5
        WHEN '2026_ONLY_EXACT_POLICY_ENROLLEE' THEN 6
        WHEN '2026_ONLY_ENROLLEE_DIFFERENT_POLICY' THEN 7
        WHEN '2026_ONLY_POLICY_DIFFERENT_ENROLLEE' THEN 8
        WHEN '2026_ONLY_NOT_IN_FFM_TARGET' THEN 9
        ELSE 99
    END;


-- =============================================================================
-- RESULT 8 — Focused population vs FFM 960,531 (no "missing" label)
-- =============================================================================
SELECT
    metric,
    value_count,
    note
FROM (VALUES
    ('total_2025_carry_forward_matched', @cf_2025,
        '2025_ONLY inbound CONFIRM exact in 2026 FFM target'),
    ('total_2026_CONFIRM_population_included', @pop_2026_included,
        '2026_ONLY + BOTH_2025_AND_2026 (all reconciliation classes)'),
    ('overlap_BOTH_adjustment', @both_adj,
        'BOTH_2025_AND_2026 count held separate; already inside 2026 included'),
    ('final_distinct_relevant_inbound_population', @final_relevant,
        '2025_CARRY_FORWARD_MATCHED + 2026 included (mutually exclusive; no double-count)'),
    ('FFM_2026_Enrolled_Pending', @ffm_total,
        'expected 960,531'),
    ('numeric_difference_relevant_inbound_minus_FFM', (@final_relevant - @ffm_total),
        'Signed difference only — not labeled missing/error'),
    ('numeric_difference_FFM_minus_relevant_inbound', (@ffm_total - @final_relevant),
        'Signed difference only — not labeled missing/error'),
    ('excluded_2025_ONLY_not_in_FFM_target', (
        SELECT COUNT(*) FROM #master_final
        WHERE Year_Pattern = '2025_ONLY'
          AND Reconciliation_Category <> 'EXACT_POLICY_ENROLLEE_IN_2026_FFM_TARGET'
     ),
        'Excluded from this focused summary by design')
) AS v(metric, value_count, note);

SET @msg = CONCAT('ALL DONE; total_elapsed_s=', DATEDIFF(second, @t0, SYSDATETIME()));
RAISERROR(@msg, 10, 1) WITH NOWAIT;
