-- =============================================================================
-- REVERSE RECONCILIATION — 2026 inbound CONFIRM vs FFM Scenario B target
-- =============================================================================
-- Business question:
--   Which 2026 inbound CONFIRM records exist in our 834 data but do NOT exist
--   in the approved 2026 FFM Enrolled/Pending population (960,531 pairs)?
--
-- Does NOT modify:
--   sql/scenario_b_2026_834_row_level_reconciliation.sql
--
-- Safety: READ ONLY on permanent tables. Temp tables/indexes only. No RCNI.
-- =============================================================================

SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @coverage_year INT = 2026;
DECLARE @expected_ffm_pairs BIGINT = 960531;
DECLARE @enforce_expected_count BIT = 1;


-- =============================================================================
-- 1) FFM / Swathi-like TARGET (Scenario B — unchanged)
-- =============================================================================
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

CREATE UNIQUE CLUSTERED INDEX CX_ffm_target
    ON #ffm_target (FFM_Coverage_Year, FFM_Policy_ID, FFM_Enrollee_ID);
CREATE NONCLUSTERED INDEX IX_ffm_enrollee
    ON #ffm_target (FFM_Enrollee_ID) INCLUDE (FFM_Policy_ID, FFM_Issuer);
CREATE NONCLUSTERED INDEX IX_ffm_policy
    ON #ffm_target (FFM_Policy_ID) INCLUDE (FFM_Enrollee_ID, FFM_Issuer);

DECLARE @ffm_pair_count BIGINT = (SELECT COUNT(*) FROM #ffm_target);

IF @enforce_expected_count = 1 AND @ffm_pair_count <> @expected_ffm_pairs
BEGIN
    RAISERROR(
        'FFM target has %I64d pairs; expected %I64d. Aborting reverse reconciliation.',
        16, 1, @ffm_pair_count, @expected_ffm_pairs
    );
    RETURN;
END;


-- =============================================================================
-- 2) INBOUND STATUS DIAGNOSTICS
-- =============================================================================
-- A) All-year inventory (context)
-- B) 2026 inventory (scope used for this reconciliation)
-- =============================================================================
IF OBJECT_ID('tempdb..#inbound_status_diag_all') IS NOT NULL DROP TABLE #inbound_status_diag_all;
IF OBJECT_ID('tempdb..#inbound_status_diag_2026') IS NOT NULL DROP TABLE #inbound_status_diag_2026;

SELECT
    'ALL_YEARS' AS inventory_scope,
    CASE
        WHEN UPPER(LTRIM(RTRIM(ia.enrolleeStatus))) = 'CONFIRM' THEN 'CONFIRM'
        WHEN UPPER(LTRIM(RTRIM(ia.enrolleeStatus))) = 'CANCEL'  THEN 'CANCEL'
        WHEN UPPER(LTRIM(RTRIM(ia.enrolleeStatus))) = 'TERM'    THEN 'TERM'
        WHEN ia.enrolleeStatus IS NULL OR LTRIM(RTRIM(ia.enrolleeStatus)) = '' THEN 'NULL_OR_BLANK'
        ELSE 'UNMAPPED_OTHER'
    END AS status_bucket,
    ia.enrolleeStatus AS status_raw,
    COUNT(*) AS raw_row_count
INTO #inbound_status_diag_all
FROM dbo.inbound_automation AS ia
GROUP BY
    CASE
        WHEN UPPER(LTRIM(RTRIM(ia.enrolleeStatus))) = 'CONFIRM' THEN 'CONFIRM'
        WHEN UPPER(LTRIM(RTRIM(ia.enrolleeStatus))) = 'CANCEL'  THEN 'CANCEL'
        WHEN UPPER(LTRIM(RTRIM(ia.enrolleeStatus))) = 'TERM'    THEN 'TERM'
        WHEN ia.enrolleeStatus IS NULL OR LTRIM(RTRIM(ia.enrolleeStatus)) = '' THEN 'NULL_OR_BLANK'
        ELSE 'UNMAPPED_OTHER'
    END,
    ia.enrolleeStatus;

SELECT
    'COVERAGE_YEAR_2026' AS inventory_scope,
    CASE
        WHEN UPPER(LTRIM(RTRIM(ia.enrolleeStatus))) = 'CONFIRM' THEN 'CONFIRM'
        WHEN UPPER(LTRIM(RTRIM(ia.enrolleeStatus))) = 'CANCEL'  THEN 'CANCEL'
        WHEN UPPER(LTRIM(RTRIM(ia.enrolleeStatus))) = 'TERM'    THEN 'TERM'
        WHEN ia.enrolleeStatus IS NULL OR LTRIM(RTRIM(ia.enrolleeStatus)) = '' THEN 'NULL_OR_BLANK'
        ELSE 'UNMAPPED_OTHER'
    END AS status_bucket,
    ia.enrolleeStatus AS status_raw,
    COUNT(*) AS raw_row_count
INTO #inbound_status_diag_2026
FROM dbo.inbound_automation AS ia
WHERE ia.coverage_year = @coverage_year
GROUP BY
    CASE
        WHEN UPPER(LTRIM(RTRIM(ia.enrolleeStatus))) = 'CONFIRM' THEN 'CONFIRM'
        WHEN UPPER(LTRIM(RTRIM(ia.enrolleeStatus))) = 'CANCEL'  THEN 'CANCEL'
        WHEN UPPER(LTRIM(RTRIM(ia.enrolleeStatus))) = 'TERM'    THEN 'TERM'
        WHEN ia.enrolleeStatus IS NULL OR LTRIM(RTRIM(ia.enrolleeStatus)) = '' THEN 'NULL_OR_BLANK'
        ELSE 'UNMAPPED_OTHER'
    END,
    ia.enrolleeStatus;


-- =============================================================================
-- 3) 2026 INBOUND CONFIRM — BUSINESS ENTITY + FULL EVIDENCE BRIDGE
-- =============================================================================
-- Primary population filter:
--   coverage_year = 2026
--   AND enrolleeStatus = 'CONFIRM'
--
-- Business entity key (for counting / one reverse-master row):
--   issuer | coverage_year | Canonical_Policy_Key | Canonical_Enrollee_Key
-- where Canonical_* preference is used ONLY to define the entity key.
--
-- Evidence bridge:
--   ALL physical CONFIRM rows that belong to a complete business entity.
--   Matching uses this bridge so alternate identifier values on older rows
--   are NOT discarded before evaluation.
--
-- Representative row (latest maint date / id) is kept for display fields only.
-- =============================================================================
IF OBJECT_ID('tempdb..#inbound_confirm_raw') IS NOT NULL DROP TABLE #inbound_confirm_raw;

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
    ia.folder_year,
    ia.folder_month,
    ia.household_or_employee_case_id,
    ia.relationship,
    COALESCE(
        NULLIF(LTRIM(RTRIM(CAST(ia.member_id AS VARCHAR(100)))), ''),
        NULLIF(LTRIM(RTRIM(CAST(ia.issuer_indiv_identifier AS VARCHAR(100)))), ''),
        NULLIF(LTRIM(RTRIM(CAST(ia.exchg_assigned_enrollee_id AS VARCHAR(100)))), '')
    ) AS Canonical_Enrollee_Key,
    COALESCE(
        NULLIF(LTRIM(RTRIM(CAST(ia.policy_id AS VARCHAR(100)))), ''),
        NULLIF(LTRIM(RTRIM(CAST(ia.health_coverage_policy_no AS VARCHAR(100)))), '')
    ) AS Canonical_Policy_Key
INTO #inbound_confirm_raw
FROM dbo.inbound_automation AS ia
WHERE ia.coverage_year = @coverage_year
  AND UPPER(LTRIM(RTRIM(ia.enrolleeStatus))) = 'CONFIRM';

DECLARE @inbound_confirm_raw_count BIGINT = (SELECT COUNT(*) FROM #inbound_confirm_raw);

DECLARE @inbound_confirm_raw_incomplete BIGINT = (
    SELECT COUNT(*)
    FROM #inbound_confirm_raw
    WHERE Canonical_Enrollee_Key IS NULL OR Canonical_Policy_Key IS NULL
);

-- Bridge: every complete physical row, tagged with business entity key
IF OBJECT_ID('tempdb..#inbound_confirm_bridge') IS NOT NULL DROP TABLE #inbound_confirm_bridge;

SELECT
    CAST(r.Inbound_Issuer AS VARCHAR(20))
        + '|' + CAST(r.Inbound_Coverage_Year AS VARCHAR(10))
        + '|' + r.Canonical_Policy_Key
        + '|' + r.Canonical_Enrollee_Key AS Inbound_Business_Key,
    r.*
INTO #inbound_confirm_bridge
FROM #inbound_confirm_raw AS r
WHERE r.Canonical_Enrollee_Key IS NOT NULL
  AND r.Canonical_Policy_Key IS NOT NULL;

CREATE CLUSTERED INDEX CX_bridge ON #inbound_confirm_bridge (Inbound_Business_Key, inbound_row_id);
CREATE NONCLUSTERED INDEX IX_br_member ON #inbound_confirm_bridge (Inbound_Member_ID) INCLUDE (Inbound_Business_Key);
CREATE NONCLUSTERED INDEX IX_br_issuer_indiv ON #inbound_confirm_bridge (Inbound_Issuer_Indiv_Identifier) INCLUDE (Inbound_Business_Key);
CREATE NONCLUSTERED INDEX IX_br_exchg ON #inbound_confirm_bridge (Inbound_Exchange_Assigned_Enrollee_ID) INCLUDE (Inbound_Business_Key);
CREATE NONCLUSTERED INDEX IX_br_policy ON #inbound_confirm_bridge (Inbound_Policy_ID) INCLUDE (Inbound_Business_Key);
CREATE NONCLUSTERED INDEX IX_br_hc ON #inbound_confirm_bridge (Inbound_Health_Coverage_Policy_No) INCLUDE (Inbound_Business_Key);

DECLARE @inbound_confirm_bridge_rows BIGINT = (SELECT COUNT(*) FROM #inbound_confirm_bridge);

-- Entity header: one row per business entity + representative display fields
IF OBJECT_ID('tempdb..#inbound_confirm_entity') IS NOT NULL DROP TABLE #inbound_confirm_entity;

SELECT
    b.Inbound_Business_Key,
    b.Inbound_Issuer,
    b.Inbound_Coverage_Year,
    b.Canonical_Enrollee_Key,
    b.Canonical_Policy_Key,
    COUNT(*) AS Physical_Confirm_Row_Count,
    MAX(CASE WHEN b.Inbound_Member_ID IS NOT NULL THEN 1 ELSE 0 END) AS Has_Member_ID_Evidence,
    MAX(CASE WHEN b.Inbound_Issuer_Indiv_Identifier IS NOT NULL THEN 1 ELSE 0 END) AS Has_Issuer_Indiv_Evidence,
    MAX(CASE WHEN b.Inbound_Exchange_Assigned_Enrollee_ID IS NOT NULL THEN 1 ELSE 0 END) AS Has_Exchg_Enrollee_Evidence,
    MAX(CASE WHEN b.Inbound_Policy_ID IS NOT NULL THEN 1 ELSE 0 END) AS Has_Policy_ID_Evidence,
    MAX(CASE WHEN b.Inbound_Health_Coverage_Policy_No IS NOT NULL THEN 1 ELSE 0 END) AS Has_Health_Coverage_Policy_Evidence
INTO #inbound_confirm_entity
FROM #inbound_confirm_bridge AS b
GROUP BY
    b.Inbound_Business_Key,
    b.Inbound_Issuer,
    b.Inbound_Coverage_Year,
    b.Canonical_Enrollee_Key,
    b.Canonical_Policy_Key;

-- Distinct identifier value lists across ALL physical rows (evidence, not COALESCE-hidden)
IF OBJECT_ID('tempdb..#entity_member_ids') IS NOT NULL DROP TABLE #entity_member_ids;
IF OBJECT_ID('tempdb..#entity_issuer_indiv_ids') IS NOT NULL DROP TABLE #entity_issuer_indiv_ids;
IF OBJECT_ID('tempdb..#entity_exchg_ids') IS NOT NULL DROP TABLE #entity_exchg_ids;
IF OBJECT_ID('tempdb..#entity_policy_ids') IS NOT NULL DROP TABLE #entity_policy_ids;
IF OBJECT_ID('tempdb..#entity_hc_policy_ids') IS NOT NULL DROP TABLE #entity_hc_policy_ids;

SELECT
    Inbound_Business_Key,
    STRING_AGG(CAST(id_val AS NVARCHAR(100)), N' | ') WITHIN GROUP (ORDER BY id_val) AS Distinct_Member_ID_Values
INTO #entity_member_ids
FROM (SELECT DISTINCT Inbound_Business_Key, Inbound_Member_ID AS id_val
      FROM #inbound_confirm_bridge WHERE Inbound_Member_ID IS NOT NULL) d
GROUP BY Inbound_Business_Key;

SELECT
    Inbound_Business_Key,
    STRING_AGG(CAST(id_val AS NVARCHAR(100)), N' | ') WITHIN GROUP (ORDER BY id_val) AS Distinct_Issuer_Indiv_Values
INTO #entity_issuer_indiv_ids
FROM (SELECT DISTINCT Inbound_Business_Key, Inbound_Issuer_Indiv_Identifier AS id_val
      FROM #inbound_confirm_bridge WHERE Inbound_Issuer_Indiv_Identifier IS NOT NULL) d
GROUP BY Inbound_Business_Key;

SELECT
    Inbound_Business_Key,
    STRING_AGG(CAST(id_val AS NVARCHAR(100)), N' | ') WITHIN GROUP (ORDER BY id_val) AS Distinct_Exchg_Enrollee_Values
INTO #entity_exchg_ids
FROM (SELECT DISTINCT Inbound_Business_Key, Inbound_Exchange_Assigned_Enrollee_ID AS id_val
      FROM #inbound_confirm_bridge WHERE Inbound_Exchange_Assigned_Enrollee_ID IS NOT NULL) d
GROUP BY Inbound_Business_Key;

SELECT
    Inbound_Business_Key,
    STRING_AGG(CAST(id_val AS NVARCHAR(100)), N' | ') WITHIN GROUP (ORDER BY id_val) AS Distinct_Policy_ID_Values
INTO #entity_policy_ids
FROM (SELECT DISTINCT Inbound_Business_Key, Inbound_Policy_ID AS id_val
      FROM #inbound_confirm_bridge WHERE Inbound_Policy_ID IS NOT NULL) d
GROUP BY Inbound_Business_Key;

SELECT
    Inbound_Business_Key,
    STRING_AGG(CAST(id_val AS NVARCHAR(100)), N' | ') WITHIN GROUP (ORDER BY id_val) AS Distinct_Health_Coverage_Policy_Values
INTO #entity_hc_policy_ids
FROM (SELECT DISTINCT Inbound_Business_Key, Inbound_Health_Coverage_Policy_No AS id_val
      FROM #inbound_confirm_bridge WHERE Inbound_Health_Coverage_Policy_No IS NOT NULL) d
GROUP BY Inbound_Business_Key;

-- Representative (latest) physical row for display dates / source_file
IF OBJECT_ID('tempdb..#entity_rep') IS NOT NULL DROP TABLE #entity_rep;

SELECT *
INTO #entity_rep
FROM (
    SELECT
        b.*,
        ROW_NUMBER() OVER (
            PARTITION BY b.Inbound_Business_Key
            ORDER BY b.member_maint_effective_date DESC, b.inbound_row_id DESC
        ) AS rn
    FROM #inbound_confirm_bridge AS b
) x
WHERE rn = 1;

CREATE UNIQUE CLUSTERED INDEX CX_entity ON #inbound_confirm_entity (Inbound_Business_Key);
CREATE UNIQUE CLUSTERED INDEX CX_rep ON #entity_rep (Inbound_Business_Key);

DECLARE @inbound_confirm_business_count BIGINT = (SELECT COUNT(*) FROM #inbound_confirm_entity);
DECLARE @physical_rows_collapsed BIGINT = @inbound_confirm_bridge_rows - @inbound_confirm_business_count;


-- =============================================================================
-- 4) MATCH USING FULL EVIDENCE BRIDGE (all physical rows in each entity)
-- =============================================================================
-- Exact match rule:
--   enrollee evidence and policy evidence must map to the SAME FFM target pair
--   and the SAME Inbound_Business_Key (entity). Evidence may come from different
--   physical rows within that entity — not from unrelated entities/transactions.
-- =============================================================================
IF OBJECT_ID('tempdb..#enrollee_hits') IS NOT NULL DROP TABLE #enrollee_hits;

;WITH e_raw AS (
    SELECT br.Inbound_Business_Key, f.FFM_Coverage_Year, f.FFM_Policy_ID, f.FFM_Enrollee_ID, f.FFM_Issuer,
           CAST('MEMBER_ID' AS VARCHAR(40)) AS Enrollee_Hit_Type
    FROM #inbound_confirm_bridge AS br
    INNER JOIN #ffm_target AS f ON f.FFM_Enrollee_ID = br.Inbound_Member_ID
    WHERE br.Inbound_Member_ID IS NOT NULL

    UNION ALL

    SELECT br.Inbound_Business_Key, f.FFM_Coverage_Year, f.FFM_Policy_ID, f.FFM_Enrollee_ID, f.FFM_Issuer,
           CAST('ISSUER_INDIV_IDENTIFIER' AS VARCHAR(40))
    FROM #inbound_confirm_bridge AS br
    INNER JOIN #ffm_target AS f ON f.FFM_Enrollee_ID = br.Inbound_Issuer_Indiv_Identifier
    WHERE br.Inbound_Issuer_Indiv_Identifier IS NOT NULL

    UNION ALL

    SELECT br.Inbound_Business_Key, f.FFM_Coverage_Year, f.FFM_Policy_ID, f.FFM_Enrollee_ID, f.FFM_Issuer,
           CAST('EXCHG_ASSIGNED_ENROLLEE_ID' AS VARCHAR(40))
    FROM #inbound_confirm_bridge AS br
    INNER JOIN #ffm_target AS f ON f.FFM_Enrollee_ID = br.Inbound_Exchange_Assigned_Enrollee_ID
    WHERE br.Inbound_Exchange_Assigned_Enrollee_ID IS NOT NULL
)
SELECT
    Inbound_Business_Key,
    FFM_Coverage_Year,
    FFM_Policy_ID,
    FFM_Enrollee_ID,
    FFM_Issuer,
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
GROUP BY Inbound_Business_Key, FFM_Coverage_Year, FFM_Policy_ID, FFM_Enrollee_ID, FFM_Issuer;

CREATE CLUSTERED INDEX CX_eh ON #enrollee_hits (Inbound_Business_Key, FFM_Policy_ID, FFM_Enrollee_ID);


IF OBJECT_ID('tempdb..#policy_hits') IS NOT NULL DROP TABLE #policy_hits;

;WITH p_raw AS (
    SELECT br.Inbound_Business_Key, f.FFM_Coverage_Year, f.FFM_Policy_ID, f.FFM_Enrollee_ID, f.FFM_Issuer,
           CAST('POLICY_ID' AS VARCHAR(40)) AS Policy_Hit_Type
    FROM #inbound_confirm_bridge AS br
    INNER JOIN #ffm_target AS f ON f.FFM_Policy_ID = br.Inbound_Policy_ID
    WHERE br.Inbound_Policy_ID IS NOT NULL

    UNION ALL

    SELECT br.Inbound_Business_Key, f.FFM_Coverage_Year, f.FFM_Policy_ID, f.FFM_Enrollee_ID, f.FFM_Issuer,
           CAST('HEALTH_COVERAGE_POLICY_NO' AS VARCHAR(40))
    FROM #inbound_confirm_bridge AS br
    INNER JOIN #ffm_target AS f ON f.FFM_Policy_ID = br.Inbound_Health_Coverage_Policy_No
    WHERE br.Inbound_Health_Coverage_Policy_No IS NOT NULL
)
SELECT
    Inbound_Business_Key,
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
GROUP BY Inbound_Business_Key, FFM_Coverage_Year, FFM_Policy_ID, FFM_Enrollee_ID, FFM_Issuer;

CREATE CLUSTERED INDEX CX_ph ON #policy_hits (Inbound_Business_Key, FFM_Policy_ID, FFM_Enrollee_ID);


IF OBJECT_ID('tempdb..#exact_hits') IS NOT NULL DROP TABLE #exact_hits;

SELECT
    e.Inbound_Business_Key,
    e.FFM_Coverage_Year,
    e.FFM_Policy_ID AS Matched_FFM_Policy_ID,
    e.FFM_Enrollee_ID AS Matched_FFM_Enrollee_ID,
    e.FFM_Issuer AS Matched_FFM_Issuer,
    e.Matched_Enrollee_ID_Type,
    p.Matched_Policy_ID_Type
INTO #exact_hits
FROM #enrollee_hits AS e
INNER JOIN #policy_hits AS p
    ON p.Inbound_Business_Key = e.Inbound_Business_Key
   AND p.FFM_Coverage_Year = e.FFM_Coverage_Year
   AND p.FFM_Policy_ID = e.FFM_Policy_ID
   AND p.FFM_Enrollee_ID = e.FFM_Enrollee_ID;

CREATE CLUSTERED INDEX CX_exact ON #exact_hits (Inbound_Business_Key);

-- Collapse to ONE classification row per inbound business entity
IF OBJECT_ID('tempdb..#exact_best') IS NOT NULL DROP TABLE #exact_best;
SELECT * INTO #exact_best FROM (
    SELECT *, ROW_NUMBER() OVER (
        PARTITION BY Inbound_Business_Key
        ORDER BY Matched_FFM_Policy_ID, Matched_FFM_Enrollee_ID
    ) AS rn FROM #exact_hits
) x WHERE rn = 1;

IF OBJECT_ID('tempdb..#enrollee_only_best') IS NOT NULL DROP TABLE #enrollee_only_best;
SELECT * INTO #enrollee_only_best FROM (
    SELECT e.*, ROW_NUMBER() OVER (
        PARTITION BY e.Inbound_Business_Key ORDER BY e.FFM_Policy_ID, e.FFM_Enrollee_ID
    ) AS rn
    FROM #enrollee_hits e
    WHERE NOT EXISTS (SELECT 1 FROM #exact_hits x WHERE x.Inbound_Business_Key = e.Inbound_Business_Key)
) x WHERE rn = 1;

IF OBJECT_ID('tempdb..#policy_only_best') IS NOT NULL DROP TABLE #policy_only_best;
SELECT * INTO #policy_only_best FROM (
    SELECT p.*, ROW_NUMBER() OVER (
        PARTITION BY p.Inbound_Business_Key ORDER BY p.FFM_Policy_ID, p.FFM_Enrollee_ID
    ) AS rn
    FROM #policy_hits p
    WHERE NOT EXISTS (SELECT 1 FROM #exact_hits x WHERE x.Inbound_Business_Key = p.Inbound_Business_Key)
      AND NOT EXISTS (SELECT 1 FROM #enrollee_hits e WHERE e.Inbound_Business_Key = p.Inbound_Business_Key)
) x WHERE rn = 1;


-- =============================================================================
-- 5) REVERSE MASTER (one row per inbound business entity)
-- =============================================================================
IF OBJECT_ID('tempdb..#reverse_master') IS NOT NULL DROP TABLE #reverse_master;

SELECT
    ent.Inbound_Business_Key,
    ent.Inbound_Issuer,
    ent.Inbound_Coverage_Year,
    ent.Canonical_Enrollee_Key,
    ent.Canonical_Policy_Key,
    ent.Physical_Confirm_Row_Count,
    ent.Has_Member_ID_Evidence,
    ent.Has_Issuer_Indiv_Evidence,
    ent.Has_Exchg_Enrollee_Evidence,
    ent.Has_Policy_ID_Evidence,
    ent.Has_Health_Coverage_Policy_Evidence,
    mid.Distinct_Member_ID_Values,
    iid.Distinct_Issuer_Indiv_Values,
    xid.Distinct_Exchg_Enrollee_Values,
    pid.Distinct_Policy_ID_Values,
    hid.Distinct_Health_Coverage_Policy_Values,

    /* Representative display fields (latest physical row) — not sole ID evidence */
    rep.inbound_row_id AS Representative_Inbound_Row_ID,
    rep.Inbound_Member_ID AS Rep_Member_ID,
    rep.Inbound_Issuer_Indiv_Identifier AS Rep_Issuer_Indiv_Identifier,
    rep.Inbound_Exchange_Assigned_Enrollee_ID AS Rep_Exchange_Assigned_Enrollee_ID,
    rep.Inbound_Policy_ID AS Rep_Policy_ID,
    rep.Inbound_Health_Coverage_Policy_No AS Rep_Health_Coverage_Policy_No,
    rep.Inbound_Status,
    rep.member_maint_effective_date,
    rep.benefit_effective_date,
    rep.benefit_end_date,
    rep.Inbound_Source_File,
    rep.folder_year,
    rep.folder_month,
    rep.household_or_employee_case_id,
    rep.relationship,

    CASE
        WHEN ex.Inbound_Business_Key IS NOT NULL THEN 'YES'
        WHEN eo.Inbound_Business_Key IS NOT NULL THEN 'PARTIAL_ENROLLEE'
        WHEN po.Inbound_Business_Key IS NOT NULL THEN 'PARTIAL_POLICY'
        ELSE 'NO'
    END AS FFM_Found_Flag,

    CASE
        WHEN ex.Inbound_Business_Key IS NOT NULL THEN ex.Matched_FFM_Policy_ID
        WHEN eo.Inbound_Business_Key IS NOT NULL THEN eo.FFM_Policy_ID
        WHEN po.Inbound_Business_Key IS NOT NULL THEN po.FFM_Policy_ID
    END AS Matched_FFM_Policy_ID,

    CASE
        WHEN ex.Inbound_Business_Key IS NOT NULL THEN ex.Matched_FFM_Enrollee_ID
        WHEN eo.Inbound_Business_Key IS NOT NULL THEN eo.FFM_Enrollee_ID
        WHEN po.Inbound_Business_Key IS NOT NULL THEN po.FFM_Enrollee_ID
    END AS Matched_FFM_Enrollee_ID,

    CASE
        WHEN ex.Inbound_Business_Key IS NOT NULL THEN ex.Matched_FFM_Issuer
        WHEN eo.Inbound_Business_Key IS NOT NULL THEN eo.FFM_Issuer
        WHEN po.Inbound_Business_Key IS NOT NULL THEN po.FFM_Issuer
    END AS Matched_FFM_Issuer,

    CASE
        WHEN ex.Inbound_Business_Key IS NOT NULL THEN ex.Matched_Enrollee_ID_Type
        WHEN eo.Inbound_Business_Key IS NOT NULL THEN eo.Matched_Enrollee_ID_Type
    END AS Matched_Enrollee_ID_Type,

    CASE
        WHEN ex.Inbound_Business_Key IS NOT NULL THEN ex.Matched_Policy_ID_Type
        WHEN po.Inbound_Business_Key IS NOT NULL THEN po.Matched_Policy_ID_Type
    END AS Matched_Policy_ID_Type,

    CASE
        WHEN ex.Inbound_Business_Key IS NOT NULL THEN 'EXACT_IN_FFM_TARGET'
        WHEN eo.Inbound_Business_Key IS NOT NULL THEN 'ENROLLEE_IN_TARGET_DIFFERENT_POLICY'
        WHEN po.Inbound_Business_Key IS NOT NULL THEN 'POLICY_IN_TARGET_DIFFERENT_ENROLLEE'
        ELSE 'INBOUND_CONFIRM_NOT_IN_FFM_TARGET'
    END AS Reverse_Category
INTO #reverse_master
FROM #inbound_confirm_entity AS ent
INNER JOIN #entity_rep AS rep
    ON rep.Inbound_Business_Key = ent.Inbound_Business_Key
LEFT JOIN #entity_member_ids AS mid ON mid.Inbound_Business_Key = ent.Inbound_Business_Key
LEFT JOIN #entity_issuer_indiv_ids AS iid ON iid.Inbound_Business_Key = ent.Inbound_Business_Key
LEFT JOIN #entity_exchg_ids AS xid ON xid.Inbound_Business_Key = ent.Inbound_Business_Key
LEFT JOIN #entity_policy_ids AS pid ON pid.Inbound_Business_Key = ent.Inbound_Business_Key
LEFT JOIN #entity_hc_policy_ids AS hid ON hid.Inbound_Business_Key = ent.Inbound_Business_Key
LEFT JOIN #exact_best AS ex ON ex.Inbound_Business_Key = ent.Inbound_Business_Key
LEFT JOIN #enrollee_only_best AS eo ON eo.Inbound_Business_Key = ent.Inbound_Business_Key
LEFT JOIN #policy_only_best AS po ON po.Inbound_Business_Key = ent.Inbound_Business_Key;

CREATE UNIQUE CLUSTERED INDEX CX_rev ON #reverse_master (Inbound_Business_Key);
CREATE NONCLUSTERED INDEX IX_rev_cat ON #reverse_master (Reverse_Category, Inbound_Issuer);


-- Diagnostics for NOT_IN_FFM_TARGET (all-year Enrollments_TEST; does not change reverse category)
IF OBJECT_ID('tempdb..#diag_enrollee') IS NOT NULL DROP TABLE #diag_enrollee;
IF OBJECT_ID('tempdb..#diag_policy') IS NOT NULL DROP TABLE #diag_policy;

;WITH not_in AS (
    SELECT * FROM #reverse_master WHERE Reverse_Category = 'INBOUND_CONFIRM_NOT_IN_FFM_TARGET'
),
enr_hits AS (
    SELECT n.Inbound_Business_Key, e.coverage_year, e.hios_issuer_id,
           CAST(e.enrollment_id AS VARCHAR(100)) AS enrollment_id,
           CAST(e.enrollee_id AS VARCHAR(100)) AS enrollee_id,
           e.enrollment_status_description
    FROM not_in n
    INNER JOIN #inbound_confirm_bridge br ON br.Inbound_Business_Key = n.Inbound_Business_Key
    INNER JOIN dbo.Enrollments_TEST e ON CAST(e.enrollee_id AS VARCHAR(100)) = br.Inbound_Member_ID
    WHERE br.Inbound_Member_ID IS NOT NULL
    UNION
    SELECT n.Inbound_Business_Key, e.coverage_year, e.hios_issuer_id,
           CAST(e.enrollment_id AS VARCHAR(100)), CAST(e.enrollee_id AS VARCHAR(100)),
           e.enrollment_status_description
    FROM not_in n
    INNER JOIN #inbound_confirm_bridge br ON br.Inbound_Business_Key = n.Inbound_Business_Key
    INNER JOIN dbo.Enrollments_TEST e ON CAST(e.enrollee_id AS VARCHAR(100)) = br.Inbound_Issuer_Indiv_Identifier
    WHERE br.Inbound_Issuer_Indiv_Identifier IS NOT NULL
    UNION
    SELECT n.Inbound_Business_Key, e.coverage_year, e.hios_issuer_id,
           CAST(e.enrollment_id AS VARCHAR(100)), CAST(e.enrollee_id AS VARCHAR(100)),
           e.enrollment_status_description
    FROM not_in n
    INNER JOIN #inbound_confirm_bridge br ON br.Inbound_Business_Key = n.Inbound_Business_Key
    INNER JOIN dbo.Enrollments_TEST e ON CAST(e.enrollee_id AS VARCHAR(100)) = br.Inbound_Exchange_Assigned_Enrollee_ID
    WHERE br.Inbound_Exchange_Assigned_Enrollee_ID IS NOT NULL
)
SELECT DISTINCT * INTO #diag_enrollee FROM enr_hits;

;WITH not_in AS (
    SELECT * FROM #reverse_master WHERE Reverse_Category = 'INBOUND_CONFIRM_NOT_IN_FFM_TARGET'
),
pol_hits AS (
    SELECT n.Inbound_Business_Key, e.coverage_year, e.hios_issuer_id,
           CAST(e.enrollment_id AS VARCHAR(100)) AS enrollment_id,
           CAST(e.enrollee_id AS VARCHAR(100)) AS enrollee_id,
           e.enrollment_status_description
    FROM not_in n
    INNER JOIN #inbound_confirm_bridge br ON br.Inbound_Business_Key = n.Inbound_Business_Key
    INNER JOIN dbo.Enrollments_TEST e ON CAST(e.enrollment_id AS VARCHAR(100)) = br.Inbound_Policy_ID
    WHERE br.Inbound_Policy_ID IS NOT NULL
    UNION
    SELECT n.Inbound_Business_Key, e.coverage_year, e.hios_issuer_id,
           CAST(e.enrollment_id AS VARCHAR(100)), CAST(e.enrollee_id AS VARCHAR(100)),
           e.enrollment_status_description
    FROM not_in n
    INNER JOIN #inbound_confirm_bridge br ON br.Inbound_Business_Key = n.Inbound_Business_Key
    INNER JOIN dbo.Enrollments_TEST e ON CAST(e.enrollment_id AS VARCHAR(100)) = br.Inbound_Health_Coverage_Policy_No
    WHERE br.Inbound_Health_Coverage_Policy_No IS NOT NULL
)
SELECT DISTINCT * INTO #diag_policy FROM pol_hits;

CREATE NONCLUSTERED INDEX IX_de ON #diag_enrollee (Inbound_Business_Key);
CREATE NONCLUSTERED INDEX IX_dp ON #diag_policy (Inbound_Business_Key);

IF OBJECT_ID('tempdb..#reverse_with_diag') IS NOT NULL DROP TABLE #reverse_with_diag;

SELECT
    m.*,
    CASE
        WHEN m.Reverse_Category <> 'INBOUND_CONFIRM_NOT_IN_FFM_TARGET' THEN NULL
        WHEN EXISTS (
            SELECT 1 FROM #diag_enrollee de
            INNER JOIN #diag_policy dp
                ON dp.Inbound_Business_Key = de.Inbound_Business_Key
               AND dp.coverage_year = de.coverage_year
               AND dp.enrollment_id = de.enrollment_id
               AND dp.enrollee_id = de.enrollee_id
            WHERE de.Inbound_Business_Key = m.Inbound_Business_Key
              AND de.coverage_year = @coverage_year
              AND UPPER(LTRIM(RTRIM(de.enrollment_status_description))) NOT IN ('ENROLLED', 'PENDING')
        ) THEN 'IN_ENROLLMENTS_2026_OUTSIDE_ENROLLED_PENDING'
        WHEN EXISTS (
            SELECT 1 FROM #diag_enrollee de
            INNER JOIN #diag_policy dp
                ON dp.Inbound_Business_Key = de.Inbound_Business_Key
               AND dp.coverage_year = de.coverage_year
               AND dp.enrollment_id = de.enrollment_id
               AND dp.enrollee_id = de.enrollee_id
            WHERE de.Inbound_Business_Key = m.Inbound_Business_Key
              AND de.coverage_year <> @coverage_year
        ) THEN 'IN_ENROLLMENTS_OTHER_COVERAGE_YEAR'
        WHEN EXISTS (SELECT 1 FROM #diag_enrollee de WHERE de.Inbound_Business_Key = m.Inbound_Business_Key)
         AND EXISTS (SELECT 1 FROM #diag_policy dp WHERE dp.Inbound_Business_Key = m.Inbound_Business_Key)
            THEN 'ENROLLEE_AND_POLICY_IN_ENROLLMENTS_BUT_NOT_SAME_PAIR'
        WHEN EXISTS (
            SELECT 1 FROM #diag_enrollee de
            WHERE de.Inbound_Business_Key = m.Inbound_Business_Key
              AND CAST(de.hios_issuer_id AS VARCHAR(20)) <> m.Inbound_Issuer
        ) THEN 'ENROLLEE_IN_ENROLLMENTS_DIFFERENT_ISSUER'
        WHEN EXISTS (SELECT 1 FROM #diag_enrollee de WHERE de.Inbound_Business_Key = m.Inbound_Business_Key)
            THEN 'ENROLLEE_ONLY_IN_ENROLLMENTS_TEST'
        WHEN EXISTS (SELECT 1 FROM #diag_policy dp WHERE dp.Inbound_Business_Key = m.Inbound_Business_Key)
            THEN 'POLICY_ONLY_IN_ENROLLMENTS_TEST'
        ELSE 'NOWHERE_IN_ENROLLMENTS_TEST'
    END AS Diagnostic_Category
INTO #reverse_with_diag
FROM #reverse_master AS m;

CREATE UNIQUE CLUSTERED INDEX CX_rwd ON #reverse_with_diag (Inbound_Business_Key);


DECLARE @rev_count BIGINT = (SELECT COUNT(*) FROM #reverse_with_diag);
DECLARE @cat_exact BIGINT = (SELECT COUNT(*) FROM #reverse_with_diag WHERE Reverse_Category = 'EXACT_IN_FFM_TARGET');
DECLARE @cat_enr BIGINT = (SELECT COUNT(*) FROM #reverse_with_diag WHERE Reverse_Category = 'ENROLLEE_IN_TARGET_DIFFERENT_POLICY');
DECLARE @cat_pol BIGINT = (SELECT COUNT(*) FROM #reverse_with_diag WHERE Reverse_Category = 'POLICY_IN_TARGET_DIFFERENT_ENROLLEE');
DECLARE @cat_not BIGINT = (SELECT COUNT(*) FROM #reverse_with_diag WHERE Reverse_Category = 'INBOUND_CONFIRM_NOT_IN_FFM_TARGET');

IF @rev_count <> @inbound_confirm_business_count
   OR (@cat_exact + @cat_enr + @cat_pol + @cat_not) <> @inbound_confirm_business_count
BEGIN
    RAISERROR(
        'Reverse classification total mismatch. master=%I64d entities=%I64d exact=%I64d enr=%I64d pol=%I64d not=%I64d',
        16, 1, @rev_count, @inbound_confirm_business_count, @cat_exact, @cat_enr, @cat_pol, @cat_not
    );
    RETURN;
END;


-- =============================================================================
-- RESULT SET 1 — CONTROL TOTALS
-- =============================================================================
SELECT
    @ffm_pair_count AS ffm_target_distinct_pairs,
    @inbound_confirm_raw_count AS inbound_2026_raw_confirm_rows,
    @inbound_confirm_raw_incomplete AS inbound_2026_raw_confirm_incomplete_keys_excluded,
    @inbound_confirm_bridge_rows AS inbound_2026_confirm_physical_rows_in_entities,
    @inbound_confirm_business_count AS inbound_2026_distinct_confirm_business_entities,
    @physical_rows_collapsed AS physical_confirm_rows_collapsed_into_entities,
    @cat_exact AS EXACT_IN_FFM_TARGET,
    @cat_enr AS ENROLLEE_IN_TARGET_DIFFERENT_POLICY,
    @cat_pol AS POLICY_IN_TARGET_DIFFERENT_ENROLLEE,
    @cat_not AS INBOUND_CONFIRM_NOT_IN_FFM_TARGET,
    CASE
        WHEN @ffm_pair_count = @expected_ffm_pairs
         AND @rev_count = @inbound_confirm_business_count
         AND (@cat_exact + @cat_enr + @cat_pol + @cat_not) = @inbound_confirm_business_count
            THEN 'PASS'
        ELSE 'FAIL'
    END AS control_status,
    'Entity key=issuer|2026|COALESCE(policy_id,hc_policy)|COALESCE(member,issuer_indiv,exchg); match uses FULL physical-row bridge; exact=same FFM pair via entity evidence' AS grain_and_match_note;


-- =============================================================================
-- RESULT SET 2 — REVERSE CATEGORY SUMMARY
-- =============================================================================
SELECT
    Reverse_Category,
    COUNT(*) AS record_count,
    CAST(100.0 * COUNT(*) / NULLIF(SUM(COUNT(*)) OVER (), 0) AS DECIMAL(8, 2)) AS percentage
FROM #reverse_with_diag
GROUP BY Reverse_Category
ORDER BY record_count DESC;


-- =============================================================================
-- RESULT SET 3 — ISSUER SUMMARY
-- =============================================================================
SELECT
    Inbound_Issuer,
    COUNT(*) AS inbound_distinct_confirm_entities,
    SUM(Physical_Confirm_Row_Count) AS inbound_physical_confirm_rows,
    SUM(CASE WHEN Reverse_Category = 'EXACT_IN_FFM_TARGET' THEN 1 ELSE 0 END) AS exact_in_ffm_target,
    SUM(CASE WHEN Reverse_Category = 'ENROLLEE_IN_TARGET_DIFFERENT_POLICY' THEN 1 ELSE 0 END) AS different_policy,
    SUM(CASE WHEN Reverse_Category = 'POLICY_IN_TARGET_DIFFERENT_ENROLLEE' THEN 1 ELSE 0 END) AS different_enrollee,
    SUM(CASE WHEN Reverse_Category = 'INBOUND_CONFIRM_NOT_IN_FFM_TARGET' THEN 1 ELSE 0 END) AS not_in_ffm_target
FROM #reverse_with_diag
GROUP BY Inbound_Issuer
ORDER BY inbound_distinct_confirm_entities DESC;


-- =============================================================================
-- RESULT SET 4 — FULL ROW-LEVEL REVERSE MASTER (one row per business entity)
-- =============================================================================
SELECT
    Inbound_Business_Key,
    Inbound_Issuer,
    Inbound_Coverage_Year,
    Canonical_Enrollee_Key,
    Canonical_Policy_Key,
    Physical_Confirm_Row_Count,
    Has_Member_ID_Evidence,
    Has_Issuer_Indiv_Evidence,
    Has_Exchg_Enrollee_Evidence,
    Has_Policy_ID_Evidence,
    Has_Health_Coverage_Policy_Evidence,
    Distinct_Member_ID_Values,
    Distinct_Issuer_Indiv_Values,
    Distinct_Exchg_Enrollee_Values,
    Distinct_Policy_ID_Values,
    Distinct_Health_Coverage_Policy_Values,
    Representative_Inbound_Row_ID,
    Rep_Member_ID,
    Rep_Issuer_Indiv_Identifier,
    Rep_Exchange_Assigned_Enrollee_ID,
    Rep_Policy_ID,
    Rep_Health_Coverage_Policy_No,
    Inbound_Status,
    member_maint_effective_date,
    benefit_effective_date,
    benefit_end_date,
    Inbound_Source_File,
    folder_year,
    folder_month,
    household_or_employee_case_id,
    relationship,
    FFM_Found_Flag,
    Matched_FFM_Policy_ID,
    Matched_FFM_Enrollee_ID,
    Matched_FFM_Issuer,
    Matched_Enrollee_ID_Type,
    Matched_Policy_ID_Type,
    Reverse_Category,
    Diagnostic_Category
FROM #reverse_with_diag
ORDER BY
    CASE Reverse_Category
        WHEN 'INBOUND_CONFIRM_NOT_IN_FFM_TARGET' THEN 1
        WHEN 'ENROLLEE_IN_TARGET_DIFFERENT_POLICY' THEN 2
        WHEN 'POLICY_IN_TARGET_DIFFERENT_ENROLLEE' THEN 3
        ELSE 4
    END,
    Inbound_Issuer,
    Canonical_Policy_Key,
    Canonical_Enrollee_Key;


-- =============================================================================
-- RESULT SET 5 — OURS BUT NOT THEIRS DETAIL
-- =============================================================================
SELECT
    Inbound_Business_Key,
    Inbound_Issuer,
    Inbound_Coverage_Year,
    Canonical_Enrollee_Key,
    Canonical_Policy_Key,
    Physical_Confirm_Row_Count,
    Distinct_Member_ID_Values,
    Distinct_Issuer_Indiv_Values,
    Distinct_Exchg_Enrollee_Values,
    Distinct_Policy_ID_Values,
    Distinct_Health_Coverage_Policy_Values,
    Representative_Inbound_Row_ID,
    Rep_Member_ID,
    Rep_Issuer_Indiv_Identifier,
    Rep_Exchange_Assigned_Enrollee_ID,
    Rep_Policy_ID,
    Rep_Health_Coverage_Policy_No,
    Inbound_Status,
    member_maint_effective_date,
    benefit_effective_date,
    benefit_end_date,
    Inbound_Source_File,
    folder_year,
    folder_month,
    household_or_employee_case_id,
    relationship,
    Reverse_Category,
    Diagnostic_Category
FROM #reverse_with_diag
WHERE Reverse_Category = 'INBOUND_CONFIRM_NOT_IN_FFM_TARGET'
ORDER BY Inbound_Issuer, Canonical_Policy_Key, Canonical_Enrollee_Key;


-- =============================================================================
-- RESULT SET 6 — ENROLLEE FOUND / DIFFERENT POLICY DETAIL
-- =============================================================================
SELECT
    Inbound_Business_Key,
    Inbound_Issuer,
    Inbound_Coverage_Year,
    Distinct_Member_ID_Values,
    Distinct_Issuer_Indiv_Values,
    Distinct_Exchg_Enrollee_Values,
    Distinct_Policy_ID_Values,
    Distinct_Health_Coverage_Policy_Values,
    Matched_FFM_Enrollee_ID,
    Matched_FFM_Policy_ID,
    Matched_FFM_Issuer,
    Matched_Enrollee_ID_Type,
    Physical_Confirm_Row_Count,
    Inbound_Source_File,
    member_maint_effective_date,
    Reverse_Category
FROM #reverse_with_diag
WHERE Reverse_Category = 'ENROLLEE_IN_TARGET_DIFFERENT_POLICY'
ORDER BY Inbound_Issuer, Matched_FFM_Enrollee_ID;


-- =============================================================================
-- RESULT SET 7 — POLICY FOUND / DIFFERENT ENROLLEE DETAIL
-- =============================================================================
SELECT
    Inbound_Business_Key,
    Inbound_Issuer,
    Inbound_Coverage_Year,
    Distinct_Member_ID_Values,
    Distinct_Issuer_Indiv_Values,
    Distinct_Exchg_Enrollee_Values,
    Distinct_Policy_ID_Values,
    Distinct_Health_Coverage_Policy_Values,
    Matched_FFM_Policy_ID,
    Matched_FFM_Enrollee_ID,
    Matched_FFM_Issuer,
    Matched_Policy_ID_Type,
    Physical_Confirm_Row_Count,
    Inbound_Source_File,
    member_maint_effective_date,
    Reverse_Category
FROM #reverse_with_diag
WHERE Reverse_Category = 'POLICY_IN_TARGET_DIFFERENT_ENROLLEE'
ORDER BY Inbound_Issuer, Matched_FFM_Policy_ID;


-- =============================================================================
-- RESULT SET 8 — STATUS DIAGNOSTICS
-- =============================================================================
-- 8a) All-year inbound status inventory (context)
SELECT
    inventory_scope,
    status_bucket,
    status_raw,
    raw_row_count,
    'Context only — NOT the reverse population filter' AS usage_note
FROM #inbound_status_diag_all
ORDER BY
    CASE status_bucket WHEN 'CONFIRM' THEN 1 WHEN 'CANCEL' THEN 2 WHEN 'TERM' THEN 3 ELSE 4 END,
    raw_row_count DESC;

-- 8b) 2026 inbound status inventory (scope used for this reconciliation)
SELECT
    inventory_scope,
    status_bucket,
    status_raw,
    raw_row_count,
    CASE
        WHEN status_bucket = 'CONFIRM' THEN 'PRIMARY reverse population (coverage_year=2026 CONFIRM)'
        ELSE '2026 context only — NOT mixed into reverse CONFIRM population'
    END AS usage_note
FROM #inbound_status_diag_2026
ORDER BY
    CASE status_bucket WHEN 'CONFIRM' THEN 1 WHEN 'CANCEL' THEN 2 WHEN 'TERM' THEN 3 ELSE 4 END,
    raw_row_count DESC;

SELECT
    'CONFIRM_INCOMPLETE_KEYS_2026' AS note,
    @inbound_confirm_raw_incomplete AS raw_2026_confirm_rows_missing_canonical_enrollee_or_policy,
    'Excluded from business entities / reverse master' AS explanation;
