

-- =============================================================================
-- DIAGNOSTIC — EXACT_ENROLLEE_POLICY_MATCH (755,548) coverage-year / lifecycle
-- =============================================================================
-- Purpose:
--   Explain coverage-year and lifecycle/status differences inside the existing
--   forward EXACT_ENROLLEE_POLICY_MATCH population WITHOUT changing matching.
--
-- Reuses EXACT matching logic from (DO NOT MODIFY):
--   sql/scenario_b_2026_834_row_level_reconciliation.sql
--
-- Baseline expectations (flag if drift):
--   FFM Scenario B target              = 960,531
--   EXACT_ENROLLEE_POLICY_MATCH count  = 755,548
--
-- Safety: READ ONLY on permanent tables. Temp tables/indexes only. No RCNI.
-- Evidence first — do not infer missing / failed renewal / incorrect.
-- =============================================================================

SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @coverage_year INT = 2026;
DECLARE @expected_target_pairs BIGINT = 960531;
DECLARE @expected_exact_matches BIGINT = 755548;
DECLARE @enforce_expected_count BIT = 1;


-- =============================================================================
-- PHASE 1 — FFM Scenario B target (unchanged definition)
-- =============================================================================
IF OBJECT_ID('tempdb..#target_population') IS NOT NULL DROP TABLE #target_population;

SELECT
    e.coverage_year                                              AS FFM_Coverage_Year,
    CAST(e.enrollment_id AS VARCHAR(100))                        AS FFM_Policy_ID,
    CAST(e.enrollee_id AS VARCHAR(100))                          AS FFM_Enrollee_ID,
    CAST(e.hios_issuer_id AS VARCHAR(20))                        AS FFM_Issuer,
    e.enrollment_status_description                              AS FFM_Enrollment_Status,
    e.enrollee_status_description                                AS FFM_Enrollee_Status,
    CASE
        WHEN UPPER(LTRIM(RTRIM(e.enrollment_status_description))) = 'ENROLLED' THEN 'CONFIRM'
        WHEN UPPER(LTRIM(RTRIM(e.enrollment_status_description))) = 'PENDING'  THEN 'PENDING'
        ELSE 'STATUS_MAPPING_REVIEW'
    END                                                          AS FFM_Status_Norm,
    COALESCE(
        e.enrollment_last_update_date,
        e.enrollment_create_date,
        e.benefit_effective_date
    )                                                            AS FFM_Event_Date,
    e.benefit_effective_date                                     AS FFM_Benefit_Effective_Date,
    e.benefit_end_date                                           AS FFM_Benefit_End_Date,
    e.enrollment_create_date                                     AS FFM_Create_Date,
    e.enrollment_last_update_date                                AS FFM_Last_Update_Date,
    e.household_id
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
        e.benefit_end_date,
        e.enrollment_create_date,
        e.enrollment_last_update_date,
        e.household_id,
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

CREATE UNIQUE CLUSTERED INDEX CX_target
    ON #target_population (FFM_Coverage_Year, FFM_Policy_ID, FFM_Enrollee_ID);
CREATE NONCLUSTERED INDEX IX_target_enrollee
    ON #target_population (FFM_Enrollee_ID)
    INCLUDE (FFM_Policy_ID, FFM_Issuer, FFM_Status_Norm, FFM_Event_Date);

DECLARE @target_count BIGINT = (SELECT COUNT(*) FROM #target_population);

IF @enforce_expected_count = 1 AND @target_count <> @expected_target_pairs
BEGIN
    RAISERROR(
        'TARGET FAILED: %I64d pairs; expected %I64d. Aborting diagnostic.',
        16, 1, @target_count, @expected_target_pairs
    );
    RETURN;
END;


-- =============================================================================
-- PHASE 2 — inbound working set (same enrollee-ID presence filter as forward)
-- Extra benefit columns are for diagnostics only; matching uses same fields.
-- =============================================================================
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
    ia.folder_year,
    ia.folder_month,
    ia.source_file AS Inbound_Source_File,
    ia.household_or_employee_case_id,
    ia.relationship
INTO #inbound
FROM dbo.inbound_automation AS ia
WHERE NULLIF(LTRIM(RTRIM(ia.member_id)), '') IS NOT NULL
   OR NULLIF(LTRIM(RTRIM(ia.issuer_indiv_identifier)), '') IS NOT NULL
   OR NULLIF(LTRIM(RTRIM(ia.exchg_assigned_enrollee_id)), '') IS NOT NULL;

CREATE CLUSTERED INDEX CX_inbound ON #inbound (inbound_row_id);
CREATE NONCLUSTERED INDEX IX_ib_member
    ON #inbound (Inbound_Member_ID)
    INCLUDE (Inbound_Policy_ID, Inbound_Health_Coverage_Policy_No, Inbound_Issuer, Inbound_Event_Date, Inbound_Status_Normalized, Inbound_Coverage_Year);
CREATE NONCLUSTERED INDEX IX_ib_issuer_indiv
    ON #inbound (Inbound_Issuer_Indiv_Identifier)
    INCLUDE (Inbound_Policy_ID, Inbound_Health_Coverage_Policy_No, Inbound_Issuer, Inbound_Event_Date, Inbound_Status_Normalized, Inbound_Coverage_Year);
CREATE NONCLUSTERED INDEX IX_ib_exchg
    ON #inbound (Inbound_Exchange_Assigned_Enrollee_ID)
    INCLUDE (Inbound_Policy_ID, Inbound_Health_Coverage_Policy_No, Inbound_Issuer, Inbound_Event_Date, Inbound_Status_Normalized, Inbound_Coverage_Year);
CREATE NONCLUSTERED INDEX IX_ib_policy
    ON #inbound (Inbound_Policy_ID)
    INCLUDE (Inbound_Member_ID, Inbound_Issuer_Indiv_Identifier, Inbound_Exchange_Assigned_Enrollee_ID, Inbound_Issuer, Inbound_Coverage_Year, Inbound_Status_Normalized);
CREATE NONCLUSTERED INDEX IX_ib_hc_policy
    ON #inbound (Inbound_Health_Coverage_Policy_No)
    INCLUDE (Inbound_Member_ID, Inbound_Issuer_Indiv_Identifier, Inbound_Exchange_Assigned_Enrollee_ID, Inbound_Issuer, Inbound_Coverage_Year, Inbound_Status_Normalized);


-- =============================================================================
-- Enrollee-first candidate hits (3 independent equi-join paths) — UNCHANGED
-- =============================================================================
IF OBJECT_ID('tempdb..#candidate_hits') IS NOT NULL DROP TABLE #candidate_hits;

;WITH hit_raw AS (
    SELECT t.FFM_Coverage_Year, t.FFM_Policy_ID, t.FFM_Enrollee_ID, i.inbound_row_id,
           CAST('MEMBER_ID' AS VARCHAR(40)) AS hit_type
    FROM #target_population AS t
    INNER JOIN #inbound AS i ON i.Inbound_Member_ID = t.FFM_Enrollee_ID

    UNION ALL

    SELECT t.FFM_Coverage_Year, t.FFM_Policy_ID, t.FFM_Enrollee_ID, i.inbound_row_id,
           CAST('ISSUER_INDIV_IDENTIFIER' AS VARCHAR(40))
    FROM #target_population AS t
    INNER JOIN #inbound AS i ON i.Inbound_Issuer_Indiv_Identifier = t.FFM_Enrollee_ID

    UNION ALL

    SELECT t.FFM_Coverage_Year, t.FFM_Policy_ID, t.FFM_Enrollee_ID, i.inbound_row_id,
           CAST('EXCHG_ASSIGNED_ENROLLEE_ID' AS VARCHAR(40))
    FROM #target_population AS t
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
        WHEN MAX(CASE WHEN hit_type = 'MEMBER_ID' THEN 1 ELSE 0 END) = 1
            THEN 'MEMBER_ID'
        WHEN MAX(CASE WHEN hit_type = 'ISSUER_INDIV_IDENTIFIER' THEN 1 ELSE 0 END) = 1
            THEN 'ISSUER_INDIV_IDENTIFIER'
        ELSE 'EXCHG_ASSIGNED_ENROLLEE_ID'
    END AS Matched_Inbound_ID_Type
INTO #candidate_hits
FROM hit_raw
GROUP BY FFM_Coverage_Year, FFM_Policy_ID, FFM_Enrollee_ID, inbound_row_id;

CREATE CLUSTERED INDEX CX_hits
    ON #candidate_hits (FFM_Enrollee_ID, FFM_Policy_ID, inbound_row_id);


-- =============================================================================
-- Score candidates (UNCHANGED hierarchy from forward reconciliation)
-- =============================================================================
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

    i.Inbound_Member_ID,
    i.Inbound_Issuer_Indiv_Identifier,
    i.Inbound_Exchange_Assigned_Enrollee_ID,
    CASE h.Matched_Inbound_ID_Type
        WHEN 'MEMBER_ID'
            THEN i.Inbound_Member_ID
        WHEN 'ISSUER_INDIV_IDENTIFIER'
            THEN i.Inbound_Issuer_Indiv_Identifier
        WHEN 'EXCHG_ASSIGNED_ENROLLEE_ID'
            THEN i.Inbound_Exchange_Assigned_Enrollee_ID
        WHEN 'MEMBER_ID+ISSUER_INDIV_IDENTIFIER'
            THEN CONCAT(
                'MEMBER_ID=', i.Inbound_Member_ID,
                '; ISSUER_INDIV_IDENTIFIER=', i.Inbound_Issuer_Indiv_Identifier
            )
        WHEN 'MEMBER_ID+EXCHG_ASSIGNED_ENROLLEE_ID'
            THEN CONCAT(
                'MEMBER_ID=', i.Inbound_Member_ID,
                '; EXCHG_ASSIGNED_ENROLLEE_ID=', i.Inbound_Exchange_Assigned_Enrollee_ID
            )
        WHEN 'ISSUER_INDIV_IDENTIFIER+EXCHG_ASSIGNED_ENROLLEE_ID'
            THEN CONCAT(
                'ISSUER_INDIV_IDENTIFIER=', i.Inbound_Issuer_Indiv_Identifier,
                '; EXCHG_ASSIGNED_ENROLLEE_ID=', i.Inbound_Exchange_Assigned_Enrollee_ID
            )
        WHEN 'ALL_THREE'
            THEN CONCAT(
                'MEMBER_ID=', i.Inbound_Member_ID,
                '; ISSUER_INDIV_IDENTIFIER=', i.Inbound_Issuer_Indiv_Identifier,
                '; EXCHG_ASSIGNED_ENROLLEE_ID=', i.Inbound_Exchange_Assigned_Enrollee_ID
            )
        ELSE NULL
    END AS Matched_Inbound_ID,
    h.Matched_Inbound_ID_Type,

    i.Inbound_Policy_ID,
    i.Inbound_Health_Coverage_Policy_No,
    CASE
        WHEN t.FFM_Policy_ID = i.Inbound_Policy_ID
         AND t.FFM_Policy_ID = i.Inbound_Health_Coverage_Policy_No THEN i.Inbound_Policy_ID
        WHEN t.FFM_Policy_ID = i.Inbound_Policy_ID THEN i.Inbound_Policy_ID
        WHEN t.FFM_Policy_ID = i.Inbound_Health_Coverage_Policy_No THEN i.Inbound_Health_Coverage_Policy_No
        ELSE COALESCE(i.Inbound_Policy_ID, i.Inbound_Health_Coverage_Policy_No)
    END AS Matched_Inbound_Policy_ID,
    CASE
        WHEN t.FFM_Policy_ID = i.Inbound_Policy_ID
         AND t.FFM_Policy_ID = i.Inbound_Health_Coverage_Policy_No THEN 'BOTH'
        WHEN t.FFM_Policy_ID = i.Inbound_Policy_ID THEN 'POLICY_ID'
        WHEN t.FFM_Policy_ID = i.Inbound_Health_Coverage_Policy_No THEN 'HEALTH_COVERAGE_POLICY_NO'
        ELSE 'NONE'
    END AS Policy_Match_Type,

    i.Inbound_Issuer,
    i.Inbound_Coverage_Year,
    i.Inbound_Status_Raw,
    i.Inbound_Status_Normalized,
    i.Inbound_Event_Date,
    i.benefit_effective_date AS Inbound_Benefit_Effective_Date,
    i.benefit_end_date AS Inbound_Benefit_End_Date,
    i.member_maint_effective_date,
    i.folder_year,
    i.folder_month,
    i.Inbound_Source_File,
    i.household_or_employee_case_id,
    i.relationship,

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


-- =============================================================================
-- Best inbound candidate per target pair (UNCHANGED ranking)
-- =============================================================================
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


-- =============================================================================
-- Master results (UNCHANGED Match_Level classification) then EXACT subset
-- =============================================================================
IF OBJECT_ID('tempdb..#834_master_results') IS NOT NULL DROP TABLE #834_master_results;

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
    t.FFM_Create_Date,
    t.FFM_Last_Update_Date,
    t.household_id,

    CASE WHEN b.FFM_Enrollee_ID IS NULL THEN 'NO' ELSE 'YES' END AS [834_Found],
    CASE
        WHEN b.FFM_Enrollee_ID IS NULL THEN 'NO_INBOUND_ENROLLEE_EVIDENCE'
        WHEN b.Policy_Match_Flag = 'YES' THEN 'EXACT_ENROLLEE_POLICY_MATCH'
        WHEN b.Issuer_Match_Flag = 'YES'
         AND b.Status_Match_Flag = 'YES'
         AND b.Date_Difference_Days IS NOT NULL
         AND b.Date_Difference_Days <= 7
            THEN 'SAME_TRANSACTION_DIFFERENT_POLICY'
        WHEN b.Issuer_Match_Flag = 'YES'
         AND b.Status_Match_Flag = 'YES'
            THEN 'SAME_LIFECYCLE_DIFFERENT_POLICY'
        WHEN b.Issuer_Match_Flag = 'NO'
         AND b.Status_Match_Flag = 'YES'
            THEN 'CROSS_ISSUER_TRANSITION'
        ELSE 'ENROLLEE_FOUND_DIFFERENT_LIFECYCLE'
    END AS [834_Match_Level],

    b.Matched_Inbound_ID,
    b.Matched_Inbound_ID_Type,
    b.Inbound_Member_ID,
    b.Inbound_Issuer_Indiv_Identifier,
    b.Inbound_Exchange_Assigned_Enrollee_ID,
    b.Inbound_Policy_ID,
    b.Inbound_Health_Coverage_Policy_No,
    b.Matched_Inbound_Policy_ID,
    COALESCE(b.Policy_Match_Type, 'NONE') AS Policy_Match_Type,
    b.Inbound_Issuer,
    b.Inbound_Coverage_Year,
    b.Inbound_Status_Raw,
    b.Inbound_Status_Normalized,
    b.Inbound_Event_Date,
    b.Inbound_Benefit_Effective_Date,
    b.Inbound_Benefit_End_Date,
    b.Date_Difference_Days,
    b.Inbound_Source_File,
    b.member_maint_effective_date,
    b.folder_year,
    b.folder_month,
    b.inbound_row_id AS Selected_Inbound_Row_ID,
    COALESCE(b.Policy_Match_Flag, 'NO') AS Policy_Match_Flag,
    COALESCE(b.Issuer_Match_Flag, 'NO') AS Issuer_Match_Flag,
    COALESCE(b.Status_Match_Flag, 'NO') AS Status_Match_Flag
INTO #834_master_results
FROM #target_population AS t
LEFT JOIN #best AS b
    ON t.FFM_Coverage_Year = b.FFM_Coverage_Year
   AND t.FFM_Policy_ID = b.FFM_Policy_ID
   AND t.FFM_Enrollee_ID = b.FFM_Enrollee_ID;

CREATE UNIQUE CLUSTERED INDEX CX_master
    ON #834_master_results (FFM_Coverage_Year, FFM_Policy_ID, FFM_Enrollee_ID);
CREATE NONCLUSTERED INDEX IX_master_level
    ON #834_master_results ([834_Match_Level]);

IF OBJECT_ID('tempdb..#exact') IS NOT NULL DROP TABLE #exact;

SELECT *
INTO #exact
FROM #834_master_results
WHERE [834_Match_Level] = 'EXACT_ENROLLEE_POLICY_MATCH';

CREATE UNIQUE CLUSTERED INDEX CX_exact
    ON #exact (FFM_Coverage_Year, FFM_Policy_ID, FFM_Enrollee_ID);

DECLARE @exact_count BIGINT = (SELECT COUNT(*) FROM #exact);
DECLARE @exact_distinct_pairs BIGINT = (
    SELECT COUNT(*)
    FROM (SELECT DISTINCT FFM_Coverage_Year, FFM_Policy_ID, FFM_Enrollee_ID FROM #exact) AS d
);

IF @enforce_expected_count = 1 AND @exact_count <> @expected_exact_matches
BEGIN
    RAISERROR(
        'EXACT MATCH BASELINE DRIFT: got %I64d; expected %I64d. Continuing with FLAG — review Result Set 1.',
        10, 1, @exact_count, @expected_exact_matches
    );
END;


-- =============================================================================
-- PHASE 3 — ALL exact Policy+Enrollee inbound history (not just selected row)
-- =============================================================================
IF OBJECT_ID('tempdb..#exact_history') IS NOT NULL DROP TABLE #exact_history;

SELECT
    e.FFM_Coverage_Year,
    e.FFM_Policy_ID,
    e.FFM_Enrollee_ID,
    e.FFM_Issuer,
    e.FFM_Enrollment_Status,
    e.FFM_Enrollee_Status,
    e.FFM_Status_Norm,
    i.inbound_row_id,
    i.Inbound_Issuer,
    i.Inbound_Coverage_Year,
    i.Inbound_Status_Raw,
    i.Inbound_Status_Normalized,
    i.Inbound_Member_ID,
    i.Inbound_Issuer_Indiv_Identifier,
    i.Inbound_Exchange_Assigned_Enrollee_ID,
    i.Inbound_Policy_ID,
    i.Inbound_Health_Coverage_Policy_No,
    i.benefit_effective_date AS Inbound_Benefit_Effective_Date,
    i.benefit_end_date AS Inbound_Benefit_End_Date,
    i.Inbound_Event_Date,
    i.Inbound_Source_File,
    i.member_maint_effective_date
INTO #exact_history
FROM #exact AS e
INNER JOIN #inbound AS i
    ON (
           i.Inbound_Member_ID = e.FFM_Enrollee_ID
        OR i.Inbound_Issuer_Indiv_Identifier = e.FFM_Enrollee_ID
        OR i.Inbound_Exchange_Assigned_Enrollee_ID = e.FFM_Enrollee_ID
       )
   AND (
           i.Inbound_Policy_ID = e.FFM_Policy_ID
        OR i.Inbound_Health_Coverage_Policy_No = e.FFM_Policy_ID
       );

CREATE CLUSTERED INDEX CX_exact_hist
    ON #exact_history (FFM_Coverage_Year, FFM_Policy_ID, FFM_Enrollee_ID, inbound_row_id);
CREATE NONCLUSTERED INDEX IX_exact_hist_year
    ON #exact_history (Inbound_Coverage_Year, Inbound_Status_Normalized);


-- History rollup per FFM exact pair
IF OBJECT_ID('tempdb..#exact_hist_agg') IS NOT NULL DROP TABLE #exact_hist_agg;

SELECT
    h.FFM_Coverage_Year,
    h.FFM_Policy_ID,
    h.FFM_Enrollee_ID,
    COUNT(*) AS Exact_Inbound_Physical_Row_Count,
    MAX(CASE WHEN h.Inbound_Coverage_Year = 2025
              AND h.Inbound_Status_Normalized = 'CONFIRM' THEN 1 ELSE 0 END) AS Has_2025_CONFIRM,
    MAX(CASE WHEN h.Inbound_Coverage_Year = 2025
              AND h.Inbound_Status_Normalized = 'CANCEL' THEN 1 ELSE 0 END) AS Has_2025_CANCEL,
    MAX(CASE WHEN h.Inbound_Coverage_Year = 2025
              AND h.Inbound_Status_Normalized = 'TERM' THEN 1 ELSE 0 END) AS Has_2025_TERM,
    MAX(CASE WHEN h.Inbound_Coverage_Year = 2026
              AND h.Inbound_Status_Normalized = 'CONFIRM' THEN 1 ELSE 0 END) AS Has_2026_CONFIRM,
    MAX(CASE WHEN h.Inbound_Coverage_Year = 2026
              AND h.Inbound_Status_Normalized = 'CANCEL' THEN 1 ELSE 0 END) AS Has_2026_CANCEL,
    MAX(CASE WHEN h.Inbound_Coverage_Year = 2026
              AND h.Inbound_Status_Normalized = 'TERM' THEN 1 ELSE 0 END) AS Has_2026_TERM,
    MAX(CASE WHEN h.Inbound_Coverage_Year IS NOT NULL
              AND h.Inbound_Coverage_Year NOT IN (2025, 2026) THEN 1 ELSE 0 END) AS Has_Other_Year_Evidence,
    MAX(CASE WHEN h.Inbound_Coverage_Year = 2025 THEN 1 ELSE 0 END) AS Has_2025_Exact_Evidence,
    MAX(CASE WHEN h.Inbound_Coverage_Year = 2026 THEN 1 ELSE 0 END) AS Has_2026_Exact_Evidence,
    MAX(CASE WHEN h.Inbound_Coverage_Year IS NULL THEN 1 ELSE 0 END) AS Has_Null_Year_Exact_Evidence,
    MIN(h.Inbound_Benefit_Effective_Date) AS Earliest_Inbound_Effective_Date,
    MAX(h.Inbound_Benefit_Effective_Date) AS Latest_Inbound_Effective_Date,
    MIN(h.Inbound_Event_Date) AS Earliest_Inbound_Event_Date,
    MAX(h.Inbound_Event_Date) AS Latest_Inbound_Event_Date
INTO #exact_hist_agg
FROM #exact_history AS h
GROUP BY
    h.FFM_Coverage_Year,
    h.FFM_Policy_ID,
    h.FFM_Enrollee_ID;

CREATE UNIQUE CLUSTERED INDEX CX_exact_hist_agg
    ON #exact_hist_agg (FFM_Coverage_Year, FFM_Policy_ID, FFM_Enrollee_ID);

-- Distinct year / status lists (preserve physical evidence; no COALESCE hiding)
IF OBJECT_ID('tempdb..#exact_year_list') IS NOT NULL DROP TABLE #exact_year_list;
IF OBJECT_ID('tempdb..#exact_status_list') IS NOT NULL DROP TABLE #exact_status_list;
IF OBJECT_ID('tempdb..#exact_earliest_file') IS NOT NULL DROP TABLE #exact_earliest_file;
IF OBJECT_ID('tempdb..#exact_latest_file') IS NOT NULL DROP TABLE #exact_latest_file;

SELECT
    FFM_Coverage_Year,
    FFM_Policy_ID,
    FFM_Enrollee_ID,
    STRING_AGG(year_token, ',') WITHIN GROUP (ORDER BY sort_key) AS All_Inbound_Coverage_Years_Found
INTO #exact_year_list
FROM (
    SELECT DISTINCT
        FFM_Coverage_Year,
        FFM_Policy_ID,
        FFM_Enrollee_ID,
        CASE
            WHEN Inbound_Coverage_Year IS NULL THEN 'NULL'
            ELSE CAST(Inbound_Coverage_Year AS VARCHAR(10))
        END AS year_token,
        CASE WHEN Inbound_Coverage_Year IS NULL THEN 9999 ELSE Inbound_Coverage_Year END AS sort_key
    FROM #exact_history
) AS y
GROUP BY FFM_Coverage_Year, FFM_Policy_ID, FFM_Enrollee_ID;

SELECT
    FFM_Coverage_Year,
    FFM_Policy_ID,
    FFM_Enrollee_ID,
    STRING_AGG(status_token, ',') WITHIN GROUP (ORDER BY status_token) AS All_Inbound_Statuses_Found
INTO #exact_status_list
FROM (
    SELECT DISTINCT
        FFM_Coverage_Year,
        FFM_Policy_ID,
        FFM_Enrollee_ID,
        COALESCE(Inbound_Status_Raw, 'NULL') AS status_token
    FROM #exact_history
) AS s
GROUP BY FFM_Coverage_Year, FFM_Policy_ID, FFM_Enrollee_ID;

;WITH ranked_earliest AS (
    SELECT
        FFM_Coverage_Year,
        FFM_Policy_ID,
        FFM_Enrollee_ID,
        Inbound_Source_File,
        ROW_NUMBER() OVER (
            PARTITION BY FFM_Coverage_Year, FFM_Policy_ID, FFM_Enrollee_ID
            ORDER BY
                CASE WHEN Inbound_Benefit_Effective_Date IS NULL THEN 1 ELSE 0 END,
                Inbound_Benefit_Effective_Date ASC,
                CASE WHEN Inbound_Event_Date IS NULL THEN 1 ELSE 0 END,
                Inbound_Event_Date ASC,
                inbound_row_id ASC
        ) AS rn
    FROM #exact_history
),
ranked_latest AS (
    SELECT
        FFM_Coverage_Year,
        FFM_Policy_ID,
        FFM_Enrollee_ID,
        Inbound_Source_File,
        ROW_NUMBER() OVER (
            PARTITION BY FFM_Coverage_Year, FFM_Policy_ID, FFM_Enrollee_ID
            ORDER BY
                CASE WHEN Inbound_Benefit_Effective_Date IS NULL THEN 1 ELSE 0 END,
                Inbound_Benefit_Effective_Date DESC,
                CASE WHEN Inbound_Event_Date IS NULL THEN 1 ELSE 0 END,
                Inbound_Event_Date DESC,
                inbound_row_id DESC
        ) AS rn
    FROM #exact_history
)
SELECT FFM_Coverage_Year, FFM_Policy_ID, FFM_Enrollee_ID, Inbound_Source_File AS Earliest_Inbound_Source_File
INTO #exact_earliest_file
FROM ranked_earliest
WHERE rn = 1;

SELECT FFM_Coverage_Year, FFM_Policy_ID, FFM_Enrollee_ID, Inbound_Source_File AS Latest_Inbound_Source_File
INTO #exact_latest_file
FROM ranked_latest
WHERE rn = 1;


-- =============================================================================
-- PHASE 4 — 2025-only continuation search in 2026 inbound (section 7)
-- =============================================================================
IF OBJECT_ID('tempdb..#y2025_only') IS NOT NULL DROP TABLE #y2025_only;

SELECT
    e.*,
    a.Has_2025_CONFIRM,
    a.Has_2025_CANCEL,
    a.Has_2025_TERM,
    a.Has_2026_CONFIRM,
    a.Has_2026_CANCEL,
    a.Has_2026_TERM,
    a.Has_Other_Year_Evidence,
    a.Has_2025_Exact_Evidence,
    a.Has_2026_Exact_Evidence
INTO #y2025_only
FROM #exact AS e
INNER JOIN #exact_hist_agg AS a
    ON a.FFM_Coverage_Year = e.FFM_Coverage_Year
   AND a.FFM_Policy_ID = e.FFM_Policy_ID
   AND a.FFM_Enrollee_ID = e.FFM_Enrollee_ID
WHERE a.Has_2025_Exact_Evidence = 1
  AND a.Has_2026_Exact_Evidence = 0;

CREATE UNIQUE CLUSTERED INDEX CX_y2025_only
    ON #y2025_only (FFM_Coverage_Year, FFM_Policy_ID, FFM_Enrollee_ID);

-- 2026 inbound enrollee hits (independent ID paths)
IF OBJECT_ID('tempdb..#y2026_enrollee_hits') IS NOT NULL DROP TABLE #y2026_enrollee_hits;

;WITH hit_raw AS (
    SELECT y.FFM_Coverage_Year, y.FFM_Policy_ID, y.FFM_Enrollee_ID, i.inbound_row_id
    FROM #y2025_only AS y
    INNER JOIN #inbound AS i
        ON i.Inbound_Coverage_Year = 2026
       AND i.Inbound_Member_ID = y.FFM_Enrollee_ID

    UNION

    SELECT y.FFM_Coverage_Year, y.FFM_Policy_ID, y.FFM_Enrollee_ID, i.inbound_row_id
    FROM #y2025_only AS y
    INNER JOIN #inbound AS i
        ON i.Inbound_Coverage_Year = 2026
       AND i.Inbound_Issuer_Indiv_Identifier = y.FFM_Enrollee_ID

    UNION

    SELECT y.FFM_Coverage_Year, y.FFM_Policy_ID, y.FFM_Enrollee_ID, i.inbound_row_id
    FROM #y2025_only AS y
    INNER JOIN #inbound AS i
        ON i.Inbound_Coverage_Year = 2026
       AND i.Inbound_Exchange_Assigned_Enrollee_ID = y.FFM_Enrollee_ID
)
SELECT *
INTO #y2026_enrollee_hits
FROM hit_raw;

CREATE CLUSTERED INDEX CX_y2026_eel
    ON #y2026_enrollee_hits (FFM_Enrollee_ID, FFM_Policy_ID, inbound_row_id);

-- 2026 inbound policy hits (independent policy paths)
IF OBJECT_ID('tempdb..#y2026_policy_hits') IS NOT NULL DROP TABLE #y2026_policy_hits;

;WITH hit_raw AS (
    SELECT y.FFM_Coverage_Year, y.FFM_Policy_ID, y.FFM_Enrollee_ID, i.inbound_row_id
    FROM #y2025_only AS y
    INNER JOIN #inbound AS i
        ON i.Inbound_Coverage_Year = 2026
       AND i.Inbound_Policy_ID = y.FFM_Policy_ID

    UNION

    SELECT y.FFM_Coverage_Year, y.FFM_Policy_ID, y.FFM_Enrollee_ID, i.inbound_row_id
    FROM #y2025_only AS y
    INNER JOIN #inbound AS i
        ON i.Inbound_Coverage_Year = 2026
       AND i.Inbound_Health_Coverage_Policy_No = y.FFM_Policy_ID
)
SELECT *
INTO #y2026_policy_hits
FROM hit_raw;

CREATE CLUSTERED INDEX CX_y2026_pol
    ON #y2026_policy_hits (FFM_Policy_ID, FFM_Enrollee_ID, inbound_row_id);

IF OBJECT_ID('tempdb..#y2025_continuation') IS NOT NULL DROP TABLE #y2025_continuation;

SELECT
    y.FFM_Coverage_Year,
    y.FFM_Policy_ID,
    y.FFM_Enrollee_ID,
    CASE WHEN eel.inbound_row_id IS NOT NULL THEN 1 ELSE 0 END AS Has_2026_Enrollee_Hit,
    CASE WHEN pol.inbound_row_id IS NOT NULL THEN 1 ELSE 0 END AS Has_2026_Policy_Hit,
    CASE
        WHEN eel.inbound_row_id IS NOT NULL
         AND (
                i.Inbound_Policy_ID = y.FFM_Policy_ID
             OR i.Inbound_Health_Coverage_Policy_No = y.FFM_Policy_ID
         )
            THEN 1 ELSE 0
    END AS Has_2026_Same_Enrollee_Same_Policy,
    CASE
        WHEN eel.inbound_row_id IS NOT NULL
         AND ISNULL(i.Inbound_Policy_ID, '') <> y.FFM_Policy_ID
         AND ISNULL(i.Inbound_Health_Coverage_Policy_No, '') <> y.FFM_Policy_ID
         AND i.Inbound_Issuer = y.FFM_Issuer
            THEN 1 ELSE 0
    END AS Has_2026_Same_Enrollee_Diff_Policy_Same_Issuer,
    CASE
        WHEN eel.inbound_row_id IS NOT NULL
         AND i.Inbound_Issuer IS NOT NULL
         AND i.Inbound_Issuer <> y.FFM_Issuer
            THEN 1 ELSE 0
    END AS Has_2026_Same_Enrollee_Diff_Issuer,
    MAX(CASE WHEN eel.inbound_row_id IS NOT NULL THEN 1 ELSE 0 END)
        OVER (PARTITION BY y.FFM_Coverage_Year, y.FFM_Policy_ID, y.FFM_Enrollee_ID) AS _any_eel,
    MAX(CASE WHEN pol.inbound_row_id IS NOT NULL THEN 1 ELSE 0 END)
        OVER (PARTITION BY y.FFM_Coverage_Year, y.FFM_Policy_ID, y.FFM_Enrollee_ID) AS _any_pol,
    MAX(CASE
            WHEN eel.inbound_row_id IS NOT NULL
             AND (
                    i.Inbound_Policy_ID = y.FFM_Policy_ID
                 OR i.Inbound_Health_Coverage_Policy_No = y.FFM_Policy_ID
             ) THEN 1 ELSE 0
        END) OVER (PARTITION BY y.FFM_Coverage_Year, y.FFM_Policy_ID, y.FFM_Enrollee_ID) AS _any_same_pair,
    MAX(CASE
            WHEN eel.inbound_row_id IS NOT NULL
             AND ISNULL(i.Inbound_Policy_ID, '') <> y.FFM_Policy_ID
             AND ISNULL(i.Inbound_Health_Coverage_Policy_No, '') <> y.FFM_Policy_ID
             AND i.Inbound_Issuer = y.FFM_Issuer THEN 1 ELSE 0
        END) OVER (PARTITION BY y.FFM_Coverage_Year, y.FFM_Policy_ID, y.FFM_Enrollee_ID) AS _any_diff_pol,
    MAX(CASE
            WHEN eel.inbound_row_id IS NOT NULL
             AND i.Inbound_Issuer IS NOT NULL
             AND i.Inbound_Issuer <> y.FFM_Issuer THEN 1 ELSE 0
        END) OVER (PARTITION BY y.FFM_Coverage_Year, y.FFM_Policy_ID, y.FFM_Enrollee_ID) AS _any_diff_iss
INTO #y2025_continuation_raw
FROM #y2025_only AS y
LEFT JOIN #y2026_enrollee_hits AS eel
    ON eel.FFM_Coverage_Year = y.FFM_Coverage_Year
   AND eel.FFM_Policy_ID = y.FFM_Policy_ID
   AND eel.FFM_Enrollee_ID = y.FFM_Enrollee_ID
LEFT JOIN #inbound AS i
    ON i.inbound_row_id = eel.inbound_row_id
LEFT JOIN #y2026_policy_hits AS pol
    ON pol.FFM_Coverage_Year = y.FFM_Coverage_Year
   AND pol.FFM_Policy_ID = y.FFM_Policy_ID
   AND pol.FFM_Enrollee_ID = y.FFM_Enrollee_ID;

-- Collapse to one row per pair with prioritized continuation label
SELECT
    FFM_Coverage_Year,
    FFM_Policy_ID,
    FFM_Enrollee_ID,
    MAX(_any_eel) AS Has_2026_Enrollee_Hit,
    MAX(_any_pol) AS Has_2026_Policy_Hit,
    MAX(_any_same_pair) AS Has_2026_Same_Enrollee_Same_Policy,
    MAX(_any_diff_pol) AS Has_2026_Same_Enrollee_Diff_Policy_Same_Issuer,
    MAX(_any_diff_iss) AS Has_2026_Same_Enrollee_Diff_Issuer,
    CASE
        WHEN MAX(_any_same_pair) = 1 THEN 'same enrollee + same policy'
        WHEN MAX(_any_diff_pol) = 1 THEN 'same enrollee + different policy'
        WHEN MAX(_any_diff_iss) = 1 THEN 'same enrollee + different issuer'
        WHEN MAX(_any_pol) = 1 AND MAX(_any_eel) = 0 THEN 'policy only'
        WHEN MAX(_any_eel) = 1 THEN 'enrollee only'
        ELSE 'no 2026 inbound evidence'
    END AS Continuation_2026_Finding
INTO #y2025_continuation
FROM #y2025_continuation_raw
GROUP BY FFM_Coverage_Year, FFM_Policy_ID, FFM_Enrollee_ID;

CREATE UNIQUE CLUSTERED INDEX CX_y2025_cont
    ON #y2025_continuation (FFM_Coverage_Year, FFM_Policy_ID, FFM_Enrollee_ID);

IF OBJECT_ID('tempdb..#y2025_continuation_raw') IS NOT NULL DROP TABLE #y2025_continuation_raw;


-- =============================================================================
-- PHASE 5 — Full record-level diagnostic assembly
-- =============================================================================
IF OBJECT_ID('tempdb..#exact_diag') IS NOT NULL DROP TABLE #exact_diag;

SELECT
    e.FFM_Issuer,
    e.FFM_Coverage_Year,
    e.FFM_Policy_ID,
    e.FFM_Enrollee_ID,
    e.FFM_Enrollment_Status,
    e.FFM_Enrollee_Status,
    e.FFM_Status_Norm,
    e.FFM_Benefit_Effective_Date,
    e.FFM_Benefit_End_Date,
    e.FFM_Event_Date,
    e.FFM_Create_Date,
    e.FFM_Last_Update_Date,
    e.household_id,

    e.Inbound_Issuer AS Selected_Inbound_Issuer,
    e.Inbound_Coverage_Year AS Selected_Inbound_Coverage_Year,
    e.Inbound_Policy_ID AS Selected_Inbound_Policy_ID,
    e.Inbound_Health_Coverage_Policy_No AS Selected_Inbound_Health_Coverage_Policy_No,
    e.Matched_Inbound_Policy_ID AS Selected_Matched_Inbound_Policy_ID,
    e.Policy_Match_Type AS Selected_Policy_Match_Type,
    e.Inbound_Member_ID AS Selected_Inbound_Member_ID,
    e.Inbound_Issuer_Indiv_Identifier AS Selected_Inbound_Issuer_Indiv_Identifier,
    e.Inbound_Exchange_Assigned_Enrollee_ID AS Selected_Inbound_Exchange_Assigned_Enrollee_ID,
    e.Matched_Inbound_ID AS Selected_Matched_Inbound_ID,
    e.Matched_Inbound_ID_Type AS Selected_Matched_Inbound_ID_Type,
    e.Inbound_Status_Raw AS Selected_Inbound_Status_Raw,
    e.Inbound_Status_Normalized AS Selected_Inbound_Status_Normalized,
    e.Status_Match_Flag AS Selected_Status_Match_Flag,
    e.Inbound_Benefit_Effective_Date AS Selected_Inbound_Benefit_Effective_Date,
    e.Inbound_Benefit_End_Date AS Selected_Inbound_Benefit_End_Date,
    e.Inbound_Event_Date AS Selected_Inbound_Event_Date,
    e.Inbound_Source_File AS Selected_Inbound_Source_File,
    e.Selected_Inbound_Row_ID,

    COALESCE(a.Exact_Inbound_Physical_Row_Count, 0) AS Exact_Inbound_Physical_Row_Count,
    yl.All_Inbound_Coverage_Years_Found,
    sl.All_Inbound_Statuses_Found,
    COALESCE(a.Has_2025_CONFIRM, 0) AS Has_2025_CONFIRM,
    COALESCE(a.Has_2025_CANCEL, 0) AS Has_2025_CANCEL,
    COALESCE(a.Has_2025_TERM, 0) AS Has_2025_TERM,
    COALESCE(a.Has_2026_CONFIRM, 0) AS Has_2026_CONFIRM,
    COALESCE(a.Has_2026_CANCEL, 0) AS Has_2026_CANCEL,
    COALESCE(a.Has_2026_TERM, 0) AS Has_2026_TERM,
    COALESCE(a.Has_Other_Year_Evidence, 0) AS Has_Other_Year_Evidence,
    COALESCE(a.Has_2025_Exact_Evidence, 0) AS Has_2025_Exact_Evidence,
    COALESCE(a.Has_2026_Exact_Evidence, 0) AS Has_2026_Exact_Evidence,
    COALESCE(a.Has_Null_Year_Exact_Evidence, 0) AS Has_Null_Year_Exact_Evidence,
    a.Earliest_Inbound_Effective_Date,
    a.Latest_Inbound_Effective_Date,
    a.Earliest_Inbound_Event_Date,
    a.Latest_Inbound_Event_Date,
    ef.Earliest_Inbound_Source_File,
    lf.Latest_Inbound_Source_File,

    /* Year-transition diagnostic populations (A–E) — evidence labels only */
    CASE
        WHEN COALESCE(a.Has_2025_Exact_Evidence, 0) = 1
         AND COALESCE(a.Has_2026_Exact_Evidence, 0) = 0
            THEN 'A_2025_EXACT_NO_2026_EXACT'
        WHEN COALESCE(a.Has_2025_CONFIRM, 0) = 1
         AND COALESCE(a.Has_2026_CONFIRM, 0) = 0
            THEN 'B_2025_CONFIRM_NO_2026_CONFIRM'
        WHEN COALESCE(a.Has_2025_Exact_Evidence, 0) = 1
         AND COALESCE(a.Has_2026_Exact_Evidence, 0) = 1
         AND (
                COALESCE(a.Has_2025_CONFIRM, 0) <> COALESCE(a.Has_2026_CONFIRM, 0)
             OR COALESCE(a.Has_2025_CANCEL, 0) <> COALESCE(a.Has_2026_CANCEL, 0)
             OR COALESCE(a.Has_2025_TERM, 0) <> COALESCE(a.Has_2026_TERM, 0)
             OR e.Inbound_Status_Normalized <>
                CASE
                    WHEN e.FFM_Status_Norm = 'CONFIRM' THEN 'CONFIRM'
                    ELSE e.Inbound_Status_Normalized
                END
         )
            THEN 'C_BOTH_YEARS_LIFECYCLE_CHANGED'
        WHEN UPPER(LTRIM(RTRIM(e.FFM_Enrollment_Status))) = 'ENROLLED'
         AND e.Inbound_Status_Normalized IN ('CANCEL', 'TERM')
            THEN 'D_FFM_ENROLLED_LATEST_SELECTED_CANCEL_OR_TERM'
        WHEN UPPER(LTRIM(RTRIM(e.FFM_Enrollment_Status))) = 'PENDING'
         AND e.Inbound_Status_Normalized IN ('CONFIRM', 'CANCEL', 'TERM')
            THEN 'E_FFM_PENDING_WITH_INBOUND_CONFIRM_CANCEL_OR_TERM'
        ELSE 'NO_YEAR_TRANSITION_FLAG'
    END AS Year_Transition_Diagnostic,

    /* Also expose independent A–E boolean flags (categories can overlap) */
    CASE WHEN COALESCE(a.Has_2025_Exact_Evidence, 0) = 1
          AND COALESCE(a.Has_2026_Exact_Evidence, 0) = 0 THEN 1 ELSE 0 END AS Flag_A_2025_Exact_No_2026_Exact,
    CASE WHEN COALESCE(a.Has_2025_CONFIRM, 0) = 1
          AND COALESCE(a.Has_2026_CONFIRM, 0) = 0 THEN 1 ELSE 0 END AS Flag_B_2025_Confirm_No_2026_Confirm,
    CASE WHEN COALESCE(a.Has_2025_Exact_Evidence, 0) = 1
          AND COALESCE(a.Has_2026_Exact_Evidence, 0) = 1
          AND (
                 COALESCE(a.Has_2025_CONFIRM, 0) <> COALESCE(a.Has_2026_CONFIRM, 0)
              OR COALESCE(a.Has_2025_CANCEL, 0) <> COALESCE(a.Has_2026_CANCEL, 0)
              OR COALESCE(a.Has_2025_TERM, 0) <> COALESCE(a.Has_2026_TERM, 0)
          ) THEN 1 ELSE 0 END AS Flag_C_Both_Years_Lifecycle_Changed,
    CASE WHEN UPPER(LTRIM(RTRIM(e.FFM_Enrollment_Status))) = 'ENROLLED'
          AND e.Inbound_Status_Normalized IN ('CANCEL', 'TERM') THEN 1 ELSE 0 END
        AS Flag_D_FFM_Enrolled_Selected_Cancel_Or_Term,
    CASE WHEN UPPER(LTRIM(RTRIM(e.FFM_Enrollment_Status))) = 'PENDING'
          AND e.Inbound_Status_Normalized IN ('CONFIRM', 'CANCEL', 'TERM') THEN 1 ELSE 0 END
        AS Flag_E_FFM_Pending_With_Inbound_Lifecycle,

    /* Lifecycle diagnostic (selected + history; does NOT change Match_Level) */
    CASE
        WHEN UPPER(LTRIM(RTRIM(e.FFM_Enrollment_Status))) = 'PENDING'
         AND e.Inbound_Status_Normalized = 'CONFIRM'
            THEN 'FFM_PENDING_WITH_INBOUND_CONFIRM'
        WHEN UPPER(LTRIM(RTRIM(e.FFM_Enrollment_Status))) = 'ENROLLED'
         AND e.Inbound_Status_Normalized = 'CANCEL'
            THEN 'FFM_ENROLLED_WITH_INBOUND_CANCEL'
        WHEN UPPER(LTRIM(RTRIM(e.FFM_Enrollment_Status))) = 'ENROLLED'
         AND e.Inbound_Status_Normalized = 'TERM'
            THEN 'FFM_ENROLLED_WITH_INBOUND_TERM'
        WHEN COALESCE(a.Has_2025_Exact_Evidence, 0) = 1
         AND COALESCE(a.Has_2026_Exact_Evidence, 0) = 0
            THEN '2025_ONLY_EXACT_INBOUND_EVIDENCE'
        WHEN COALESCE(a.Has_2025_Exact_Evidence, 0) = 1
         AND COALESCE(a.Has_2026_Exact_Evidence, 0) = 1
            THEN '2025_AND_2026_EXACT_INBOUND_EVIDENCE'
        WHEN COALESCE(a.Has_Other_Year_Evidence, 0) = 1
         AND COALESCE(a.Has_2026_Exact_Evidence, 0) = 0
         AND COALESCE(a.Has_2025_Exact_Evidence, 0) = 0
            THEN 'OTHER_YEAR_ONLY_EXACT_INBOUND_EVIDENCE'
        WHEN e.Inbound_Coverage_Year = 2026
         AND e.Status_Match_Flag = 'YES'
            THEN '2026_CONFIRM_STATUS_ALIGNED'
        WHEN e.Inbound_Coverage_Year = 2026
         AND e.Status_Match_Flag = 'NO'
            THEN '2026_EXACT_ID_STATUS_DISAGREE'
        ELSE 'OTHER_STATUS_PATTERN'
    END AS Lifecycle_Diagnostic,

    cont.Continuation_2026_Finding,
    cont.Has_2026_Enrollee_Hit AS Cont_Has_2026_Enrollee_Hit,
    cont.Has_2026_Policy_Hit AS Cont_Has_2026_Policy_Hit,
    cont.Has_2026_Same_Enrollee_Same_Policy AS Cont_Has_2026_Same_Enrollee_Same_Policy,
    cont.Has_2026_Same_Enrollee_Diff_Policy_Same_Issuer AS Cont_Has_2026_Same_Enrollee_Diff_Policy,
    cont.Has_2026_Same_Enrollee_Diff_Issuer AS Cont_Has_2026_Same_Enrollee_Diff_Issuer,

    CASE
        WHEN e.Inbound_Coverage_Year = 2026 THEN 'FFM_2026_TO_INBOUND_2026'
        WHEN e.Inbound_Coverage_Year = 2025 THEN 'FFM_2026_TO_INBOUND_2025'
        WHEN e.Inbound_Coverage_Year IS NULL THEN 'INBOUND_COVERAGE_YEAR_NULL'
        ELSE 'FFM_2026_TO_OTHER_INBOUND_YEAR'
    END AS Selected_Inbound_Year_Bucket
INTO #exact_diag
FROM #exact AS e
LEFT JOIN #exact_hist_agg AS a
    ON a.FFM_Coverage_Year = e.FFM_Coverage_Year
   AND a.FFM_Policy_ID = e.FFM_Policy_ID
   AND a.FFM_Enrollee_ID = e.FFM_Enrollee_ID
LEFT JOIN #exact_year_list AS yl
    ON yl.FFM_Coverage_Year = e.FFM_Coverage_Year
   AND yl.FFM_Policy_ID = e.FFM_Policy_ID
   AND yl.FFM_Enrollee_ID = e.FFM_Enrollee_ID
LEFT JOIN #exact_status_list AS sl
    ON sl.FFM_Coverage_Year = e.FFM_Coverage_Year
   AND sl.FFM_Policy_ID = e.FFM_Policy_ID
   AND sl.FFM_Enrollee_ID = e.FFM_Enrollee_ID
LEFT JOIN #exact_earliest_file AS ef
    ON ef.FFM_Coverage_Year = e.FFM_Coverage_Year
   AND ef.FFM_Policy_ID = e.FFM_Policy_ID
   AND ef.FFM_Enrollee_ID = e.FFM_Enrollee_ID
LEFT JOIN #exact_latest_file AS lf
    ON lf.FFM_Coverage_Year = e.FFM_Coverage_Year
   AND lf.FFM_Policy_ID = e.FFM_Policy_ID
   AND lf.FFM_Enrollee_ID = e.FFM_Enrollee_ID
LEFT JOIN #y2025_continuation AS cont
    ON cont.FFM_Coverage_Year = e.FFM_Coverage_Year
   AND cont.FFM_Policy_ID = e.FFM_Policy_ID
   AND cont.FFM_Enrollee_ID = e.FFM_Enrollee_ID;

CREATE UNIQUE CLUSTERED INDEX CX_exact_diag
    ON #exact_diag (FFM_Coverage_Year, FFM_Policy_ID, FFM_Enrollee_ID);
CREATE NONCLUSTERED INDEX IX_exact_diag_life
    ON #exact_diag (Lifecycle_Diagnostic);
CREATE NONCLUSTERED INDEX IX_exact_diag_year
    ON #exact_diag (Selected_Inbound_Year_Bucket);


-- =============================================================================
-- RESULT SET 1 — Baseline validation (960,531 / 755,548)
-- =============================================================================
SELECT
    @target_count AS ffm_target_count,
    @expected_target_pairs AS expected_ffm_target_count,
    CASE WHEN @target_count = @expected_target_pairs THEN 'PASS' ELSE 'FAIL' END AS ffm_target_check,
    @exact_count AS existing_exact_match_count,
    @expected_exact_matches AS expected_exact_match_count,
    CASE WHEN @exact_count = @expected_exact_matches THEN 'PASS' ELSE 'FAIL_BASELINE_DRIFT' END AS exact_match_check,
    CAST(100.0 * @exact_count / NULLIF(@target_count, 0) AS DECIMAL(10, 4)) AS exact_match_percentage,
    @exact_distinct_pairs AS distinct_matched_policy_enrollee_pairs,
    CASE
        WHEN @target_count = @expected_target_pairs
         AND @exact_count = @expected_exact_matches
            THEN 'PASS'
        ELSE 'FLAG_REVIEW_REQUIRED'
    END AS control_status;


-- =============================================================================
-- RESULT SET 2 — Selected inbound coverage-year breakdown of exact matches
-- =============================================================================
SELECT
    FFM_Coverage_Year AS ffm_coverage_year,
    Selected_Inbound_Coverage_Year AS inbound_coverage_year,
    Selected_Inbound_Year_Bucket AS year_bucket,
    COUNT(*) AS exact_match_count,
    CAST(100.0 * COUNT(*) / NULLIF(@exact_count, 0) AS DECIMAL(10, 4)) AS pct_of_exact_755548
FROM #exact_diag
GROUP BY
    FFM_Coverage_Year,
    Selected_Inbound_Coverage_Year,
    Selected_Inbound_Year_Bucket
ORDER BY exact_match_count DESC;


-- =============================================================================
-- RESULT SET 3 — FFM status × inbound status × inbound year (selected row)
-- =============================================================================
SELECT
    FFM_Enrollment_Status,
    FFM_Enrollee_Status,
    Selected_Inbound_Status_Raw AS inbound_enrolleeStatus,
    Selected_Inbound_Coverage_Year AS inbound_coverage_year,
    COUNT(*) AS exact_match_count,
    CAST(100.0 * COUNT(*) / NULLIF(@exact_count, 0) AS DECIMAL(10, 4)) AS pct_of_exact_755548
FROM #exact_diag
GROUP BY
    FFM_Enrollment_Status,
    FFM_Enrollee_Status,
    Selected_Inbound_Status_Raw,
    Selected_Inbound_Coverage_Year
ORDER BY exact_match_count DESC;


-- =============================================================================
-- RESULT SET 4 — Lifecycle diagnostic summary
-- =============================================================================
SELECT
    Lifecycle_Diagnostic,
    COUNT(*) AS exact_match_count,
    CAST(100.0 * COUNT(*) / NULLIF(@exact_count, 0) AS DECIMAL(10, 4)) AS pct_of_exact_755548
FROM #exact_diag
GROUP BY Lifecycle_Diagnostic
ORDER BY exact_match_count DESC;


-- =============================================================================
-- RESULT SET 5 — History evidence: 2025-only vs 2026-only vs both vs other
-- =============================================================================
SELECT
    CASE
        WHEN Has_2025_Exact_Evidence = 1 AND Has_2026_Exact_Evidence = 1 THEN 'BOTH_2025_AND_2026_EXACT'
        WHEN Has_2025_Exact_Evidence = 1 AND Has_2026_Exact_Evidence = 0 THEN '2025_ONLY_EXACT'
        WHEN Has_2025_Exact_Evidence = 0 AND Has_2026_Exact_Evidence = 1 THEN '2026_ONLY_EXACT'
        WHEN Has_Other_Year_Evidence = 1 THEN 'OTHER_YEAR_EXACT_ONLY'
        WHEN Has_Null_Year_Exact_Evidence = 1 THEN 'NULL_YEAR_EXACT_ONLY'
        ELSE 'NO_HISTORY_AGG_UNEXPECTED'
    END AS history_year_pattern,
    COUNT(*) AS exact_match_count,
    CAST(100.0 * COUNT(*) / NULLIF(@exact_count, 0) AS DECIMAL(10, 4)) AS pct_of_exact_755548,
    SUM(Has_2025_CONFIRM) AS pairs_with_2025_confirm,
    SUM(Has_2025_CANCEL) AS pairs_with_2025_cancel,
    SUM(Has_2025_TERM) AS pairs_with_2025_term,
    SUM(Has_2026_CONFIRM) AS pairs_with_2026_confirm,
    SUM(Has_2026_CANCEL) AS pairs_with_2026_cancel,
    SUM(Has_2026_TERM) AS pairs_with_2026_term
FROM #exact_diag
GROUP BY
    CASE
        WHEN Has_2025_Exact_Evidence = 1 AND Has_2026_Exact_Evidence = 1 THEN 'BOTH_2025_AND_2026_EXACT'
        WHEN Has_2025_Exact_Evidence = 1 AND Has_2026_Exact_Evidence = 0 THEN '2025_ONLY_EXACT'
        WHEN Has_2025_Exact_Evidence = 0 AND Has_2026_Exact_Evidence = 1 THEN '2026_ONLY_EXACT'
        WHEN Has_Other_Year_Evidence = 1 THEN 'OTHER_YEAR_EXACT_ONLY'
        WHEN Has_Null_Year_Exact_Evidence = 1 THEN 'NULL_YEAR_EXACT_ONLY'
        ELSE 'NO_HISTORY_AGG_UNEXPECTED'
    END
ORDER BY exact_match_count DESC;


-- =============================================================================
-- RESULT SET 6 — Year-transition A–E counts (overlapping flags allowed)
-- =============================================================================
SELECT 'A_2025_EXACT_NO_2026_EXACT' AS year_transition_category,
       SUM(Flag_A_2025_Exact_No_2026_Exact) AS pair_count,
       CAST(100.0 * SUM(Flag_A_2025_Exact_No_2026_Exact) / NULLIF(@exact_count, 0) AS DECIMAL(10, 4)) AS pct_of_exact
FROM #exact_diag
UNION ALL
SELECT 'B_2025_CONFIRM_NO_2026_CONFIRM',
       SUM(Flag_B_2025_Confirm_No_2026_Confirm),
       CAST(100.0 * SUM(Flag_B_2025_Confirm_No_2026_Confirm) / NULLIF(@exact_count, 0) AS DECIMAL(10, 4))
FROM #exact_diag
UNION ALL
SELECT 'C_BOTH_YEARS_LIFECYCLE_CHANGED',
       SUM(Flag_C_Both_Years_Lifecycle_Changed),
       CAST(100.0 * SUM(Flag_C_Both_Years_Lifecycle_Changed) / NULLIF(@exact_count, 0) AS DECIMAL(10, 4))
FROM #exact_diag
UNION ALL
SELECT 'D_FFM_ENROLLED_SELECTED_CANCEL_OR_TERM',
       SUM(Flag_D_FFM_Enrolled_Selected_Cancel_Or_Term),
       CAST(100.0 * SUM(Flag_D_FFM_Enrolled_Selected_Cancel_Or_Term) / NULLIF(@exact_count, 0) AS DECIMAL(10, 4))
FROM #exact_diag
UNION ALL
SELECT 'E_FFM_PENDING_WITH_INBOUND_LIFECYCLE',
       SUM(Flag_E_FFM_Pending_With_Inbound_Lifecycle),
       CAST(100.0 * SUM(Flag_E_FFM_Pending_With_Inbound_Lifecycle) / NULLIF(@exact_count, 0) AS DECIMAL(10, 4))
FROM #exact_diag
ORDER BY year_transition_category;


-- =============================================================================
-- RESULT SET 7 — FFM Enrolled with selected inbound CANCEL/TERM
-- =============================================================================
SELECT
    FFM_Enrollment_Status,
    Selected_Inbound_Status_Raw,
    Selected_Inbound_Coverage_Year,
    COUNT(*) AS pair_count,
    CAST(100.0 * COUNT(*) / NULLIF(@exact_count, 0) AS DECIMAL(10, 4)) AS pct_of_exact
FROM #exact_diag
WHERE Flag_D_FFM_Enrolled_Selected_Cancel_Or_Term = 1
GROUP BY
    FFM_Enrollment_Status,
    Selected_Inbound_Status_Raw,
    Selected_Inbound_Coverage_Year
ORDER BY pair_count DESC;


-- =============================================================================
-- RESULT SET 8 — FFM Pending vs inbound lifecycle (selected)
-- =============================================================================
SELECT
    FFM_Enrollment_Status,
    Selected_Inbound_Status_Raw,
    Selected_Inbound_Coverage_Year,
    COUNT(*) AS pair_count,
    CAST(100.0 * COUNT(*) / NULLIF(@exact_count, 0) AS DECIMAL(10, 4)) AS pct_of_exact
FROM #exact_diag
WHERE Flag_E_FFM_Pending_With_Inbound_Lifecycle = 1
GROUP BY
    FFM_Enrollment_Status,
    Selected_Inbound_Status_Raw,
    Selected_Inbound_Coverage_Year
ORDER BY pair_count DESC;


-- =============================================================================
-- RESULT SET 9 — 2025-only exact pair: what 2026 inbound shows instead
-- =============================================================================
SELECT
    Continuation_2026_Finding,
    COUNT(*) AS pair_count,
    CAST(100.0 * COUNT(*) / NULLIF((SELECT COUNT(*) FROM #y2025_continuation), 0) AS DECIMAL(10, 4))
        AS pct_of_2025_only_exact
FROM #exact_diag
WHERE Flag_A_2025_Exact_No_2026_Exact = 1
GROUP BY Continuation_2026_Finding
ORDER BY pair_count DESC;


-- =============================================================================
-- RESULT SET 10 — Year-transition record detail (A–E populations)
-- =============================================================================
SELECT
    Year_Transition_Diagnostic,
    Flag_A_2025_Exact_No_2026_Exact,
    Flag_B_2025_Confirm_No_2026_Confirm,
    Flag_C_Both_Years_Lifecycle_Changed,
    Flag_D_FFM_Enrolled_Selected_Cancel_Or_Term,
    Flag_E_FFM_Pending_With_Inbound_Lifecycle,
    Lifecycle_Diagnostic,
    Continuation_2026_Finding,
    FFM_Issuer,
    FFM_Coverage_Year,
    FFM_Policy_ID,
    FFM_Enrollee_ID,
    FFM_Enrollment_Status,
    FFM_Enrollee_Status,
    Selected_Inbound_Issuer,
    Selected_Inbound_Coverage_Year,
    Selected_Inbound_Status_Raw,
    Selected_Inbound_Policy_ID,
    Selected_Inbound_Health_Coverage_Policy_No,
    Selected_Inbound_Member_ID,
    Selected_Inbound_Issuer_Indiv_Identifier,
    Selected_Inbound_Exchange_Assigned_Enrollee_ID,
    All_Inbound_Coverage_Years_Found,
    All_Inbound_Statuses_Found,
    Has_2025_CONFIRM,
    Has_2025_CANCEL,
    Has_2025_TERM,
    Has_2026_CONFIRM,
    Has_2026_CANCEL,
    Has_2026_TERM,
    Selected_Inbound_Source_File
FROM #exact_diag
WHERE Flag_A_2025_Exact_No_2026_Exact = 1
   OR Flag_B_2025_Confirm_No_2026_Confirm = 1
   OR Flag_C_Both_Years_Lifecycle_Changed = 1
   OR Flag_D_FFM_Enrolled_Selected_Cancel_Or_Term = 1
   OR Flag_E_FFM_Pending_With_Inbound_Lifecycle = 1
ORDER BY
    Year_Transition_Diagnostic,
    FFM_Issuer,
    FFM_Policy_ID,
    FFM_Enrollee_ID;


-- =============================================================================
-- RESULT SET 11 — Full record-level diagnostic (all exact matches)
-- =============================================================================
SELECT
    FFM_Issuer,
    FFM_Coverage_Year,
    FFM_Policy_ID,
    FFM_Enrollee_ID,
    FFM_Enrollment_Status,
    FFM_Enrollee_Status,
    FFM_Benefit_Effective_Date,
    FFM_Benefit_End_Date,
    Selected_Inbound_Issuer,
    Selected_Inbound_Coverage_Year,
    Selected_Inbound_Policy_ID,
    Selected_Inbound_Health_Coverage_Policy_No,
    Selected_Matched_Inbound_Policy_ID,
    Selected_Inbound_Member_ID,
    Selected_Inbound_Issuer_Indiv_Identifier,
    Selected_Inbound_Exchange_Assigned_Enrollee_ID,
    Selected_Matched_Inbound_ID,
    Selected_Matched_Inbound_ID_Type,
    Selected_Inbound_Status_Raw,
    Selected_Inbound_Status_Normalized,
    Selected_Status_Match_Flag,
    Selected_Inbound_Benefit_Effective_Date,
    Selected_Inbound_Benefit_End_Date,
    Selected_Inbound_Event_Date,
    Selected_Inbound_Source_File,
    Exact_Inbound_Physical_Row_Count,
    All_Inbound_Coverage_Years_Found,
    All_Inbound_Statuses_Found,
    Earliest_Inbound_Effective_Date,
    Latest_Inbound_Effective_Date,
    Earliest_Inbound_Source_File,
    Latest_Inbound_Source_File,
    Has_2025_CONFIRM,
    Has_2025_CANCEL,
    Has_2025_TERM,
    Has_2026_CONFIRM,
    Has_2026_CANCEL,
    Has_2026_TERM,
    Has_Other_Year_Evidence,
    Has_2025_Exact_Evidence,
    Has_2026_Exact_Evidence,
    Selected_Inbound_Year_Bucket,
    Year_Transition_Diagnostic,
    Flag_A_2025_Exact_No_2026_Exact,
    Flag_B_2025_Confirm_No_2026_Confirm,
    Flag_C_Both_Years_Lifecycle_Changed,
    Flag_D_FFM_Enrolled_Selected_Cancel_Or_Term,
    Flag_E_FFM_Pending_With_Inbound_Lifecycle,
    Lifecycle_Diagnostic,
    Continuation_2026_Finding
FROM #exact_diag
ORDER BY
    FFM_Issuer,
    FFM_Policy_ID,
    FFM_Enrollee_ID;
