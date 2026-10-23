-- =============================================================================
-- PHASE 2 — HISTORICAL LINEAGE OF VALIDATED 2026 NO_INBOUND POPULATION
-- =============================================================================
-- Purpose:
--   Starting strictly from the validated 109,776
--   NO_INBOUND_ENROLLEE_EVIDENCE Policy + Enrollee records, profile same-
--   enrollee enrollment history in Coverage Year 2025 and then 2024.
--
-- This script does NOT:
--   * assign AUTO_RENEWAL or AUTO_RENEWAL_CANDIDATE
--   * apply a "good standing" status rule
--   * use the business-reported 75,390 as a target
--   * use RCNI
--   * modify permanent tables
--
-- Validated starting chain:
--   dbo.Enrollments_TEST
--     -> #pop_2026 (five-field latest-row dedup)
--     -> #ffm_target (2026 Enrollment Status Enrolled/Pending)
--     -> #no_inbound_export (all-history, three independent identifier checks)
--
-- Grain:
--   2026 Coverage Year + Policy ID + Enrollee ID
-- =============================================================================

SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @coverage_year INT = 2026;
DECLARE @expected_complete_2026 BIGINT = 2263972;
DECLARE @expected_ffm_target BIGINT = 960531;
DECLARE @expected_no_inbound BIGINT = 109776;

DECLARE @t0 DATETIME2 = SYSDATETIME();
DECLARE @msg NVARCHAR(500);


-- =============================================================================
-- A1 — VALIDATED COMPLETE 2026 DEDUPLICATED POPULATION
-- Exact five-field ordering from:
--   enrollments_2026_complete_population_diagnostic.sql
-- Additional projected fields do not participate in membership or ordering.
-- =============================================================================
RAISERROR('PHASE2 A1: build complete deduplicated 2026 population', 10, 1) WITH NOWAIT;

IF OBJECT_ID('tempdb..#pop_2026') IS NOT NULL DROP TABLE #pop_2026;

SELECT
    e.coverage_year,
    e.hios_issuer_id,
    e.enrollment_id,
    e.enrollee_id,
    e.enrollment_status_description,
    e.enrollee_status_description,
    e.benefit_effective_date,
    e.benefit_end_date,
    e.enrollment_create_date,
    e.enrollment_last_update_date,
    e.enrollee_create_date,
    e.enrollee_last_update_date,
    e.person_type,
    e.relationship_type,
    e.net_premium_amt,
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
        e.enrollment_create_date,
        e.enrollment_last_update_date,
        e.enrollee_create_date,
        e.enrollee_last_update_date,
        e.person_type,
        e.relationship_type,
        e.net_premium_amt,
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
    INCLUDE (
        hios_issuer_id,
        enrollee_status_description,
        person_type,
        relationship_type,
        net_premium_amt
    );

DECLARE @complete_2026_count BIGINT = (
    SELECT COUNT_BIG(*) FROM #pop_2026
);

IF @complete_2026_count <> @expected_complete_2026
BEGIN
    RAISERROR(
        'STOP A1: COMPLETE_2026_DISTINCT_PAIRS=%I64d; expected %I64d.',
        16, 1,
        @complete_2026_count,
        @expected_complete_2026
    );
    RETURN;
END;


-- =============================================================================
-- A2 — VALIDATED 2026 ENROLLED/PENDING TARGET
-- Filter enrollment status only, after complete-population deduplication.
-- =============================================================================
RAISERROR('PHASE2 A2: build validated 2026 Enrolled/Pending target', 10, 1) WITH NOWAIT;

IF OBJECT_ID('tempdb..#ffm_target') IS NOT NULL DROP TABLE #ffm_target;

SELECT
    p.coverage_year AS FFM_Coverage_Year,
    CAST(p.hios_issuer_id AS VARCHAR(20)) AS FFM_Issuer,
    CAST(p.enrollment_id AS VARCHAR(100)) AS FFM_Policy_ID,
    CAST(p.enrollee_id AS VARCHAR(100)) AS FFM_Enrollee_ID,
    p.enrollment_status_description AS FFM_Enrollment_Status,
    p.enrollee_status_description AS FFM_Enrollee_Status,
    p.benefit_effective_date AS FFM_Benefit_Effective_Date,
    p.benefit_end_date AS FFM_Benefit_End_Date,
    p.enrollment_create_date AS FFM_Enrollment_Create_Date,
    p.enrollment_last_update_date AS FFM_Enrollment_Last_Update_Date,
    p.enrollee_create_date AS FFM_Enrollee_Create_Date,
    p.enrollee_last_update_date AS FFM_Enrollee_Last_Update_Date,
    p.person_type AS FFM_Person_Type,
    p.relationship_type AS FFM_Relationship_Type,
    CAST(p.net_premium_amt AS DECIMAL(38, 10)) AS FFM_Net_Premium_Amount
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

IF @ffm_target_count <> @expected_ffm_target
BEGIN
    RAISERROR(
        'STOP A2: FFM_TARGET_COUNT=%I64d; expected %I64d.',
        16, 1,
        @ffm_target_count,
        @expected_ffm_target
    );
    RETURN;
END;


-- =============================================================================
-- B1 — ALL-HISTORY INBOUND ENROLLEE IDENTIFIERS
-- No coverage-year or inbound-status restriction.
-- =============================================================================
RAISERROR('PHASE2 B1: stage all-history inbound enrollee identifiers', 10, 1) WITH NOWAIT;

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


-- =============================================================================
-- B2 — VALIDATED 109,776 NO_INBOUND POPULATION
-- =============================================================================
RAISERROR('PHASE2 B2: build validated NO_INBOUND population', 10, 1) WITH NOWAIT;

IF OBJECT_ID('tempdb..#no_inbound_export') IS NOT NULL
    DROP TABLE #no_inbound_export;

SELECT
    t.*,
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

CREATE NONCLUSTERED INDEX IX_no_inbound_enrollee
    ON #no_inbound_export (FFM_Enrollee_ID)
    INCLUDE (
        FFM_Coverage_Year,
        FFM_Policy_ID,
        FFM_Issuer
    );

DECLARE @no_inbound_count BIGINT = (
    SELECT COUNT_BIG(*) FROM #no_inbound_export
);

IF @no_inbound_count <> @expected_no_inbound
BEGIN
    RAISERROR(
        'STOP B2: NO_INBOUND_COUNT=%I64d; expected %I64d.',
        16, 1,
        @no_inbound_count,
        @expected_no_inbound
    );
    RETURN;
END;


-- =============================================================================
-- C1 — DEDUPLICATED 2025/2024 ENROLLMENT HISTORY
-- One row per historical coverage year + Policy ID + Enrollee ID.
-- Uses the same five-field latest-row ordering as the validated 2026 population.
-- No historical status filter is applied.
-- =============================================================================
RAISERROR('PHASE2 C1: build deduplicated 2025/2024 enrollment history', 10, 1) WITH NOWAIT;

IF OBJECT_ID('tempdb..#prior_history') IS NOT NULL DROP TABLE #prior_history;

SELECT
    e.coverage_year AS Historical_Coverage_Year,
    CAST(e.hios_issuer_id AS VARCHAR(20)) AS Historical_Issuer,
    CAST(e.enrollment_id AS VARCHAR(100)) AS Historical_Policy_ID,
    CAST(e.enrollee_id AS VARCHAR(100)) AS Historical_Enrollee_ID,
    e.enrollment_status_description AS Historical_Enrollment_Status,
    e.enrollee_status_description AS Historical_Enrollee_Status,
    e.benefit_effective_date AS Historical_Benefit_Effective_Date,
    e.benefit_end_date AS Historical_Benefit_End_Date,
    e.enrollment_create_date AS Historical_Enrollment_Create_Date,
    e.enrollment_last_update_date AS Historical_Enrollment_Last_Update_Date,
    e.enrollee_create_date AS Historical_Enrollee_Create_Date,
    e.enrollee_last_update_date AS Historical_Enrollee_Last_Update_Date,
    e.person_type AS Historical_Person_Type,
    e.relationship_type AS Historical_Relationship_Type,
    CAST(e.net_premium_amt AS DECIMAL(38, 10))
        AS Historical_Net_Premium_Amount,
    e.physical_row_count_for_key AS Historical_Physical_Row_Count_For_Key
INTO #prior_history
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
        e.enrollment_create_date,
        e.enrollment_last_update_date,
        e.enrollee_create_date,
        e.enrollee_last_update_date,
        e.person_type,
        e.relationship_type,
        e.net_premium_amt,
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
    INNER JOIN (
        SELECT DISTINCT FFM_Enrollee_ID
        FROM #no_inbound_export
    ) AS n
        ON n.FFM_Enrollee_ID = CAST(e.enrollee_id AS VARCHAR(100))
    WHERE e.coverage_year IN (2024, 2025)
) AS e
WHERE e._rn = 1;

CREATE UNIQUE CLUSTERED INDEX CX_prior_history
    ON #prior_history (
        Historical_Coverage_Year,
        Historical_Policy_ID,
        Historical_Enrollee_ID
    );

CREATE NONCLUSTERED INDEX IX_prior_history_enrollee_year
    ON #prior_history (
        Historical_Enrollee_ID,
        Historical_Coverage_Year
    )
    INCLUDE (
        Historical_Issuer,
        Historical_Policy_ID,
        Historical_Enrollment_Status,
        Historical_Enrollee_Status,
        Historical_Benefit_Effective_Date,
        Historical_Benefit_End_Date,
        Historical_Enrollment_Create_Date,
        Historical_Enrollment_Last_Update_Date,
        Historical_Enrollee_Create_Date,
        Historical_Enrollee_Last_Update_Date,
        Historical_Person_Type,
        Historical_Relationship_Type,
        Historical_Net_Premium_Amount
    );


-- =============================================================================
-- C2 — AGGREGATE 2025 EVIDENCE AT THE VALIDATED 2026 BUSINESS GRAIN
-- =============================================================================
IF OBJECT_ID('tempdb..#history_2025_agg') IS NOT NULL
    DROP TABLE #history_2025_agg;

SELECT
    n.FFM_Coverage_Year,
    n.FFM_Policy_ID,
    n.FFM_Enrollee_ID,
    COUNT_BIG(h.Historical_Enrollee_ID) AS History_2025_Row_Count,
    COUNT(DISTINCT h.Historical_Policy_ID)
        AS History_2025_Distinct_Policy_Count,
    COUNT(DISTINCT h.Historical_Issuer)
        AS History_2025_Distinct_Issuer_Count,
    MAX(CASE
            WHEN h.Historical_Issuer = n.FFM_Issuer
             AND h.Historical_Policy_ID = n.FFM_Policy_ID
                THEN 1 ELSE 0
        END) AS Has_2025_Same_Issuer_Same_Policy,
    MAX(CASE
            WHEN h.Historical_Issuer = n.FFM_Issuer
             AND h.Historical_Policy_ID <> n.FFM_Policy_ID
                THEN 1 ELSE 0
        END) AS Has_2025_Same_Issuer_Different_Policy,
    MAX(CASE
            WHEN h.Historical_Issuer <> n.FFM_Issuer
                THEN 1 ELSE 0
        END) AS Has_2025_Different_Issuer,
    MAX(CASE
            WHEN h.Historical_Enrollee_ID IS NOT NULL
             AND (
                    h.Historical_Issuer IS NULL
                 OR h.Historical_Policy_ID IS NULL
             )
                THEN 1 ELSE 0
        END) AS Has_2025_Incomplete_Key
INTO #history_2025_agg
FROM #no_inbound_export AS n
LEFT JOIN #prior_history AS h
    ON h.Historical_Coverage_Year = 2025
   AND h.Historical_Enrollee_ID = n.FFM_Enrollee_ID
GROUP BY
    n.FFM_Coverage_Year,
    n.FFM_Policy_ID,
    n.FFM_Enrollee_ID;

CREATE UNIQUE CLUSTERED INDEX CX_history_2025_agg
    ON #history_2025_agg (
        FFM_Coverage_Year,
        FFM_Policy_ID,
        FFM_Enrollee_ID
    );


-- =============================================================================
-- C3 — AGGREGATE 2024 EVIDENCE AT THE VALIDATED 2026 BUSINESS GRAIN
-- =============================================================================
IF OBJECT_ID('tempdb..#history_2024_agg') IS NOT NULL
    DROP TABLE #history_2024_agg;

SELECT
    n.FFM_Coverage_Year,
    n.FFM_Policy_ID,
    n.FFM_Enrollee_ID,
    COUNT_BIG(h.Historical_Enrollee_ID) AS History_2024_Row_Count,
    COUNT(DISTINCT h.Historical_Policy_ID)
        AS History_2024_Distinct_Policy_Count,
    COUNT(DISTINCT h.Historical_Issuer)
        AS History_2024_Distinct_Issuer_Count,
    MAX(CASE
            WHEN h.Historical_Issuer = n.FFM_Issuer
                THEN 1 ELSE 0
        END) AS Has_2024_Same_Issuer,
    MAX(CASE
            WHEN h.Historical_Policy_ID = n.FFM_Policy_ID
                THEN 1 ELSE 0
        END) AS Has_2024_Same_Policy
INTO #history_2024_agg
FROM #no_inbound_export AS n
LEFT JOIN #prior_history AS h
    ON h.Historical_Coverage_Year = 2024
   AND h.Historical_Enrollee_ID = n.FFM_Enrollee_ID
GROUP BY
    n.FFM_Coverage_Year,
    n.FFM_Policy_ID,
    n.FFM_Enrollee_ID;

CREATE UNIQUE CLUSTERED INDEX CX_history_2024_agg
    ON #history_2024_agg (
        FFM_Coverage_Year,
        FFM_Policy_ID,
        FFM_Enrollee_ID
    );


-- =============================================================================
-- C4 — REPRESENTATIVE 2025 HISTORY ROW
-- Ranking is for display only:
--   1) same issuer + same policy
--   2) same issuer
--   3) any same-enrollee 2025 row
-- Within each tier, use the validated five-field latest-row chronology.
-- Multiplicity remains preserved in aggregate count/list fields.
-- =============================================================================
IF OBJECT_ID('tempdb..#history_2025_best') IS NOT NULL
    DROP TABLE #history_2025_best;

SELECT *
INTO #history_2025_best
FROM (
    SELECT
        n.FFM_Coverage_Year,
        n.FFM_Policy_ID,
        n.FFM_Enrollee_ID,
        h.Historical_Policy_ID,
        h.Historical_Issuer,
        h.Historical_Enrollment_Status,
        h.Historical_Enrollee_Status,
        h.Historical_Benefit_Effective_Date,
        h.Historical_Benefit_End_Date,
        h.Historical_Enrollment_Create_Date,
        h.Historical_Enrollment_Last_Update_Date,
        h.Historical_Enrollee_Create_Date,
        h.Historical_Enrollee_Last_Update_Date,
        h.Historical_Person_Type,
        h.Historical_Relationship_Type,
        h.Historical_Net_Premium_Amount,
        ROW_NUMBER() OVER (
            PARTITION BY
                n.FFM_Coverage_Year,
                n.FFM_Policy_ID,
                n.FFM_Enrollee_ID
            ORDER BY
                CASE
                    WHEN h.Historical_Issuer = n.FFM_Issuer
                     AND h.Historical_Policy_ID = n.FFM_Policy_ID THEN 1
                    WHEN h.Historical_Issuer = n.FFM_Issuer THEN 2
                    ELSE 3
                END,
                h.Historical_Enrollment_Last_Update_Date DESC,
                h.Historical_Enrollee_Last_Update_Date DESC,
                h.Historical_Enrollment_Create_Date DESC,
                h.Historical_Enrollee_Create_Date DESC,
                h.Historical_Benefit_Effective_Date DESC,
                h.Historical_Policy_ID
        ) AS rn
    FROM #no_inbound_export AS n
    INNER JOIN #prior_history AS h
        ON h.Historical_Coverage_Year = 2025
       AND h.Historical_Enrollee_ID = n.FFM_Enrollee_ID
) AS ranked
WHERE rn = 1;

CREATE UNIQUE CLUSTERED INDEX CX_history_2025_best
    ON #history_2025_best (
        FFM_Coverage_Year,
        FFM_Policy_ID,
        FFM_Enrollee_ID
    );


-- =============================================================================
-- C5 — REPRESENTATIVE 2024 HISTORY ROW
-- Same display-only ranking approach as 2025.
-- =============================================================================
IF OBJECT_ID('tempdb..#history_2024_best') IS NOT NULL
    DROP TABLE #history_2024_best;

SELECT *
INTO #history_2024_best
FROM (
    SELECT
        n.FFM_Coverage_Year,
        n.FFM_Policy_ID,
        n.FFM_Enrollee_ID,
        h.Historical_Policy_ID,
        h.Historical_Issuer,
        h.Historical_Enrollment_Status,
        h.Historical_Enrollee_Status,
        h.Historical_Benefit_Effective_Date,
        h.Historical_Benefit_End_Date,
        h.Historical_Enrollment_Create_Date,
        h.Historical_Enrollment_Last_Update_Date,
        h.Historical_Enrollee_Create_Date,
        h.Historical_Enrollee_Last_Update_Date,
        h.Historical_Person_Type,
        h.Historical_Relationship_Type,
        h.Historical_Net_Premium_Amount,
        ROW_NUMBER() OVER (
            PARTITION BY
                n.FFM_Coverage_Year,
                n.FFM_Policy_ID,
                n.FFM_Enrollee_ID
            ORDER BY
                CASE
                    WHEN h.Historical_Issuer = n.FFM_Issuer
                     AND h.Historical_Policy_ID = n.FFM_Policy_ID THEN 1
                    WHEN h.Historical_Issuer = n.FFM_Issuer THEN 2
                    ELSE 3
                END,
                h.Historical_Enrollment_Last_Update_Date DESC,
                h.Historical_Enrollee_Last_Update_Date DESC,
                h.Historical_Enrollment_Create_Date DESC,
                h.Historical_Enrollee_Create_Date DESC,
                h.Historical_Benefit_Effective_Date DESC,
                h.Historical_Policy_ID
        ) AS rn
    FROM #no_inbound_export AS n
    INNER JOIN #prior_history AS h
        ON h.Historical_Coverage_Year = 2024
       AND h.Historical_Enrollee_ID = n.FFM_Enrollee_ID
) AS ranked
WHERE rn = 1;

CREATE UNIQUE CLUSTERED INDEX CX_history_2024_best
    ON #history_2024_best (
        FFM_Coverage_Year,
        FFM_Policy_ID,
        FFM_Enrollee_ID
    );


-- =============================================================================
-- C6 — DISTINCT 2025 POLICY / ISSUER VALUE LISTS
-- Lists preserve multiplicity evidence without multiplying final rows.
-- =============================================================================
IF OBJECT_ID('tempdb..#history_2025_policy_lists') IS NOT NULL
    DROP TABLE #history_2025_policy_lists;

SELECT
    d.Historical_Enrollee_ID,
    STRING_AGG(
        CAST(d.Historical_Policy_ID AS NVARCHAR(MAX)),
        N' | '
    ) AS History_2025_Policy_ID_List
INTO #history_2025_policy_lists
FROM (
    SELECT DISTINCT
        Historical_Enrollee_ID,
        Historical_Policy_ID
    FROM #prior_history
    WHERE Historical_Coverage_Year = 2025
      AND Historical_Policy_ID IS NOT NULL
) AS d
GROUP BY d.Historical_Enrollee_ID;

CREATE UNIQUE CLUSTERED INDEX CX_history_2025_policy_lists
    ON #history_2025_policy_lists (Historical_Enrollee_ID);

IF OBJECT_ID('tempdb..#history_2025_issuer_lists') IS NOT NULL
    DROP TABLE #history_2025_issuer_lists;

SELECT
    d.Historical_Enrollee_ID,
    STRING_AGG(
        CAST(d.Historical_Issuer AS NVARCHAR(MAX)),
        N' | '
    ) AS History_2025_Issuer_List
INTO #history_2025_issuer_lists
FROM (
    SELECT DISTINCT
        Historical_Enrollee_ID,
        Historical_Issuer
    FROM #prior_history
    WHERE Historical_Coverage_Year = 2025
      AND Historical_Issuer IS NOT NULL
) AS d
GROUP BY d.Historical_Enrollee_ID;

CREATE UNIQUE CLUSTERED INDEX CX_history_2025_issuer_lists
    ON #history_2025_issuer_lists (Historical_Enrollee_ID);


-- =============================================================================
-- D1 — ONE FINAL ANALYTICAL ROW PER VALIDATED 2026 BUSINESS ENTITY
-- Mutually exclusive historical classifications.
--
-- Precedence:
--   4 before 1/2/3 when 2025 evidence is multiple or has incomplete keys.
--   Then exact continuity, same-issuer policy transition, issuer transition.
--   If no 2025 evidence, test 2024; otherwise no prior history.
-- =============================================================================
RAISERROR('PHASE2 D1: classify historical lineage', 10, 1) WITH NOWAIT;

IF OBJECT_ID('tempdb..#lineage_final') IS NOT NULL
    DROP TABLE #lineage_final;

SELECT
    n.FFM_Coverage_Year,
    n.FFM_Issuer,
    n.FFM_Policy_ID,
    n.FFM_Enrollee_ID,
    n.FFM_Enrollment_Status,
    n.FFM_Enrollee_Status,
    n.FFM_Benefit_Effective_Date,
    n.FFM_Benefit_End_Date,
    n.FFM_Enrollment_Create_Date,
    n.FFM_Enrollment_Last_Update_Date,
    n.FFM_Enrollee_Create_Date,
    n.FFM_Enrollee_Last_Update_Date,
    n.FFM_Person_Type,
    n.FFM_Relationship_Type,
    n.FFM_Net_Premium_Amount,

    CAST(CASE WHEN a25.History_2025_Row_Count > 0 THEN 'Y' ELSE 'N' END AS CHAR(1))
        AS Enrollee_Found_2025,
    a25.History_2025_Row_Count,
    a25.History_2025_Distinct_Policy_Count,
    a25.History_2025_Distinct_Issuer_Count,
    CAST(CASE WHEN a25.Has_2025_Same_Issuer_Same_Policy = 1
              OR a25.Has_2025_Same_Issuer_Different_Policy = 1
              THEN 'Y' ELSE 'N' END AS CHAR(1)) AS Same_Issuer_2025,
    CAST(CASE WHEN a25.Has_2025_Same_Issuer_Same_Policy = 1
              THEN 'Y' ELSE 'N' END AS CHAR(1)) AS Same_Policy_2025,
    CAST(CASE WHEN a25.Has_2025_Different_Issuer = 1
              THEN 'Y' ELSE 'N' END AS CHAR(1)) AS Different_Issuer_2025,
    p25.History_2025_Policy_ID_List,
    i25.History_2025_Issuer_List,
    b25.Historical_Policy_ID AS Representative_2025_Policy_ID,
    b25.Historical_Issuer AS Representative_2025_Issuer,
    b25.Historical_Enrollment_Status AS Representative_2025_Enrollment_Status,
    b25.Historical_Enrollee_Status AS Representative_2025_Enrollee_Status,
    b25.Historical_Benefit_Effective_Date AS Representative_2025_Benefit_Effective_Date,
    b25.Historical_Benefit_End_Date AS Representative_2025_Benefit_End_Date,
    b25.Historical_Enrollment_Create_Date AS Representative_2025_Enrollment_Create_Date,
    b25.Historical_Enrollment_Last_Update_Date AS Representative_2025_Enrollment_Last_Update_Date,
    b25.Historical_Enrollee_Create_Date AS Representative_2025_Enrollee_Create_Date,
    b25.Historical_Enrollee_Last_Update_Date AS Representative_2025_Enrollee_Last_Update_Date,
    b25.Historical_Person_Type AS Representative_2025_Person_Type,
    b25.Historical_Relationship_Type AS Representative_2025_Relationship_Type,
    b25.Historical_Net_Premium_Amount AS Representative_2025_Net_Premium_Amount,

    CAST(CASE WHEN a24.History_2024_Row_Count > 0 THEN 'Y' ELSE 'N' END AS CHAR(1))
        AS Enrollee_Found_2024,
    a24.History_2024_Row_Count,
    a24.History_2024_Distinct_Policy_Count,
    a24.History_2024_Distinct_Issuer_Count,
    CAST(CASE WHEN a24.Has_2024_Same_Issuer = 1
              THEN 'Y' ELSE 'N' END AS CHAR(1)) AS Same_Issuer_2024,
    CAST(CASE WHEN a24.Has_2024_Same_Policy = 1
              THEN 'Y' ELSE 'N' END AS CHAR(1)) AS Same_Policy_2024,
    b24.Historical_Policy_ID AS Representative_2024_Policy_ID,
    b24.Historical_Issuer AS Representative_2024_Issuer,
    b24.Historical_Enrollment_Status AS Representative_2024_Enrollment_Status,
    b24.Historical_Enrollee_Status AS Representative_2024_Enrollee_Status,
    b24.Historical_Benefit_Effective_Date AS Representative_2024_Benefit_Effective_Date,
    b24.Historical_Benefit_End_Date AS Representative_2024_Benefit_End_Date,

    CAST(
        CASE
            WHEN a25.History_2025_Row_Count > 1
              OR a25.History_2025_Distinct_Policy_Count > 1
              OR a25.History_2025_Distinct_Issuer_Count > 1
              OR a25.Has_2025_Incomplete_Key = 1
                THEN '4_2025_MULTIPLE_OR_AMBIGUOUS_HISTORY'
            WHEN a25.Has_2025_Same_Issuer_Same_Policy = 1
                THEN '1_2025_SAME_ENROLLEE_SAME_ISSUER_SAME_POLICY'
            WHEN a25.Has_2025_Same_Issuer_Different_Policy = 1
                THEN '2_2025_SAME_ENROLLEE_SAME_ISSUER_DIFFERENT_POLICY'
            WHEN a25.Has_2025_Different_Issuer = 1
                THEN '3_2025_SAME_ENROLLEE_DIFFERENT_ISSUER'
            WHEN a25.History_2025_Row_Count > 0
                THEN '4_2025_MULTIPLE_OR_AMBIGUOUS_HISTORY'
            WHEN a24.History_2024_Row_Count > 0
                THEN '5_NO_2025_HISTORY_BUT_2024_HISTORY_EXISTS'
            ELSE '6_NO_2025_OR_2024_ENROLLEE_HISTORY'
        END
        AS VARCHAR(70)
    ) AS Historical_Classification,

    CAST(
        CASE
            WHEN a25.History_2025_Row_Count > 1
              OR a25.History_2025_Distinct_Policy_Count > 1
              OR a25.History_2025_Distinct_Issuer_Count > 1
              OR a25.Has_2025_Incomplete_Key = 1
                THEN CONCAT(
                    '2025 same-enrollee history requires review: rows=',
                    a25.History_2025_Row_Count,
                    ', policies=', a25.History_2025_Distinct_Policy_Count,
                    ', issuers=', a25.History_2025_Distinct_Issuer_Count,
                    ', incomplete_key=', a25.Has_2025_Incomplete_Key
                )
            WHEN a25.Has_2025_Same_Issuer_Same_Policy = 1
                THEN 'Same Enrollee ID, FFM Issuer, and Policy ID found in 2025'
            WHEN a25.Has_2025_Same_Issuer_Different_Policy = 1
                THEN 'Same Enrollee ID and FFM Issuer found in 2025; Policy ID differs'
            WHEN a25.Has_2025_Different_Issuer = 1
                THEN 'Same Enrollee ID found in 2025 under a different issuer'
            WHEN a25.History_2025_Row_Count > 0
                THEN '2025 same-enrollee history exists but keys are insufficient for categories 1-3'
            WHEN a24.History_2024_Row_Count > 0
                THEN 'No 2025 same-enrollee history; same Enrollee ID found in 2024'
            ELSE 'Same Enrollee ID not found in Enrollments_TEST coverage years 2025 or 2024'
        END
        AS NVARCHAR(500)
    ) AS Classification_Reason
INTO #lineage_final
FROM #no_inbound_export AS n
INNER JOIN #history_2025_agg AS a25
    ON a25.FFM_Coverage_Year = n.FFM_Coverage_Year
   AND a25.FFM_Policy_ID = n.FFM_Policy_ID
   AND a25.FFM_Enrollee_ID = n.FFM_Enrollee_ID
INNER JOIN #history_2024_agg AS a24
    ON a24.FFM_Coverage_Year = n.FFM_Coverage_Year
   AND a24.FFM_Policy_ID = n.FFM_Policy_ID
   AND a24.FFM_Enrollee_ID = n.FFM_Enrollee_ID
LEFT JOIN #history_2025_best AS b25
    ON b25.FFM_Coverage_Year = n.FFM_Coverage_Year
   AND b25.FFM_Policy_ID = n.FFM_Policy_ID
   AND b25.FFM_Enrollee_ID = n.FFM_Enrollee_ID
LEFT JOIN #history_2024_best AS b24
    ON b24.FFM_Coverage_Year = n.FFM_Coverage_Year
   AND b24.FFM_Policy_ID = n.FFM_Policy_ID
   AND b24.FFM_Enrollee_ID = n.FFM_Enrollee_ID
LEFT JOIN #history_2025_policy_lists AS p25
    ON p25.Historical_Enrollee_ID = n.FFM_Enrollee_ID
LEFT JOIN #history_2025_issuer_lists AS i25
    ON i25.Historical_Enrollee_ID = n.FFM_Enrollee_ID;

CREATE CLUSTERED INDEX CX_lineage_final
    ON #lineage_final (
        FFM_Coverage_Year,
        FFM_Policy_ID,
        FFM_Enrollee_ID
    );

CREATE NONCLUSTERED INDEX IX_lineage_class
    ON #lineage_final (
        Historical_Classification,
        FFM_Issuer
    );


-- =============================================================================
-- D2 — SAME-ENROLLEE + SAME-ISSUER 2025 STATUS EVIDENCE
-- Separate evidence table; it does not change or multiply #lineage_final.
-- =============================================================================
IF OBJECT_ID('tempdb..#same_issuer_2025_status_evidence') IS NOT NULL
    DROP TABLE #same_issuer_2025_status_evidence;

SELECT
    n.FFM_Coverage_Year,
    n.FFM_Policy_ID,
    n.FFM_Enrollee_ID,
    h.Historical_Policy_ID,
    h.Historical_Enrollment_Status,
    h.Historical_Enrollee_Status
INTO #same_issuer_2025_status_evidence
FROM #no_inbound_export AS n
INNER JOIN #prior_history AS h
    ON h.Historical_Coverage_Year = 2025
   AND h.Historical_Enrollee_ID = n.FFM_Enrollee_ID
   AND h.Historical_Issuer = n.FFM_Issuer;

CREATE CLUSTERED INDEX CX_same_issuer_2025_status
    ON #same_issuer_2025_status_evidence (
        Historical_Enrollment_Status,
        Historical_Enrollee_Status,
        FFM_Policy_ID,
        FFM_Enrollee_ID
    );


-- =============================================================================
-- E — HARD RECONCILIATION CONTROLS
-- =============================================================================
DECLARE @lineage_row_count BIGINT = (
    SELECT COUNT_BIG(*) FROM #lineage_final
);

DECLARE @lineage_distinct_grain_count BIGINT = (
    SELECT COUNT_BIG(*)
    FROM (
        SELECT
            FFM_Coverage_Year,
            FFM_Policy_ID,
            FFM_Enrollee_ID
        FROM #lineage_final
        GROUP BY
            FFM_Coverage_Year,
            FFM_Policy_ID,
            FFM_Enrollee_ID
    ) AS d
);

DECLARE @lineage_duplicate_count BIGINT =
    @lineage_row_count - @lineage_distinct_grain_count;

DECLARE @classification_bucket_sum BIGINT = (
    SELECT SUM(bucket_count)
    FROM (
        SELECT COUNT_BIG(*) AS bucket_count
        FROM #lineage_final
        GROUP BY Historical_Classification
    ) AS buckets
);

DECLARE @control_status VARCHAR(4) =
    CASE
        WHEN @complete_2026_count = @expected_complete_2026
         AND @ffm_target_count = @expected_ffm_target
         AND @no_inbound_count = @expected_no_inbound
         AND @lineage_row_count = @expected_no_inbound
         AND @lineage_distinct_grain_count = @expected_no_inbound
         AND @lineage_duplicate_count = 0
         AND @classification_bucket_sum = @expected_no_inbound
            THEN 'PASS'
        ELSE 'FAIL'
    END;

SET @msg = CONCAT(
    'PHASE2 complete: no_inbound=', @no_inbound_count,
    '; lineage=', @lineage_row_count,
    '; distinct=', @lineage_distinct_grain_count,
    '; duplicates=', @lineage_duplicate_count,
    '; bucket_sum=', @classification_bucket_sum,
    '; elapsed_s=', DATEDIFF(second, @t0, SYSDATETIME())
);
RAISERROR(@msg, 10, 1) WITH NOWAIT;


-- =============================================================================
-- RESULT 1 — CONTROL TABLE
-- =============================================================================
SELECT
    @complete_2026_count AS COMPLETE_2026_DISTINCT_PAIRS,
    @ffm_target_count AS FFM_TARGET_COUNT,
    @no_inbound_count AS VALIDATED_NO_INBOUND_COUNT,
    @lineage_row_count AS LINEAGE_ROW_COUNT,
    @lineage_distinct_grain_count AS DISTINCT_POLICY_ENROLLEE_COUNT,
    @lineage_duplicate_count AS DUPLICATE_BUSINESS_ENTITY_COUNT,
    @classification_bucket_sum AS CLASSIFICATION_BUCKET_SUM,
    @control_status AS CONTROL_STATUS;

IF @control_status <> 'PASS'
BEGIN
    RAISERROR(
        'STOP E: Phase 2 reconciliation controls failed.',
        16, 1
    );
    RETURN;
END;


-- =============================================================================
-- RESULT 2 — MUTUALLY EXCLUSIVE HISTORICAL LINEAGE COUNTS
-- =============================================================================
SELECT
    Historical_Classification,
    COUNT_BIG(*) AS Record_Count,
    CAST(
        100.0 * COUNT_BIG(*) / NULLIF(@expected_no_inbound, 0)
        AS DECIMAL(10, 4)
    ) AS Percent_of_109776
FROM #lineage_final
GROUP BY Historical_Classification
ORDER BY Historical_Classification;


-- =============================================================================
-- RESULT 3 — ISSUER x HISTORICAL CLASSIFICATION
-- =============================================================================
SELECT
    FFM_Issuer,
    Historical_Classification,
    COUNT_BIG(*) AS Record_Count,
    CAST(
        100.0 * COUNT_BIG(*)
        / NULLIF(
            SUM(COUNT_BIG(*)) OVER (PARTITION BY FFM_Issuer),
            0
        )
        AS DECIMAL(10, 4)
    ) AS Percent_of_Issuer_No_Inbound
FROM #lineage_final
GROUP BY
    FFM_Issuer,
    Historical_Classification
ORDER BY
    SUM(COUNT_BIG(*)) OVER (PARTITION BY FFM_Issuer) DESC,
    FFM_Issuer,
    Historical_Classification;


-- =============================================================================
-- RESULT 4 — 2025 ENROLLMENT STATUS DISTRIBUTION
-- Scope: same Enrollee ID + same 2026 FFM Issuer found in 2025.
-- Historical rows can exceed distinct 2026 records when multiple policies exist.
-- =============================================================================
SELECT
    Historical_Enrollment_Status AS Enrollment_Status_2025,
    COUNT_BIG(*) AS Historical_2025_Row_Count,
    COUNT(
        DISTINCT CONCAT(
            FFM_Coverage_Year,
            '|',
            FFM_Policy_ID,
            '|',
            FFM_Enrollee_ID
        )
    ) AS Distinct_2026_No_Inbound_Records
FROM #same_issuer_2025_status_evidence
GROUP BY Historical_Enrollment_Status
ORDER BY
    Distinct_2026_No_Inbound_Records DESC,
    Historical_Enrollment_Status;


-- =============================================================================
-- RESULT 5 — 2025 ENROLLEE STATUS DISTRIBUTION
-- Scope: same Enrollee ID + same 2026 FFM Issuer found in 2025.
-- =============================================================================
SELECT
    Historical_Enrollee_Status AS Enrollee_Status_2025,
    COUNT_BIG(*) AS Historical_2025_Row_Count,
    COUNT(
        DISTINCT CONCAT(
            FFM_Coverage_Year,
            '|',
            FFM_Policy_ID,
            '|',
            FFM_Enrollee_ID
        )
    ) AS Distinct_2026_No_Inbound_Records
FROM #same_issuer_2025_status_evidence
GROUP BY Historical_Enrollee_Status
ORDER BY
    Distinct_2026_No_Inbound_Records DESC,
    Historical_Enrollee_Status;


-- =============================================================================
-- RESULT 6 — ROW-LEVEL AUDIT DATASET (EXACTLY 109,776 ROWS)
-- No Auto-Renewal candidate is assigned in Phase 2.
-- =============================================================================
SELECT
    FFM_Coverage_Year,
    FFM_Issuer,
    FFM_Policy_ID,
    FFM_Enrollee_ID,
    FFM_Enrollment_Status,
    FFM_Enrollee_Status,
    FFM_Benefit_Effective_Date,
    FFM_Benefit_End_Date,
    FFM_Enrollment_Create_Date,
    FFM_Enrollment_Last_Update_Date,
    FFM_Enrollee_Create_Date,
    FFM_Enrollee_Last_Update_Date,
    FFM_Person_Type,
    FFM_Relationship_Type,
    FFM_Net_Premium_Amount,

    Enrollee_Found_2025,
    History_2025_Row_Count,
    History_2025_Distinct_Policy_Count,
    History_2025_Distinct_Issuer_Count,
    Same_Issuer_2025,
    Same_Policy_2025,
    Different_Issuer_2025,
    History_2025_Policy_ID_List,
    History_2025_Issuer_List,
    Representative_2025_Policy_ID,
    Representative_2025_Issuer,
    Representative_2025_Enrollment_Status,
    Representative_2025_Enrollee_Status,
    Representative_2025_Benefit_Effective_Date,
    Representative_2025_Benefit_End_Date,
    Representative_2025_Enrollment_Create_Date,
    Representative_2025_Enrollment_Last_Update_Date,
    Representative_2025_Enrollee_Create_Date,
    Representative_2025_Enrollee_Last_Update_Date,
    Representative_2025_Person_Type,
    Representative_2025_Relationship_Type,
    Representative_2025_Net_Premium_Amount,

    Enrollee_Found_2024,
    History_2024_Row_Count,
    History_2024_Distinct_Policy_Count,
    History_2024_Distinct_Issuer_Count,
    Same_Issuer_2024,
    Same_Policy_2024,
    Representative_2024_Policy_ID,
    Representative_2024_Issuer,
    Representative_2024_Enrollment_Status,
    Representative_2024_Enrollee_Status,
    Representative_2024_Benefit_Effective_Date,
    Representative_2024_Benefit_End_Date,

    Historical_Classification,
    Classification_Reason
FROM #lineage_final
ORDER BY
    Historical_Classification,
    FFM_Issuer,
    FFM_Policy_ID,
    FFM_Enrollee_ID;
