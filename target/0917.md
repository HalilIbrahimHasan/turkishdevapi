-- =============================================================================
-- ALL ISSUERS — 2026 Enrolled + Pending FFM population
--                 reconciled to dbo.inbound_automation
-- =============================================================================
-- Derived from (DO NOT MODIFY):
--   sql/same_transaction_different_policy_reconciliation.sql
--
-- Purpose (Phase 1 — NO RCNI):
--   Reproduce Swathi/Hari 2026 Enrolled+Pending business population from
--   dbo.Enrollments_TEST and classify each FFM enrollee+policy pair against
--   inbound 834 evidence using the proven hierarchical match engine.
--
-- Grain:
--   ONE ROW PER DISTINCT (FFM_Coverage_Year, FFM_Enrollee_ID, FFM_Policy_ID)
--
-- Safety:
--   READ ONLY against permanent tables.
--   Temp tables / temp indexes only. No INSERT/UPDATE/DELETE/TRUNCATE/DROP/ALTER
--   on permanent objects. No permanent index creation.
--
-- Result sets:
--   0a) SCHEMA CHECK (plan_name / insurer_name on Enrollments_TEST)
--   0 ) FFM STATUS INVENTORY — complete 2026 enrollment × enrollee combinations
--   0c) POPULATION FILTER DIAGNOSTICS (provisional candidates only — not confirmed)
--   0d) INBOUND STATUS INVENTORY (enrolleeStatus counts; 2026 + all years)
--   0e) POPULATION CONTROL — before vs after FFM deduplication (when mode is set)
--   1) POPULATION CONTROL (final #final_results)
--   2) MATCH LEVEL SUMMARY
--   3) ROOT CAUSE SUMMARY
--   4) ISSUER SUMMARY
--   5) FULL DETAIL
--   6) NO INBOUND DETAIL
--   7) SAME ENROLLEE / DIFFERENT POLICY
--   8) CROSS ISSUER
-- =============================================================================

SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @coverage_year INT = 2026;

/*
==============================================================================
POPULATION FILTER — ACTIVE SETTING
==============================================================================
Current active value:

    @population_mode = 'UNSET'

Meaning:
    Diagnostics run (schema / FFM status inventory / provisional filter
    candidates / inbound status inventory). Reconciliation does NOT run
    until you set an explicit mode after comparing Result Set 0 to Swathi.

ALLOWED MODES (column logic only — status value list is separate):
    'ENROLLMENT_ONLY'  -> filter on enrollment_status_description
    'ENROLLEE_ONLY'    -> filter on enrollee_status_description
    'OR'               -> either status column qualifies
    'AND'              -> both status columns qualify

PROVISIONAL STATUS VALUE LIST used when a mode is set
(ASSUMPTION — MUST CONFIRM AGAINST SWATHI):

    Enrolled
    Pending

NOT included by default (no silent equivalence / interpretation):
    Pend            — appears as its own raw value in Result Set 0; not treated as Pending
    Pend canceled   — appears as its own raw value in Result Set 0; not interpreted here

To also include literal 'Pend' after confirming with Swathi, set:
    @include_literal_pend = 1
==============================================================================
*/
DECLARE @population_mode VARCHAR(30) = 'UNSET';
DECLARE @include_literal_pend BIT = 0;  -- keep 0 unless Swathi confirms Pend is in-scope

-- Schema flags from INFORMATION_SCHEMA (no guessing, no unverified joins)
DECLARE @has_plan_name BIT =
    CASE WHEN EXISTS (
        SELECT 1
        FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA = 'dbo'
          AND TABLE_NAME = 'Enrollments_TEST'
          AND COLUMN_NAME = 'plan_name'
    ) THEN 1 ELSE 0 END;

DECLARE @has_insurer_name BIT =
    CASE WHEN EXISTS (
        SELECT 1
        FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA = 'dbo'
          AND TABLE_NAME = 'Enrollments_TEST'
          AND COLUMN_NAME = 'insurer_name'
    ) THEN 1 ELSE 0 END;


-- =============================================================================
-- RESULT SET 0a — SCHEMA CHECK
-- =============================================================================
SELECT
    'dbo.Enrollments_TEST' AS table_name,
    CASE WHEN @has_plan_name = 1 THEN 'EXISTS' ELSE 'MISSING' END AS plan_name_status,
    CASE WHEN @has_insurer_name = 1 THEN 'EXISTS' ELSE 'MISSING' END AS insurer_name_status,
    CASE
        WHEN @has_plan_name = 1 AND @has_insurer_name = 1
            THEN 'Both columns present — populated into detail output when reconciliation runs.'
        WHEN @has_plan_name = 0 AND @has_insurer_name = 0
            THEN 'Neither column exists — detail columns returned as NULL. No replacement invented.'
        WHEN @has_plan_name = 0
            THEN 'plan_name MISSING — NULL. insurer_name kept if present.'
        ELSE 'insurer_name MISSING — NULL. plan_name kept if present.'
    END AS schema_action,
    @population_mode AS active_population_mode,
    @include_literal_pend AS include_literal_pend_flag,
    CASE
        WHEN @population_mode = 'UNSET'
            THEN 'ACTIVE FILTER: NONE (diagnostics only). ASSUMPTION OPEN: Swathi status rule not confirmed.'
        WHEN @include_literal_pend = 1
            THEN CONCAT('ACTIVE FILTER: ', @population_mode,
                        ' on provisional values Enrolled + Pending + Pend. CONFIRM vs Swathi.')
        ELSE CONCAT('ACTIVE FILTER: ', @population_mode,
                    ' on provisional values Enrolled + Pending only (Pend NOT included). CONFIRM vs Swathi.')
    END AS active_population_filter_label;


-- =============================================================================
-- RESULT SET 0 — FFM STATUS INVENTORY (complete 2026 combinations)
-- =============================================================================
-- Authoritative view of source values. Use this to determine Swathi's exact rule.
-- Do NOT assume Enrolled/Pending/Pend OR-logic from this inventory alone.
-- =============================================================================
SELECT
    e.enrollment_status_description,
    e.enrollee_status_description,
    COUNT(*) AS row_count,
    COUNT(DISTINCT e.enrollee_id) AS distinct_enrollees,
    COUNT(DISTINCT e.enrollment_id) AS distinct_policies,
    COUNT(DISTINCT CAST(e.enrollee_id AS VARCHAR(50)) + '|' + CAST(e.enrollment_id AS VARCHAR(50)))
        AS distinct_enrollee_policy_pairs,
    COUNT(DISTINCT e.hios_issuer_id) AS distinct_issuers
FROM dbo.Enrollments_TEST AS e
WHERE e.coverage_year = @coverage_year
GROUP BY
    e.enrollment_status_description,
    e.enrollee_status_description
ORDER BY
    row_count DESC,
    e.enrollment_status_description,
    e.enrollee_status_description;


-- =============================================================================
-- RESULT SET 0c — POPULATION FILTER DIAGNOSTICS (PROVISIONAL ONLY)
-- =============================================================================
-- These are candidate count definitions to compare with Swathi.
-- They are NOT confirmed business rules.
-- Pend is counted separately from Pending — never silently merged.
-- =============================================================================
;WITH base AS (
    SELECT
        e.enrollee_id,
        e.enrollment_id,
        e.hios_issuer_id,
        UPPER(LTRIM(RTRIM(e.enrollment_status_description))) AS enrollment_status_norm,
        UPPER(LTRIM(RTRIM(e.enrollee_status_description)))   AS enrollee_status_norm
    FROM dbo.Enrollments_TEST AS e
    WHERE e.coverage_year = @coverage_year
),
flags AS (
    SELECT
        enrollee_id,
        enrollment_id,
        hios_issuer_id,
        CASE WHEN enrollment_status_norm = 'ENROLLED' THEN 1 ELSE 0 END AS enr_enrolled,
        CASE WHEN enrollment_status_norm = 'PENDING'  THEN 1 ELSE 0 END AS enr_pending,
        CASE WHEN enrollment_status_norm = 'PEND'     THEN 1 ELSE 0 END AS enr_pend,
        CASE WHEN enrollee_status_norm = 'ENROLLED' THEN 1 ELSE 0 END AS eel_enrolled,
        CASE WHEN enrollee_status_norm = 'PENDING'  THEN 1 ELSE 0 END AS eel_pending,
        CASE WHEN enrollee_status_norm = 'PEND'     THEN 1 ELSE 0 END AS eel_pend
    FROM base
)
SELECT
    scenario_group,
    filter_definition,
    raw_row_count,
    distinct_enrollee_policy_pairs,
    distinct_enrollees,
    distinct_policies,
    distinct_issuers,
    assumption_note
FROM (
    /* --- Exact single-value inventories by column --- */
    SELECT 'value_inventory' AS scenario_group,
           'enrollment_status = Enrolled' AS filter_definition,
           SUM(enr_enrolled), COUNT(DISTINCT CASE WHEN enr_enrolled=1 THEN CAST(enrollee_id AS VARCHAR(50))+'|'+CAST(enrollment_id AS VARCHAR(50)) END),
           COUNT(DISTINCT CASE WHEN enr_enrolled=1 THEN enrollee_id END),
           COUNT(DISTINCT CASE WHEN enr_enrolled=1 THEN enrollment_id END),
           COUNT(DISTINCT CASE WHEN enr_enrolled=1 THEN hios_issuer_id END),
           'Exact raw value count — no Pending/Pend mixed in'
    FROM flags
    UNION ALL
    SELECT 'value_inventory', 'enrollment_status = Pending',
           SUM(enr_pending), COUNT(DISTINCT CASE WHEN enr_pending=1 THEN CAST(enrollee_id AS VARCHAR(50))+'|'+CAST(enrollment_id AS VARCHAR(50)) END),
           COUNT(DISTINCT CASE WHEN enr_pending=1 THEN enrollee_id END),
           COUNT(DISTINCT CASE WHEN enr_pending=1 THEN enrollment_id END),
           COUNT(DISTINCT CASE WHEN enr_pending=1 THEN hios_issuer_id END),
           'Exact raw value — NOT merged with Pend'
    FROM flags
    UNION ALL
    SELECT 'value_inventory', 'enrollment_status = Pend',
           SUM(enr_pend), COUNT(DISTINCT CASE WHEN enr_pend=1 THEN CAST(enrollee_id AS VARCHAR(50))+'|'+CAST(enrollment_id AS VARCHAR(50)) END),
           COUNT(DISTINCT CASE WHEN enr_pend=1 THEN enrollee_id END),
           COUNT(DISTINCT CASE WHEN enr_pend=1 THEN enrollment_id END),
           COUNT(DISTINCT CASE WHEN enr_pend=1 THEN hios_issuer_id END),
           'Exact raw value — NOT treated as Pending'
    FROM flags
    UNION ALL
    SELECT 'value_inventory', 'enrollee_status = Enrolled',
           SUM(eel_enrolled), COUNT(DISTINCT CASE WHEN eel_enrolled=1 THEN CAST(enrollee_id AS VARCHAR(50))+'|'+CAST(enrollment_id AS VARCHAR(50)) END),
           COUNT(DISTINCT CASE WHEN eel_enrolled=1 THEN enrollee_id END),
           COUNT(DISTINCT CASE WHEN eel_enrolled=1 THEN enrollment_id END),
           COUNT(DISTINCT CASE WHEN eel_enrolled=1 THEN hios_issuer_id END),
           'Exact raw value count — no Pending/Pend mixed in'
    FROM flags
    UNION ALL
    SELECT 'value_inventory', 'enrollee_status = Pending',
           SUM(eel_pending), COUNT(DISTINCT CASE WHEN eel_pending=1 THEN CAST(enrollee_id AS VARCHAR(50))+'|'+CAST(enrollment_id AS VARCHAR(50)) END),
           COUNT(DISTINCT CASE WHEN eel_pending=1 THEN enrollee_id END),
           COUNT(DISTINCT CASE WHEN eel_pending=1 THEN enrollment_id END),
           COUNT(DISTINCT CASE WHEN eel_pending=1 THEN hios_issuer_id END),
           'Exact raw value — NOT merged with Pend'
    FROM flags
    UNION ALL
    SELECT 'value_inventory', 'enrollee_status = Pend',
           SUM(eel_pend), COUNT(DISTINCT CASE WHEN eel_pend=1 THEN CAST(enrollee_id AS VARCHAR(50))+'|'+CAST(enrollment_id AS VARCHAR(50)) END),
           COUNT(DISTINCT CASE WHEN eel_pend=1 THEN enrollee_id END),
           COUNT(DISTINCT CASE WHEN eel_pend=1 THEN enrollment_id END),
           COUNT(DISTINCT CASE WHEN eel_pend=1 THEN hios_issuer_id END),
           'Exact raw value — NOT treated as Pending'
    FROM flags

    /* --- Provisional Enrolled+Pending (Pend excluded) --- */
    UNION ALL
    SELECT 'provisional_Enrolled_Pending_no_Pend', 'a. ENROLLMENT_ONLY Enrolled+Pending',
           SUM(CASE WHEN enr_enrolled=1 OR enr_pending=1 THEN 1 ELSE 0 END),
           COUNT(DISTINCT CASE WHEN enr_enrolled=1 OR enr_pending=1 THEN CAST(enrollee_id AS VARCHAR(50))+'|'+CAST(enrollment_id AS VARCHAR(50)) END),
           COUNT(DISTINCT CASE WHEN enr_enrolled=1 OR enr_pending=1 THEN enrollee_id END),
           COUNT(DISTINCT CASE WHEN enr_enrolled=1 OR enr_pending=1 THEN enrollment_id END),
           COUNT(DISTINCT CASE WHEN enr_enrolled=1 OR enr_pending=1 THEN hios_issuer_id END),
           'PROVISIONAL — default candidate list if mode=ENROLLMENT_ONLY and @include_literal_pend=0'
    FROM flags
    UNION ALL
    SELECT 'provisional_Enrolled_Pending_no_Pend', 'b. ENROLLEE_ONLY Enrolled+Pending',
           SUM(CASE WHEN eel_enrolled=1 OR eel_pending=1 THEN 1 ELSE 0 END),
           COUNT(DISTINCT CASE WHEN eel_enrolled=1 OR eel_pending=1 THEN CAST(enrollee_id AS VARCHAR(50))+'|'+CAST(enrollment_id AS VARCHAR(50)) END),
           COUNT(DISTINCT CASE WHEN eel_enrolled=1 OR eel_pending=1 THEN enrollee_id END),
           COUNT(DISTINCT CASE WHEN eel_enrolled=1 OR eel_pending=1 THEN enrollment_id END),
           COUNT(DISTINCT CASE WHEN eel_enrolled=1 OR eel_pending=1 THEN hios_issuer_id END),
           'PROVISIONAL — default candidate list if mode=ENROLLEE_ONLY and @include_literal_pend=0'
    FROM flags
    UNION ALL
    SELECT 'provisional_Enrolled_Pending_no_Pend', 'c. OR Enrolled+Pending',
           SUM(CASE WHEN enr_enrolled=1 OR enr_pending=1 OR eel_enrolled=1 OR eel_pending=1 THEN 1 ELSE 0 END),
           COUNT(DISTINCT CASE WHEN enr_enrolled=1 OR enr_pending=1 OR eel_enrolled=1 OR eel_pending=1 THEN CAST(enrollee_id AS VARCHAR(50))+'|'+CAST(enrollment_id AS VARCHAR(50)) END),
           COUNT(DISTINCT CASE WHEN enr_enrolled=1 OR enr_pending=1 OR eel_enrolled=1 OR eel_pending=1 THEN enrollee_id END),
           COUNT(DISTINCT CASE WHEN enr_enrolled=1 OR enr_pending=1 OR eel_enrolled=1 OR eel_pending=1 THEN enrollment_id END),
           COUNT(DISTINCT CASE WHEN enr_enrolled=1 OR enr_pending=1 OR eel_enrolled=1 OR eel_pending=1 THEN hios_issuer_id END),
           'PROVISIONAL — NOT confirmed as Swathi rule'
    FROM flags
    UNION ALL
    SELECT 'provisional_Enrolled_Pending_no_Pend', 'd. AND Enrolled+Pending',
           SUM(CASE WHEN (enr_enrolled=1 OR enr_pending=1) AND (eel_enrolled=1 OR eel_pending=1) THEN 1 ELSE 0 END),
           COUNT(DISTINCT CASE WHEN (enr_enrolled=1 OR enr_pending=1) AND (eel_enrolled=1 OR eel_pending=1) THEN CAST(enrollee_id AS VARCHAR(50))+'|'+CAST(enrollment_id AS VARCHAR(50)) END),
           COUNT(DISTINCT CASE WHEN (enr_enrolled=1 OR enr_pending=1) AND (eel_enrolled=1 OR eel_pending=1) THEN enrollee_id END),
           COUNT(DISTINCT CASE WHEN (enr_enrolled=1 OR enr_pending=1) AND (eel_enrolled=1 OR eel_pending=1) THEN enrollment_id END),
           COUNT(DISTINCT CASE WHEN (enr_enrolled=1 OR enr_pending=1) AND (eel_enrolled=1 OR eel_pending=1) THEN hios_issuer_id END),
           'PROVISIONAL — NOT confirmed as Swathi rule'
    FROM flags

    /* --- Sensitivity: add literal Pend (still separate from Pending) --- */
    UNION ALL
    SELECT 'sensitivity_plus_literal_Pend', 'ENROLLMENT_ONLY Enrolled+Pending+Pend',
           SUM(CASE WHEN enr_enrolled=1 OR enr_pending=1 OR enr_pend=1 THEN 1 ELSE 0 END),
           COUNT(DISTINCT CASE WHEN enr_enrolled=1 OR enr_pending=1 OR enr_pend=1 THEN CAST(enrollee_id AS VARCHAR(50))+'|'+CAST(enrollment_id AS VARCHAR(50)) END),
           COUNT(DISTINCT CASE WHEN enr_enrolled=1 OR enr_pending=1 OR enr_pend=1 THEN enrollee_id END),
           COUNT(DISTINCT CASE WHEN enr_enrolled=1 OR enr_pending=1 OR enr_pend=1 THEN enrollment_id END),
           COUNT(DISTINCT CASE WHEN enr_enrolled=1 OR enr_pending=1 OR enr_pend=1 THEN hios_issuer_id END),
           'SENSITIVITY ONLY — requires @include_literal_pend=1; Pend still not equated to Pending'
    FROM flags
    UNION ALL
    SELECT 'sensitivity_plus_literal_Pend', 'OR Enrolled+Pending+Pend',
           SUM(CASE WHEN enr_enrolled=1 OR enr_pending=1 OR enr_pend=1
                      OR eel_enrolled=1 OR eel_pending=1 OR eel_pend=1 THEN 1 ELSE 0 END),
           COUNT(DISTINCT CASE WHEN enr_enrolled=1 OR enr_pending=1 OR enr_pend=1
                                 OR eel_enrolled=1 OR eel_pending=1 OR eel_pend=1
                 THEN CAST(enrollee_id AS VARCHAR(50))+'|'+CAST(enrollment_id AS VARCHAR(50)) END),
           COUNT(DISTINCT CASE WHEN enr_enrolled=1 OR enr_pending=1 OR enr_pend=1
                                 OR eel_enrolled=1 OR eel_pending=1 OR eel_pend=1 THEN enrollee_id END),
           COUNT(DISTINCT CASE WHEN enr_enrolled=1 OR enr_pending=1 OR enr_pend=1
                                 OR eel_enrolled=1 OR eel_pending=1 OR eel_pend=1 THEN enrollment_id END),
           COUNT(DISTINCT CASE WHEN enr_enrolled=1 OR enr_pending=1 OR enr_pend=1
                                 OR eel_enrolled=1 OR eel_pending=1 OR eel_pend=1 THEN hios_issuer_id END),
           'SENSITIVITY ONLY — NOT assumed'
    FROM flags
) AS diag (scenario_group, filter_definition, raw_row_count, distinct_enrollee_policy_pairs,
           distinct_enrollees, distinct_policies, distinct_issuers, assumption_note)
ORDER BY
    CASE scenario_group
        WHEN 'value_inventory' THEN 1
        WHEN 'provisional_Enrolled_Pending_no_Pend' THEN 2
        ELSE 3
    END,
    filter_definition;


-- =============================================================================
-- RESULT SET 0d — INBOUND STATUS INVENTORY
-- =============================================================================
-- Critical for Pending analysis: do not invent Pending -> CONFIRM mapping.
-- Flag any enrolleeStatus values outside CONFIRM / CANCEL / TERM.
-- =============================================================================
SELECT
    'coverage_year=2026' AS scope,
    ia.enrolleeStatus AS Inbound_Status_Raw,
    COUNT(*) AS raw_row_count,
    COUNT(DISTINCT ia.member_id) AS distinct_member_id,
    COUNT(DISTINCT ia.issuer) AS distinct_issuers,
    CASE
        WHEN UPPER(LTRIM(RTRIM(ia.enrolleeStatus))) IN ('CONFIRM', 'CANCEL', 'TERM')
            THEN 'KNOWN_CORE'
        WHEN ia.enrolleeStatus IS NULL OR LTRIM(RTRIM(ia.enrolleeStatus)) = ''
            THEN 'NULL_OR_BLANK'
        ELSE 'OTHER_REVIEW — no FFM Pending mapping invented'
    END AS status_class
FROM dbo.inbound_automation AS ia
WHERE ia.coverage_year = @coverage_year
GROUP BY ia.enrolleeStatus

UNION ALL

SELECT
    'all_coverage_years' AS scope,
    ia.enrolleeStatus,
    COUNT(*),
    COUNT(DISTINCT ia.member_id),
    COUNT(DISTINCT ia.issuer),
    CASE
        WHEN UPPER(LTRIM(RTRIM(ia.enrolleeStatus))) IN ('CONFIRM', 'CANCEL', 'TERM')
            THEN 'KNOWN_CORE'
        WHEN ia.enrolleeStatus IS NULL OR LTRIM(RTRIM(ia.enrolleeStatus)) = ''
            THEN 'NULL_OR_BLANK'
        ELSE 'OTHER_REVIEW — no FFM Pending mapping invented'
    END
FROM dbo.inbound_automation AS ia
GROUP BY ia.enrolleeStatus
ORDER BY
    scope,
    raw_row_count DESC;


-- Stop here until an authoritative population mode is chosen.
IF @population_mode NOT IN ('ENROLLMENT_ONLY', 'ENROLLEE_ONLY', 'OR', 'AND')
BEGIN
    SELECT
        'POPULATION_MODE_UNSET' AS status,
        @population_mode AS current_population_mode,
        @include_literal_pend AS include_literal_pend_flag,
        'ACTIVE FILTER: NONE. Review Result Set 0 (FFM status combinations) and 0d (inbound statuses). Then set @population_mode and optionally @include_literal_pend. Reconciliation not executed.' AS next_step,
        'REMAINING ASSUMPTION: Swathi exact status field + value list not confirmed. Do not treat OR(Enrolled/Pending/Pend) as proven.' AS open_assumption;
    RETURN;
END;


-- =============================================================================
-- STEP A — FFM population (raw then deduped)
-- =============================================================================
-- Status normalization:
--   Enrolled -> CONFIRM
--   Pending  -> PENDING   (never CONFIRM)
--   Pend     -> PEND      (separate; NOT collapsed to PENDING)
--   else     -> STATUS_MAPPING_REVIEW  (includes Pend canceled; no invented meaning)
-- =============================================================================
IF OBJECT_ID('tempdb..#ffm_raw') IS NOT NULL DROP TABLE #ffm_raw;
IF OBJECT_ID('tempdb..#ffm') IS NOT NULL DROP TABLE #ffm;

SELECT
    e.coverage_year                                              AS FFM_Coverage_Year,
    CAST(e.enrollee_id AS VARCHAR(100))                          AS FFM_Enrollee_ID,
    CAST(e.enrollment_id AS VARCHAR(100))                        AS FFM_Policy_ID,
    CAST(e.hios_issuer_id AS VARCHAR(20))                        AS FFM_Issuer,
    CAST(NULL AS NVARCHAR(500))                                  AS plan_name,
    CAST(NULL AS NVARCHAR(500))                                  AS insurer_name,
    e.enrollment_status_description                              AS FFM_Enrollment_Status_Raw,
    e.enrollee_status_description                                AS FFM_Enrollee_Status_Raw,
    COALESCE(e.enrollee_status_description, e.enrollment_status_description)
                                                                 AS FFM_Status_Raw,
    CASE
        WHEN UPPER(LTRIM(RTRIM(COALESCE(e.enrollee_status_description, e.enrollment_status_description))))
             = 'ENROLLED' THEN 'CONFIRM'
        WHEN UPPER(LTRIM(RTRIM(COALESCE(e.enrollee_status_description, e.enrollment_status_description))))
             = 'PENDING' THEN 'PENDING'
        WHEN UPPER(LTRIM(RTRIM(COALESCE(e.enrollee_status_description, e.enrollment_status_description))))
             = 'PEND' THEN 'PEND'
        WHEN UPPER(LTRIM(RTRIM(COALESCE(e.enrollee_status_description, e.enrollment_status_description))))
             IN ('CANCELLED', 'CANCELED') THEN 'CANCEL'
        WHEN UPPER(LTRIM(RTRIM(COALESCE(e.enrollee_status_description, e.enrollment_status_description))))
             = 'TERMINATED' THEN 'TERM'
        ELSE 'STATUS_MAPPING_REVIEW'
    END                                                          AS FFM_Status_Norm,
    COALESCE(
        e.enrollment_last_update_date,
        CASE
            WHEN UPPER(LTRIM(RTRIM(COALESCE(e.enrollee_status_description, e.enrollment_status_description))))
                 IN ('CANCELLED', 'CANCELED', 'TERMINATED')
                THEN e.benefit_end_date
        END,
        e.enrollment_create_date,
        e.benefit_effective_date
    )                                                            AS FFM_Event_Date,
    e.benefit_effective_date                                     AS FFM_Benefit_Effective_Date,
    e.benefit_end_date                                           AS FFM_Benefit_End_Date,
    e.enrollment_create_date                                     AS FFM_Create_Date,
    e.enrollment_last_update_date                                AS FFM_Last_Update_Date,
    e.household_id,
    e.person_type,
    e.relationship_type,
    e.source                                                     AS FFM_Source
INTO #ffm_raw
FROM dbo.Enrollments_TEST AS e
WHERE e.coverage_year = @coverage_year
  AND (
        (@population_mode = 'ENROLLMENT_ONLY'
         AND (
                UPPER(LTRIM(RTRIM(e.enrollment_status_description))) IN ('ENROLLED', 'PENDING')
             OR (@include_literal_pend = 1
                 AND UPPER(LTRIM(RTRIM(e.enrollment_status_description))) = 'PEND')
             ))
     OR (@population_mode = 'ENROLLEE_ONLY'
         AND (
                UPPER(LTRIM(RTRIM(e.enrollee_status_description))) IN ('ENROLLED', 'PENDING')
             OR (@include_literal_pend = 1
                 AND UPPER(LTRIM(RTRIM(e.enrollee_status_description))) = 'PEND')
             ))
     OR (@population_mode = 'OR'
         AND (
                UPPER(LTRIM(RTRIM(e.enrollment_status_description))) IN ('ENROLLED', 'PENDING')
             OR UPPER(LTRIM(RTRIM(e.enrollee_status_description)))   IN ('ENROLLED', 'PENDING')
             OR (@include_literal_pend = 1 AND (
                    UPPER(LTRIM(RTRIM(e.enrollment_status_description))) = 'PEND'
                 OR UPPER(LTRIM(RTRIM(e.enrollee_status_description)))   = 'PEND'
             ))
             ))
     OR (@population_mode = 'AND'
         AND (
                UPPER(LTRIM(RTRIM(e.enrollment_status_description))) IN ('ENROLLED', 'PENDING')
             OR (@include_literal_pend = 1
                 AND UPPER(LTRIM(RTRIM(e.enrollment_status_description))) = 'PEND')
             )
         AND (
                UPPER(LTRIM(RTRIM(e.enrollee_status_description))) IN ('ENROLLED', 'PENDING')
             OR (@include_literal_pend = 1
                 AND UPPER(LTRIM(RTRIM(e.enrollee_status_description))) = 'PEND')
             ))
      );

-- Deduplicate to one row per coverage_year + enrollee + policy
SELECT *
INTO #ffm
FROM (
    SELECT
        r.*,
        ROW_NUMBER() OVER (
            PARTITION BY r.FFM_Coverage_Year, r.FFM_Enrollee_ID, r.FFM_Policy_ID
            ORDER BY
                r.FFM_Last_Update_Date DESC,
                r.FFM_Create_Date DESC
        ) AS _rn
    FROM #ffm_raw AS r
) AS x
WHERE x._rn = 1;

ALTER TABLE #ffm DROP COLUMN _rn;

/* Optional enrichment only when columns physically exist */
IF @has_plan_name = 1
BEGIN
    EXEC(N'
        UPDATE f
        SET plan_name = CAST(e.plan_name AS NVARCHAR(500))
        FROM #ffm AS f
        INNER JOIN dbo.Enrollments_TEST AS e
            ON e.coverage_year = f.FFM_Coverage_Year
           AND CAST(e.enrollee_id AS VARCHAR(100)) = f.FFM_Enrollee_ID
           AND CAST(e.enrollment_id AS VARCHAR(100)) = f.FFM_Policy_ID;
    ');
END;

IF @has_insurer_name = 1
BEGIN
    EXEC(N'
        UPDATE f
        SET insurer_name = CAST(e.insurer_name AS NVARCHAR(500))
        FROM #ffm AS f
        INNER JOIN dbo.Enrollments_TEST AS e
            ON e.coverage_year = f.FFM_Coverage_Year
           AND CAST(e.enrollee_id AS VARCHAR(100)) = f.FFM_Enrollee_ID
           AND CAST(e.enrollment_id AS VARCHAR(100)) = f.FFM_Policy_ID;
    ');
END;

CREATE CLUSTERED INDEX CX_ffm ON #ffm (FFM_Enrollee_ID, FFM_Policy_ID);
CREATE NONCLUSTERED INDEX IX_ffm_issuer ON #ffm (FFM_Issuer);


-- =============================================================================
-- RESULT SET 0e — POPULATION CONTROL BEFORE / AFTER FFM DEDUP
-- =============================================================================
SELECT
    'BEFORE_DEDUP' AS stage,
    @population_mode AS applied_population_mode,
    @include_literal_pend AS include_literal_pend,
    CASE WHEN @include_literal_pend = 1
         THEN 'provisional values: Enrolled + Pending + Pend'
         ELSE 'provisional values: Enrolled + Pending (Pend excluded)'
    END AS provisional_status_value_list,
    COUNT(*) AS raw_selected_ffm_rows,
    COUNT(DISTINCT CAST(FFM_Coverage_Year AS VARCHAR(10)) + '|' + FFM_Enrollee_ID + '|' + FFM_Policy_ID)
        AS distinct_coverage_enrollee_policy_pairs,
    CAST(NULL AS INT) AS rows_removed_by_ffm_dedup,
    COUNT(DISTINCT FFM_Enrollee_ID) AS distinct_enrollees,
    COUNT(DISTINCT FFM_Policy_ID) AS distinct_policies,
    COUNT(DISTINCT FFM_Issuer) AS distinct_issuers
FROM #ffm_raw

UNION ALL

SELECT
    'AFTER_DEDUP',
    @population_mode,
    @include_literal_pend,
    CASE WHEN @include_literal_pend = 1
         THEN 'provisional values: Enrolled + Pending + Pend'
         ELSE 'provisional values: Enrolled + Pending (Pend excluded)'
    END,
    COUNT(*),
    COUNT(*),
    (SELECT COUNT(*) FROM #ffm_raw) - COUNT(*),
    COUNT(DISTINCT FFM_Enrollee_ID),
    COUNT(DISTINCT FFM_Policy_ID),
    COUNT(DISTINCT FFM_Issuer)
FROM #ffm;


-- =============================================================================
-- STEP B — Inbound working set into #inbound
-- =============================================================================
-- Preserve ALL identifier columns separately (no COALESCE that hides alternates).
-- Include rows that have ANY of the three enrollee identifiers populated.
-- File date extracted from source_file stamp when present; loaded_at is NOT used
-- as the business event date (ingestion metadata only).
-- =============================================================================
IF OBJECT_ID('tempdb..#inbound') IS NOT NULL DROP TABLE #inbound;

SELECT
    ia.id                                                        AS inbound_row_id,
    NULLIF(LTRIM(RTRIM(CAST(ia.member_id AS VARCHAR(100)))), '')
                                                                 AS Inbound_Member_ID,
    NULLIF(LTRIM(RTRIM(CAST(ia.issuer_indiv_identifier AS VARCHAR(100)))), '')
                                                                 AS Inbound_Issuer_Individual_ID,
    NULLIF(LTRIM(RTRIM(CAST(ia.exchg_assigned_enrollee_id AS VARCHAR(100)))), '')
                                                                 AS Inbound_Exchange_Assigned_Enrollee_ID,
    NULLIF(LTRIM(RTRIM(CAST(ia.policy_id AS VARCHAR(100)))), '')
                                                                 AS Inbound_Policy_ID,
    NULLIF(LTRIM(RTRIM(CAST(ia.health_coverage_policy_no AS VARCHAR(100)))), '')
                                                                 AS Inbound_Health_Coverage_Policy_No,
    CAST(ia.issuer AS VARCHAR(20))                               AS Inbound_Issuer,
    ia.coverage_year                                             AS Inbound_Coverage_Year,
    ia.enrolleeStatus                                            AS Inbound_Status_Raw,
    CASE
        WHEN UPPER(LTRIM(RTRIM(ia.enrolleeStatus))) = 'CONFIRM' THEN 'CONFIRM'
        WHEN UPPER(LTRIM(RTRIM(ia.enrolleeStatus))) = 'CANCEL'  THEN 'CANCEL'
        WHEN UPPER(LTRIM(RTRIM(ia.enrolleeStatus))) = 'TERM'    THEN 'TERM'
        ELSE 'STATUS_MAPPING_REVIEW'
    END                                                          AS Inbound_Status_Norm,
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
    )                                                            AS Inbound_File_Date,
    /* Business event date preference (same philosophy as original query) */
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
    )                                                            AS Inbound_Event_Date,
    ia.folder_year                                               AS Folder_Year,
    ia.folder_month                                              AS Folder_Month,
    ia.source_file                                               AS Source_File,
    ia.household_or_employee_case_id                             AS Inbound_Household_Or_Case_ID,
    ia.relationship                                              AS Inbound_Relationship,
    ia.loaded_at
INTO #inbound
FROM dbo.inbound_automation AS ia
WHERE NULLIF(LTRIM(RTRIM(ia.member_id)), '') IS NOT NULL
   OR NULLIF(LTRIM(RTRIM(ia.issuer_indiv_identifier)), '') IS NOT NULL
   OR NULLIF(LTRIM(RTRIM(ia.exchg_assigned_enrollee_id)), '') IS NOT NULL;

CREATE CLUSTERED INDEX CX_inbound ON #inbound (inbound_row_id);
CREATE NONCLUSTERED INDEX IX_inbound_member
    ON #inbound (Inbound_Member_ID)
    INCLUDE (Inbound_Policy_ID, Inbound_Issuer, Inbound_Event_Date);
CREATE NONCLUSTERED INDEX IX_inbound_issuer_indiv
    ON #inbound (Inbound_Issuer_Individual_ID)
    INCLUDE (Inbound_Policy_ID, Inbound_Issuer, Inbound_Event_Date);
CREATE NONCLUSTERED INDEX IX_inbound_exchg
    ON #inbound (Inbound_Exchange_Assigned_Enrollee_ID)
    INCLUDE (Inbound_Policy_ID, Inbound_Issuer, Inbound_Event_Date);
CREATE NONCLUSTERED INDEX IX_inbound_policy
    ON #inbound (Inbound_Policy_ID);
CREATE NONCLUSTERED INDEX IX_inbound_hc_policy
    ON #inbound (Inbound_Health_Coverage_Policy_No);


-- =============================================================================
-- STEP C — Enrollee-first candidate generation (NO policy join requirement)
-- =============================================================================
-- Match FFM_Enrollee_ID independently against all three inbound ID columns.
-- Use UNION of three equi-joins (not OR) so the optimizer can use the indexes,
-- then collapse to one row per (FFM pair, inbound_row_id) so duplicate ID columns
-- on the same inbound row do not multiply candidates.
--
-- Matched_Inbound_ID_Type priority when multiple columns match the same row:
--   MEMBER_ID > ISSUER_INDIV_IDENTIFIER > EXCHG_ASSIGNED_ENROLLEE_ID
--   (compound labels used when more than one column matches)
-- =============================================================================
IF OBJECT_ID('tempdb..#candidate_hits') IS NOT NULL DROP TABLE #candidate_hits;

;WITH hit_raw AS (
    SELECT
        f.FFM_Coverage_Year,
        f.FFM_Enrollee_ID,
        f.FFM_Policy_ID,
        i.inbound_row_id,
        CAST('MEMBER_ID' AS VARCHAR(40)) AS hit_type
    FROM #ffm AS f
    INNER JOIN #inbound AS i
        ON i.Inbound_Member_ID = f.FFM_Enrollee_ID

    UNION ALL

    SELECT
        f.FFM_Coverage_Year,
        f.FFM_Enrollee_ID,
        f.FFM_Policy_ID,
        i.inbound_row_id,
        CAST('ISSUER_INDIV_IDENTIFIER' AS VARCHAR(40)) AS hit_type
    FROM #ffm AS f
    INNER JOIN #inbound AS i
        ON i.Inbound_Issuer_Individual_ID = f.FFM_Enrollee_ID

    UNION ALL

    SELECT
        f.FFM_Coverage_Year,
        f.FFM_Enrollee_ID,
        f.FFM_Policy_ID,
        i.inbound_row_id,
        CAST('EXCHG_ASSIGNED_ENROLLEE_ID' AS VARCHAR(40)) AS hit_type
    FROM #ffm AS f
    INNER JOIN #inbound AS i
        ON i.Inbound_Exchange_Assigned_Enrollee_ID = f.FFM_Enrollee_ID
)
SELECT
    FFM_Coverage_Year,
    FFM_Enrollee_ID,
    FFM_Policy_ID,
    inbound_row_id,
    /* Collapse multi-column hits on the same inbound row */
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
GROUP BY
    FFM_Coverage_Year,
    FFM_Enrollee_ID,
    FFM_Policy_ID,
    inbound_row_id;

CREATE CLUSTERED INDEX CX_cand_hits
    ON #candidate_hits (FFM_Enrollee_ID, FFM_Policy_ID, inbound_row_id);


-- =============================================================================
-- STEP D — Score candidates (preserve original ranking philosophy)
-- =============================================================================
-- Rank priority (lower is better) — same business meaning as original:
--   1 exact enrollee + policy (either inbound policy identifier)
--   2 same issuer + same status + same event date (Δ=0)
--   3 same issuer + same status + near date (Δ<=7)
--   4 same issuer + same status (any/nearer date)
--   5 same issuer only
--   6 different issuer + same status + Δ<=30
--   7 different issuer + same status
--   8 enrollee only
--
-- Status_Match_Flag:
--   Requires equal normalized status AND neither side is STATUS_MAPPING_REVIEW.
--   PENDING and PEND do not equal CONFIRM/CANCEL/TERM (not silently remapped).
--   Pend canceled stays STATUS_MAPPING_REVIEW — no invented business meaning.
-- =============================================================================
IF OBJECT_ID('tempdb..#candidates') IS NOT NULL DROP TABLE #candidates;

SELECT
    f.FFM_Coverage_Year,
    f.FFM_Enrollee_ID,
    f.FFM_Policy_ID,
    f.FFM_Issuer,
    f.plan_name,
    f.insurer_name,
    f.FFM_Enrollment_Status_Raw,
    f.FFM_Enrollee_Status_Raw,
    f.FFM_Status_Raw,
    f.FFM_Status_Norm,
    f.FFM_Event_Date,
    f.FFM_Benefit_Effective_Date,
    f.FFM_Benefit_End_Date,
    f.FFM_Create_Date,
    f.FFM_Last_Update_Date,
    f.household_id,
    f.person_type,
    f.relationship_type,
    f.FFM_Source,

    i.Inbound_Member_ID,
    i.Inbound_Issuer_Individual_ID,
    i.Inbound_Exchange_Assigned_Enrollee_ID,
    h.FFM_Enrollee_ID                                            AS Matched_Inbound_ID,
    h.Matched_Inbound_ID_Type,

    i.Inbound_Policy_ID,
    i.Inbound_Health_Coverage_Policy_No,
    CASE
        WHEN f.FFM_Policy_ID = i.Inbound_Policy_ID
         AND f.FFM_Policy_ID = i.Inbound_Health_Coverage_Policy_No
            THEN i.Inbound_Policy_ID
        WHEN f.FFM_Policy_ID = i.Inbound_Policy_ID
            THEN i.Inbound_Policy_ID
        WHEN f.FFM_Policy_ID = i.Inbound_Health_Coverage_Policy_No
            THEN i.Inbound_Health_Coverage_Policy_No
        ELSE COALESCE(i.Inbound_Policy_ID, i.Inbound_Health_Coverage_Policy_No)
    END                                                          AS Matched_Inbound_Policy_ID,
    CASE
        WHEN f.FFM_Policy_ID = i.Inbound_Policy_ID
         AND f.FFM_Policy_ID = i.Inbound_Health_Coverage_Policy_No
            THEN 'BOTH'
        WHEN f.FFM_Policy_ID = i.Inbound_Policy_ID
            THEN 'POLICY_ID'
        WHEN f.FFM_Policy_ID = i.Inbound_Health_Coverage_Policy_No
            THEN 'HEALTH_COVERAGE_POLICY_NO'
        ELSE 'NONE'
    END                                                          AS Policy_Match_Type,

    i.Inbound_Issuer,
    i.Inbound_Coverage_Year,
    i.Inbound_Status_Raw,
    i.Inbound_Status_Norm,
    i.Inbound_Event_Date,
    i.member_maint_effective_date,
    i.Inbound_File_Date,
    i.Folder_Year,
    i.Folder_Month,
    i.Source_File,
    i.Inbound_Household_Or_Case_ID,
    i.Inbound_Relationship,

    CASE
        WHEN f.FFM_Policy_ID = i.Inbound_Policy_ID
          OR f.FFM_Policy_ID = i.Inbound_Health_Coverage_Policy_No
            THEN 'YES'
        ELSE 'NO'
    END                                                          AS Policy_Match_Flag,
    CASE WHEN f.FFM_Issuer = i.Inbound_Issuer THEN 'YES' ELSE 'NO' END
                                                                 AS Issuer_Match_Flag,
    CASE
        WHEN f.FFM_Status_Norm = i.Inbound_Status_Norm
         AND f.FFM_Status_Norm NOT IN ('STATUS_MAPPING_REVIEW', 'PENDING', 'PEND')
         AND i.Inbound_Status_Norm <> 'STATUS_MAPPING_REVIEW'
            THEN 'YES'
        ELSE 'NO'
    END                                                          AS Status_Match_Flag,
    CASE
        WHEN f.FFM_Event_Date IS NOT NULL AND i.Inbound_Event_Date IS NOT NULL
            THEN ABS(DATEDIFF(day, f.FFM_Event_Date, i.Inbound_Event_Date))
    END                                                          AS Date_Difference_Days,

    CASE
        WHEN f.FFM_Policy_ID = i.Inbound_Policy_ID
          OR f.FFM_Policy_ID = i.Inbound_Health_Coverage_Policy_No
            THEN 1
        WHEN f.FFM_Issuer = i.Inbound_Issuer
         AND f.FFM_Status_Norm = i.Inbound_Status_Norm
         AND f.FFM_Status_Norm NOT IN ('STATUS_MAPPING_REVIEW', 'PENDING', 'PEND')
         AND i.Inbound_Status_Norm <> 'STATUS_MAPPING_REVIEW'
         AND f.FFM_Event_Date IS NOT NULL
         AND i.Inbound_Event_Date IS NOT NULL
         AND ABS(DATEDIFF(day, f.FFM_Event_Date, i.Inbound_Event_Date)) = 0
            THEN 2
        WHEN f.FFM_Issuer = i.Inbound_Issuer
         AND f.FFM_Status_Norm = i.Inbound_Status_Norm
         AND f.FFM_Status_Norm NOT IN ('STATUS_MAPPING_REVIEW', 'PENDING', 'PEND')
         AND i.Inbound_Status_Norm <> 'STATUS_MAPPING_REVIEW'
         AND f.FFM_Event_Date IS NOT NULL
         AND i.Inbound_Event_Date IS NOT NULL
         AND ABS(DATEDIFF(day, f.FFM_Event_Date, i.Inbound_Event_Date)) <= 7
            THEN 3
        WHEN f.FFM_Issuer = i.Inbound_Issuer
         AND f.FFM_Status_Norm = i.Inbound_Status_Norm
         AND f.FFM_Status_Norm NOT IN ('STATUS_MAPPING_REVIEW', 'PENDING', 'PEND')
         AND i.Inbound_Status_Norm <> 'STATUS_MAPPING_REVIEW'
            THEN 4
        WHEN f.FFM_Issuer = i.Inbound_Issuer
            THEN 5
        WHEN f.FFM_Status_Norm = i.Inbound_Status_Norm
         AND f.FFM_Status_Norm NOT IN ('STATUS_MAPPING_REVIEW', 'PENDING', 'PEND')
         AND i.Inbound_Status_Norm <> 'STATUS_MAPPING_REVIEW'
         AND f.FFM_Event_Date IS NOT NULL
         AND i.Inbound_Event_Date IS NOT NULL
         AND ABS(DATEDIFF(day, f.FFM_Event_Date, i.Inbound_Event_Date)) <= 30
            THEN 6
        WHEN f.FFM_Status_Norm = i.Inbound_Status_Norm
         AND f.FFM_Status_Norm NOT IN ('STATUS_MAPPING_REVIEW', 'PENDING', 'PEND')
         AND i.Inbound_Status_Norm <> 'STATUS_MAPPING_REVIEW'
            THEN 7
        ELSE 8
    END                                                          AS rank_priority,
    i.inbound_row_id
INTO #candidates
FROM #candidate_hits AS h
INNER JOIN #ffm AS f
    ON f.FFM_Coverage_Year = h.FFM_Coverage_Year
   AND f.FFM_Enrollee_ID   = h.FFM_Enrollee_ID
   AND f.FFM_Policy_ID     = h.FFM_Policy_ID
INNER JOIN #inbound AS i
    ON i.inbound_row_id = h.inbound_row_id;

CREATE CLUSTERED INDEX CX_candidates
    ON #candidates (FFM_Enrollee_ID, FFM_Policy_ID, rank_priority, inbound_row_id);


-- =============================================================================
-- STEP E — Best inbound candidate per FFM enrollee-policy pair
-- =============================================================================
IF OBJECT_ID('tempdb..#best') IS NOT NULL DROP TABLE #best;

SELECT *
INTO #best
FROM (
    SELECT
        c.*,
        ROW_NUMBER() OVER (
            PARTITION BY c.FFM_Coverage_Year, c.FFM_Enrollee_ID, c.FFM_Policy_ID
            ORDER BY
                c.rank_priority ASC,
                CASE WHEN c.Date_Difference_Days IS NULL THEN 999999 ELSE c.Date_Difference_Days END ASC,
                c.inbound_row_id DESC
        ) AS rn
    FROM #candidates AS c
) AS x
WHERE x.rn = 1;

CREATE CLUSTERED INDEX CX_best ON #best (FFM_Enrollee_ID, FFM_Policy_ID);


-- =============================================================================
-- STEP F — #final_results (left join so unmatched FFM pairs are retained)
-- =============================================================================
IF OBJECT_ID('tempdb..#final_results') IS NOT NULL DROP TABLE #final_results;

SELECT
    f.FFM_Coverage_Year,
    f.FFM_Enrollee_ID,
    f.FFM_Policy_ID,
    f.FFM_Issuer,
    f.plan_name,
    f.insurer_name,
    f.FFM_Enrollment_Status_Raw,
    f.FFM_Enrollee_Status_Raw,
    f.FFM_Status_Raw,
    f.FFM_Status_Norm,
    f.FFM_Event_Date,
    f.FFM_Benefit_Effective_Date,
    f.FFM_Benefit_End_Date,
    f.FFM_Create_Date,
    f.FFM_Last_Update_Date,
    f.household_id,
    f.person_type,
    f.relationship_type,
    f.FFM_Source,

    b.Inbound_Member_ID,
    b.Inbound_Issuer_Individual_ID,
    b.Inbound_Exchange_Assigned_Enrollee_ID,
    b.Matched_Inbound_ID,
    b.Matched_Inbound_ID_Type,

    b.Inbound_Policy_ID,
    b.Inbound_Health_Coverage_Policy_No,
    b.Matched_Inbound_Policy_ID,
    COALESCE(b.Policy_Match_Type, 'NONE')                        AS Policy_Match_Type,

    b.Inbound_Issuer,
    b.Inbound_Coverage_Year,
    b.Inbound_Status_Raw,
    b.Inbound_Status_Norm,
    b.Inbound_Event_Date,
    b.member_maint_effective_date,
    b.Inbound_File_Date,
    b.Folder_Year,
    b.Folder_Month,
    b.Source_File,
    b.Inbound_Household_Or_Case_ID,
    b.Inbound_Relationship,

    COALESCE(b.Policy_Match_Flag, 'NO')                          AS Policy_Match_Flag,
    COALESCE(b.Issuer_Match_Flag, 'NO')                          AS Issuer_Match_Flag,
    COALESCE(b.Status_Match_Flag, 'NO')                          AS Status_Match_Flag,
    b.Date_Difference_Days,

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
        WHEN b.Matched_Inbound_ID IS NOT NULL
            THEN 'ENROLLEE_FOUND_DIFFERENT_LIFECYCLE'
        ELSE 'NO_INBOUND_ENROLLEE_EVIDENCE'
    END                                                          AS Match_Level,

    CASE
        WHEN b.FFM_Enrollee_ID IS NULL THEN 'NO_MATCH'
        WHEN b.Policy_Match_Flag = 'YES' THEN 'VERY_STRONG'
        WHEN b.Issuer_Match_Flag = 'YES'
         AND b.Status_Match_Flag = 'YES'
         AND b.Date_Difference_Days IS NOT NULL
         AND b.Date_Difference_Days <= 7
            THEN 'VERY_STRONG'
        WHEN b.Issuer_Match_Flag = 'YES'
         AND b.Status_Match_Flag = 'YES'
         AND b.Date_Difference_Days IS NOT NULL
         AND b.Date_Difference_Days <= 30
            THEN 'STRONG'
        WHEN b.Issuer_Match_Flag = 'NO'
         AND b.Status_Match_Flag = 'YES'
            THEN 'CROSS_ISSUER'
        WHEN b.Matched_Inbound_ID IS NOT NULL THEN 'WEAK'
        ELSE 'NO_MATCH'
    END                                                          AS Match_Score,

    CASE
        WHEN b.FFM_Enrollee_ID IS NULL THEN 'NO_INBOUND_EVIDENCE'
        WHEN b.Policy_Match_Flag = 'YES' THEN 'EXACT_POLICY_MATCH'
        WHEN b.Issuer_Match_Flag = 'YES'
         AND b.Status_Match_Flag = 'YES'
         AND b.Date_Difference_Days IS NOT NULL
         AND b.Date_Difference_Days <= 30
            THEN 'POTENTIAL_POLICY_IDENTIFIER_MISMATCH'
        WHEN b.Issuer_Match_Flag = 'YES'
         AND b.Policy_Match_Flag = 'NO'
            THEN 'SAME_ISSUER_DIFFERENT_POLICY'
        WHEN b.Issuer_Match_Flag = 'NO'
         AND b.Status_Match_Flag = 'YES'
            THEN 'CROSS_ISSUER_TRANSITION'
        WHEN b.Matched_Inbound_ID IS NOT NULL THEN 'DIFFERENT_LIFECYCLE'
        ELSE 'NO_INBOUND_EVIDENCE'
    END                                                          AS Root_Cause_Category
INTO #final_results
FROM #ffm AS f
LEFT JOIN #best AS b
    ON f.FFM_Coverage_Year = b.FFM_Coverage_Year
   AND f.FFM_Enrollee_ID   = b.FFM_Enrollee_ID
   AND f.FFM_Policy_ID     = b.FFM_Policy_ID;

CREATE CLUSTERED INDEX CX_final
    ON #final_results (FFM_Issuer, Match_Level, FFM_Enrollee_ID, FFM_Policy_ID);


-- =============================================================================
-- RESULT SET 1 — POPULATION CONTROL
-- =============================================================================
SELECT
    'ALL' AS slice,
    COUNT(*) AS total_ffm_enrollee_policy_pairs,
    COUNT(DISTINCT FFM_Enrollee_ID) AS distinct_enrollees,
    COUNT(DISTINCT FFM_Policy_ID) AS distinct_policies,
    COUNT(DISTINCT FFM_Issuer) AS distinct_issuers
FROM #final_results

UNION ALL

SELECT
    CONCAT(
        'enrollment=', COALESCE(FFM_Enrollment_Status_Raw, '<NULL>'),
        ' | enrollee=', COALESCE(FFM_Enrollee_Status_Raw, '<NULL>')
    ) AS slice,
    COUNT(*) AS total_ffm_enrollee_policy_pairs,
    COUNT(DISTINCT FFM_Enrollee_ID) AS distinct_enrollees,
    COUNT(DISTINCT FFM_Policy_ID) AS distinct_policies,
    COUNT(DISTINCT FFM_Issuer) AS distinct_issuers
FROM #final_results
GROUP BY
    FFM_Enrollment_Status_Raw,
    FFM_Enrollee_Status_Raw
ORDER BY
    CASE WHEN slice = 'ALL' THEN 0 ELSE 1 END,
    total_ffm_enrollee_policy_pairs DESC;


-- =============================================================================
-- RESULT SET 2 — MATCH LEVEL SUMMARY
-- =============================================================================
SELECT
    Match_Level,
    COUNT(*) AS Distinct_FFM_Pairs,
    COUNT(DISTINCT FFM_Enrollee_ID) AS Distinct_Enrollees,
    COUNT(DISTINCT FFM_Policy_ID) AS Distinct_Policies,
    CAST(100.0 * COUNT(*) / NULLIF(SUM(COUNT(*)) OVER (), 0) AS DECIMAL(8, 2)) AS Percentage
FROM #final_results
GROUP BY Match_Level
ORDER BY Distinct_FFM_Pairs DESC;


-- =============================================================================
-- RESULT SET 3 — ROOT CAUSE SUMMARY
-- =============================================================================
SELECT
    Root_Cause_Category,
    COUNT(*) AS Distinct_FFM_Pairs,
    COUNT(DISTINCT FFM_Enrollee_ID) AS Distinct_Enrollees,
    COUNT(DISTINCT FFM_Policy_ID) AS Distinct_FFM_Policies,
    COUNT(DISTINCT Matched_Inbound_Policy_ID) AS Distinct_Inbound_Policies,
    CAST(100.0 * COUNT(*) / NULLIF(SUM(COUNT(*)) OVER (), 0) AS DECIMAL(8, 2)) AS Percentage
FROM #final_results
GROUP BY Root_Cause_Category
ORDER BY Distinct_FFM_Pairs DESC;


-- =============================================================================
-- RESULT SET 4 — ISSUER SUMMARY
-- =============================================================================
SELECT
    FFM_Issuer,
    COUNT(*) AS Total_FFM_Pairs,
    SUM(CASE WHEN Match_Level = 'EXACT_ENROLLEE_POLICY_MATCH' THEN 1 ELSE 0 END)
        AS Exact_Matches,
    SUM(CASE WHEN Match_Level = 'SAME_TRANSACTION_DIFFERENT_POLICY' THEN 1 ELSE 0 END)
        AS Same_Transaction_Different_Policy,
    SUM(CASE WHEN Match_Level = 'SAME_LIFECYCLE_DIFFERENT_POLICY' THEN 1 ELSE 0 END)
        AS Same_Lifecycle_Different_Policy,
    SUM(CASE WHEN Match_Level = 'CROSS_ISSUER_TRANSITION' THEN 1 ELSE 0 END)
        AS Cross_Issuer_Transition,
    SUM(CASE WHEN Match_Level = 'ENROLLEE_FOUND_DIFFERENT_LIFECYCLE' THEN 1 ELSE 0 END)
        AS Different_Lifecycle,
    SUM(CASE WHEN Match_Level = 'NO_INBOUND_ENROLLEE_EVIDENCE' THEN 1 ELSE 0 END)
        AS No_Inbound_Evidence,
    CAST(100.0 * SUM(CASE WHEN Match_Level = 'EXACT_ENROLLEE_POLICY_MATCH' THEN 1 ELSE 0 END)
         / NULLIF(COUNT(*), 0) AS DECIMAL(8, 2)) AS Pct_Exact,
    CAST(100.0 * SUM(CASE WHEN Match_Level = 'NO_INBOUND_ENROLLEE_EVIDENCE' THEN 1 ELSE 0 END)
         / NULLIF(COUNT(*), 0) AS DECIMAL(8, 2)) AS Pct_No_Inbound
FROM #final_results
GROUP BY FFM_Issuer
ORDER BY Total_FFM_Pairs DESC;


-- =============================================================================
-- RESULT SET 5 — FULL DETAIL
-- =============================================================================
SELECT
    FFM_Coverage_Year,
    FFM_Enrollee_ID,
    FFM_Policy_ID,
    FFM_Issuer,
    plan_name,
    insurer_name,
    FFM_Enrollment_Status_Raw,
    FFM_Enrollee_Status_Raw,
    FFM_Status_Raw,
    FFM_Status_Norm,
    FFM_Event_Date,
    FFM_Benefit_Effective_Date,
    FFM_Benefit_End_Date,
    FFM_Create_Date,
    FFM_Last_Update_Date,
    household_id,
    person_type,
    relationship_type,
    FFM_Source,
    Inbound_Member_ID,
    Inbound_Issuer_Individual_ID,
    Inbound_Exchange_Assigned_Enrollee_ID,
    Matched_Inbound_ID,
    Matched_Inbound_ID_Type,
    Inbound_Policy_ID,
    Inbound_Health_Coverage_Policy_No,
    Matched_Inbound_Policy_ID,
    Policy_Match_Type,
    Inbound_Issuer,
    Inbound_Coverage_Year,
    Inbound_Status_Raw,
    Inbound_Status_Norm,
    Inbound_Event_Date,
    member_maint_effective_date,
    Inbound_File_Date,
    Folder_Year,
    Folder_Month,
    Source_File,
    Inbound_Household_Or_Case_ID,
    Inbound_Relationship,
    Policy_Match_Flag,
    Issuer_Match_Flag,
    Status_Match_Flag,
    Date_Difference_Days,
    Match_Level,
    Match_Score,
    Root_Cause_Category
FROM #final_results
ORDER BY
    CASE Root_Cause_Category
        WHEN 'EXACT_POLICY_MATCH' THEN 1
        WHEN 'POTENTIAL_POLICY_IDENTIFIER_MISMATCH' THEN 2
        WHEN 'SAME_ISSUER_DIFFERENT_POLICY' THEN 3
        WHEN 'CROSS_ISSUER_TRANSITION' THEN 4
        WHEN 'DIFFERENT_LIFECYCLE' THEN 5
        ELSE 6
    END,
    FFM_Issuer,
    FFM_Enrollee_ID,
    FFM_Policy_ID;


-- =============================================================================
-- RESULT SET 6 — NO INBOUND DETAIL (later RCNI Phase 2 input)
-- =============================================================================
SELECT
    FFM_Coverage_Year,
    FFM_Enrollee_ID,
    FFM_Policy_ID,
    FFM_Issuer,
    plan_name,
    insurer_name,
    FFM_Enrollment_Status_Raw,
    FFM_Enrollee_Status_Raw,
    FFM_Status_Raw,
    FFM_Status_Norm,
    FFM_Event_Date,
    FFM_Benefit_Effective_Date,
    FFM_Benefit_End_Date,
    FFM_Create_Date,
    FFM_Last_Update_Date,
    household_id,
    person_type,
    relationship_type,
    FFM_Source,
    Match_Level,
    Match_Score,
    Root_Cause_Category
FROM #final_results
WHERE Match_Level = 'NO_INBOUND_ENROLLEE_EVIDENCE'
ORDER BY FFM_Issuer, FFM_Enrollee_ID, FFM_Policy_ID;


-- =============================================================================
-- RESULT SET 7 — SAME ENROLLEE / DIFFERENT POLICY
-- =============================================================================
SELECT
    FFM_Coverage_Year,
    FFM_Enrollee_ID,
    FFM_Policy_ID,
    FFM_Issuer,
    FFM_Enrollment_Status_Raw,
    FFM_Enrollee_Status_Raw,
    FFM_Status_Norm,
    FFM_Event_Date,
    Inbound_Member_ID,
    Inbound_Issuer_Individual_ID,
    Inbound_Exchange_Assigned_Enrollee_ID,
    Matched_Inbound_ID,
    Matched_Inbound_ID_Type,
    Inbound_Policy_ID,
    Inbound_Health_Coverage_Policy_No,
    Matched_Inbound_Policy_ID,
    Policy_Match_Type,
    Inbound_Issuer,
    Inbound_Status_Raw,
    Inbound_Status_Norm,
    Inbound_Event_Date,
    member_maint_effective_date,
    Date_Difference_Days,
    Folder_Year,
    Folder_Month,
    Source_File,
    Policy_Match_Flag,
    Issuer_Match_Flag,
    Status_Match_Flag,
    Match_Level,
    Match_Score,
    Root_Cause_Category
FROM #final_results
WHERE Match_Level IN (
    'SAME_TRANSACTION_DIFFERENT_POLICY',
    'SAME_LIFECYCLE_DIFFERENT_POLICY'
)
ORDER BY
    Match_Level,
    Date_Difference_Days,
    FFM_Issuer,
    FFM_Enrollee_ID;


-- =============================================================================
-- RESULT SET 8 — CROSS ISSUER
-- =============================================================================
SELECT
    FFM_Enrollee_ID,
    FFM_Issuer,
    FFM_Policy_ID,
    Inbound_Issuer,
    Inbound_Policy_ID,
    Inbound_Health_Coverage_Policy_No,
    Matched_Inbound_Policy_ID,
    Policy_Match_Type,
    FFM_Enrollment_Status_Raw,
    FFM_Enrollee_Status_Raw,
    FFM_Status_Norm,
    Inbound_Status_Raw,
    Inbound_Status_Norm,
    FFM_Event_Date,
    Inbound_Event_Date,
    Date_Difference_Days,
    Matched_Inbound_ID,
    Matched_Inbound_ID_Type,
    Source_File,
    Folder_Year,
    Folder_Month,
    Match_Level,
    Match_Score,
    Root_Cause_Category
FROM #final_results
WHERE Match_Level = 'CROSS_ISSUER_TRANSITION'
ORDER BY
    FFM_Issuer,
    Inbound_Issuer,
    Date_Difference_Days,
    FFM_Enrollee_ID;


-- =============================================================================
-- Cleanup (optional — session end also drops temp objects)
-- =============================================================================
-- DROP TABLE IF EXISTS #final_results;
-- DROP TABLE IF EXISTS #best;
-- DROP TABLE IF EXISTS #candidates;
-- DROP TABLE IF EXISTS #candidate_hits;
-- DROP TABLE IF EXISTS #inbound;
-- DROP TABLE IF EXISTS #ffm;
