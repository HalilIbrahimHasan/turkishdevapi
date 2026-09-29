    -- =============================================================================
    -- DIAGNOSTIC — 13,006 NO_INBOUND classification difference
    -- =============================================================================
    -- Compares, independently:
    --   A) ORIGINAL_FORWARD_CLASSIFICATION
    --      Exact candidate-generation, ranking, and NO_INBOUND logic from
    --      scenario_b_2026_834_row_level_reconciliation.sql.
    --
    --   B) NEW_EXPORT_CLASSIFICATION
    --      Exact enrollee-evidence logic from
    --      export_2026_no_inbound_enrollee_evidence.sql.
    --
    -- Material source-code difference identified before execution:
    --   The original forward query has NO inbound coverage_year filter.
    --   The new export restricts inbound to coverage_year IN (2025, 2026).
    --
    -- Other line-by-line findings:
    --   * Both SELECT expressions normalize each inbound enrollee identifier as
    --     NULLIF(LTRIM(RTRIM(CAST(identifier AS VARCHAR(100)))), '').
    --   * Both compare the VARCHAR(100) FFM enrollee ID independently to member_id,
    --     issuer_indiv_identifier, and exchg_assigned_enrollee_id.
    --   * The original has no issuer-only or policy-only candidate path.
    --   * Policy, issuer, status, and date are used only after an enrollee candidate
    --     exists, for best-candidate ranking and Match_Level classification.
    --   * folder_year is output metadata only; it does not filter or create hits.
    --
    -- Safety:
    --   READ ONLY on permanent tables. Temp tables/indexes only. No RCNI.
    --   Neither reconciliation query is modified.
    -- =============================================================================

    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @coverage_year INT = 2026;
    DECLARE @expected_target BIGINT = 960531;
    DECLARE @expected_original_no_inbound BIGINT = 109776;
    DECLARE @expected_new_no_inbound BIGINT = 122782;
    DECLARE @expected_difference BIGINT = 13006;

    DECLARE @t0 DATETIME2 = SYSDATETIME();
    DECLARE @msg NVARCHAR(400);


    -- =============================================================================
    -- A1 — ORIGINAL forward target population
    -- =============================================================================
    RAISERROR('DIAGNOSTIC A1: build original forward target', 10, 1) WITH NOWAIT;

    IF OBJECT_ID('tempdb..#original_target') IS NOT NULL DROP TABLE #original_target;

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
    INTO #original_target
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
                ORDER BY
                    e.enrollment_last_update_date DESC,
                    e.enrollment_create_date DESC
            ) AS _rn
        FROM dbo.Enrollments_TEST AS e
        WHERE e.coverage_year = @coverage_year
        AND UPPER(LTRIM(RTRIM(e.enrollment_status_description))) IN ('ENROLLED', 'PENDING')
    ) AS e
    WHERE e._rn = 1;

    CREATE UNIQUE CLUSTERED INDEX CX_original_target
        ON #original_target (FFM_Coverage_Year, FFM_Policy_ID, FFM_Enrollee_ID);
    CREATE NONCLUSTERED INDEX IX_original_target_enrollee
        ON #original_target (FFM_Enrollee_ID)
        INCLUDE (FFM_Policy_ID, FFM_Issuer, FFM_Status_Norm, FFM_Event_Date);

    DECLARE @original_target_count BIGINT = (SELECT COUNT_BIG(*) FROM #original_target);

    IF @original_target_count <> @expected_target
    BEGIN
        RAISERROR(
            'DIAGNOSTIC STOP: original target=%I64d; expected %I64d.',
            16, 1, @original_target_count, @expected_target
        );
        RETURN;
    END;


    -- =============================================================================
    -- A2 — ORIGINAL inbound working set: intentionally ALL coverage years
    -- =============================================================================
    -- IMPORTANT: This WHERE clause is copied from the original forward query.
    -- It has no coverage_year restriction.
    -- =============================================================================
    RAISERROR('DIAGNOSTIC A2: stage original all-year inbound working set', 10, 1) WITH NOWAIT;

    IF OBJECT_ID('tempdb..#original_inbound') IS NOT NULL DROP TABLE #original_inbound;

    SELECT
        ia.id AS inbound_row_id,
        NULLIF(LTRIM(RTRIM(CAST(ia.member_id AS VARCHAR(100)))), '')
            AS Inbound_Member_ID,
        NULLIF(LTRIM(RTRIM(CAST(ia.issuer_indiv_identifier AS VARCHAR(100)))), '')
            AS Inbound_Issuer_Indiv_Identifier,
        NULLIF(LTRIM(RTRIM(CAST(ia.exchg_assigned_enrollee_id AS VARCHAR(100)))), '')
            AS Inbound_Exchange_Assigned_Enrollee_ID,
        NULLIF(LTRIM(RTRIM(CAST(ia.policy_id AS VARCHAR(100)))), '')
            AS Inbound_Policy_ID,
        NULLIF(LTRIM(RTRIM(CAST(ia.health_coverage_policy_no AS VARCHAR(100)))), '')
            AS Inbound_Health_Coverage_Policy_No,
        CAST(ia.issuer AS VARCHAR(20)) AS Inbound_Issuer,
        ia.coverage_year AS Inbound_Coverage_Year,
        ia.enrolleeStatus AS Inbound_Status_Raw,
        CASE
            WHEN UPPER(LTRIM(RTRIM(ia.enrolleeStatus))) = 'CONFIRM' THEN 'CONFIRM'
            WHEN UPPER(LTRIM(RTRIM(ia.enrolleeStatus))) = 'CANCEL'  THEN 'CANCEL'
            WHEN UPPER(LTRIM(RTRIM(ia.enrolleeStatus))) = 'TERM'    THEN 'TERM'
            ELSE 'STATUS_MAPPING_REVIEW'
        END AS Inbound_Status_Normalized,
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
        ia.source_file AS Inbound_Source_File
    INTO #original_inbound
    FROM dbo.inbound_automation AS ia
    WHERE NULLIF(LTRIM(RTRIM(ia.member_id)), '') IS NOT NULL
    OR NULLIF(LTRIM(RTRIM(ia.issuer_indiv_identifier)), '') IS NOT NULL
    OR NULLIF(LTRIM(RTRIM(ia.exchg_assigned_enrollee_id)), '') IS NOT NULL;

    CREATE UNIQUE CLUSTERED INDEX CX_original_inbound
        ON #original_inbound (inbound_row_id);
    CREATE NONCLUSTERED INDEX IX_original_member
        ON #original_inbound (Inbound_Member_ID)
        INCLUDE (
            Inbound_Policy_ID,
            Inbound_Health_Coverage_Policy_No,
            Inbound_Issuer,
            Inbound_Event_Date,
            Inbound_Status_Normalized
        );
    CREATE NONCLUSTERED INDEX IX_original_issuer_indiv
        ON #original_inbound (Inbound_Issuer_Indiv_Identifier)
        INCLUDE (
            Inbound_Policy_ID,
            Inbound_Health_Coverage_Policy_No,
            Inbound_Issuer,
            Inbound_Event_Date,
            Inbound_Status_Normalized
        );
    CREATE NONCLUSTERED INDEX IX_original_exchange
        ON #original_inbound (Inbound_Exchange_Assigned_Enrollee_ID)
        INCLUDE (
            Inbound_Policy_ID,
            Inbound_Health_Coverage_Policy_No,
            Inbound_Issuer,
            Inbound_Event_Date,
            Inbound_Status_Normalized
        );


    -- =============================================================================
    -- A3 — ORIGINAL candidate generation: exactly three enrollee-ID paths
    -- =============================================================================
    IF OBJECT_ID('tempdb..#original_candidate_hits') IS NOT NULL DROP TABLE #original_candidate_hits;

    ;WITH hit_raw AS (
        SELECT
            t.FFM_Coverage_Year,
            t.FFM_Policy_ID,
            t.FFM_Enrollee_ID,
            i.inbound_row_id,
            CAST('MEMBER_ID' AS VARCHAR(40)) AS hit_type
        FROM #original_target AS t
        INNER JOIN #original_inbound AS i
            ON i.Inbound_Member_ID = t.FFM_Enrollee_ID

        UNION ALL

        SELECT
            t.FFM_Coverage_Year,
            t.FFM_Policy_ID,
            t.FFM_Enrollee_ID,
            i.inbound_row_id,
            CAST('ISSUER_INDIV_IDENTIFIER' AS VARCHAR(40))
        FROM #original_target AS t
        INNER JOIN #original_inbound AS i
            ON i.Inbound_Issuer_Indiv_Identifier = t.FFM_Enrollee_ID

        UNION ALL

        SELECT
            t.FFM_Coverage_Year,
            t.FFM_Policy_ID,
            t.FFM_Enrollee_ID,
            i.inbound_row_id,
            CAST('EXCHG_ASSIGNED_ENROLLEE_ID' AS VARCHAR(40))
        FROM #original_target AS t
        INNER JOIN #original_inbound AS i
            ON i.Inbound_Exchange_Assigned_Enrollee_ID = t.FFM_Enrollee_ID
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
    INTO #original_candidate_hits
    FROM hit_raw
    GROUP BY
        FFM_Coverage_Year,
        FFM_Policy_ID,
        FFM_Enrollee_ID,
        inbound_row_id;

    CREATE CLUSTERED INDEX CX_original_hits
        ON #original_candidate_hits (FFM_Enrollee_ID, FFM_Policy_ID, inbound_row_id);


    -- =============================================================================
    -- A4 — ORIGINAL candidate scoring and best-candidate selection
    -- =============================================================================
    IF OBJECT_ID('tempdb..#original_candidates') IS NOT NULL DROP TABLE #original_candidates;

    SELECT
        t.FFM_Coverage_Year,
        t.FFM_Policy_ID,
        t.FFM_Enrollee_ID,
        t.FFM_Issuer,
        t.FFM_Enrollment_Status,
        t.FFM_Enrollee_Status,
        t.FFM_Status_Norm,
        t.FFM_Event_Date,
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
        i.folder_year,
        i.Inbound_Source_File,
        CASE
            WHEN t.FFM_Policy_ID = i.Inbound_Policy_ID
            OR t.FFM_Policy_ID = i.Inbound_Health_Coverage_Policy_No THEN 'YES'
            ELSE 'NO'
        END AS Policy_Match_Flag,
        CASE
            WHEN t.FFM_Issuer = i.Inbound_Issuer THEN 'YES'
            ELSE 'NO'
        END AS Issuer_Match_Flag,
        CASE
            WHEN t.FFM_Status_Norm = 'CONFIRM'
            AND i.Inbound_Status_Normalized = 'CONFIRM' THEN 'YES'
            ELSE 'NO'
        END AS Status_Match_Flag,
        CASE
            WHEN t.FFM_Event_Date IS NOT NULL
            AND i.Inbound_Event_Date IS NOT NULL
                THEN ABS(DATEDIFF(day, t.FFM_Event_Date, i.Inbound_Event_Date))
        END AS Date_Difference_Days,
        CASE
            WHEN t.FFM_Policy_ID = i.Inbound_Policy_ID
            OR t.FFM_Policy_ID = i.Inbound_Health_Coverage_Policy_No THEN 1
            WHEN t.FFM_Issuer = i.Inbound_Issuer
            AND t.FFM_Status_Norm = 'CONFIRM'
            AND i.Inbound_Status_Normalized = 'CONFIRM'
            AND t.FFM_Event_Date IS NOT NULL
            AND i.Inbound_Event_Date IS NOT NULL
            AND ABS(DATEDIFF(day, t.FFM_Event_Date, i.Inbound_Event_Date)) = 0 THEN 2
            WHEN t.FFM_Issuer = i.Inbound_Issuer
            AND t.FFM_Status_Norm = 'CONFIRM'
            AND i.Inbound_Status_Normalized = 'CONFIRM'
            AND t.FFM_Event_Date IS NOT NULL
            AND i.Inbound_Event_Date IS NOT NULL
            AND ABS(DATEDIFF(day, t.FFM_Event_Date, i.Inbound_Event_Date)) <= 7 THEN 3
            WHEN t.FFM_Issuer = i.Inbound_Issuer
            AND t.FFM_Status_Norm = 'CONFIRM'
            AND i.Inbound_Status_Normalized = 'CONFIRM' THEN 4
            WHEN t.FFM_Issuer = i.Inbound_Issuer THEN 5
            WHEN t.FFM_Status_Norm = 'CONFIRM'
            AND i.Inbound_Status_Normalized = 'CONFIRM'
            AND t.FFM_Event_Date IS NOT NULL
            AND i.Inbound_Event_Date IS NOT NULL
            AND ABS(DATEDIFF(day, t.FFM_Event_Date, i.Inbound_Event_Date)) <= 30 THEN 6
            WHEN t.FFM_Status_Norm = 'CONFIRM'
            AND i.Inbound_Status_Normalized = 'CONFIRM' THEN 7
            ELSE 8
        END AS rank_priority,
        i.inbound_row_id
    INTO #original_candidates
    FROM #original_candidate_hits AS h
    INNER JOIN #original_target AS t
        ON t.FFM_Coverage_Year = h.FFM_Coverage_Year
    AND t.FFM_Policy_ID = h.FFM_Policy_ID
    AND t.FFM_Enrollee_ID = h.FFM_Enrollee_ID
    INNER JOIN #original_inbound AS i
        ON i.inbound_row_id = h.inbound_row_id;

    CREATE CLUSTERED INDEX CX_original_candidates
        ON #original_candidates (
            FFM_Enrollee_ID,
            FFM_Policy_ID,
            rank_priority,
            inbound_row_id
        );

    IF OBJECT_ID('tempdb..#original_best') IS NOT NULL DROP TABLE #original_best;

    SELECT *
    INTO #original_best
    FROM (
        SELECT
            c.*,
            ROW_NUMBER() OVER (
                PARTITION BY c.FFM_Coverage_Year, c.FFM_Policy_ID, c.FFM_Enrollee_ID
                ORDER BY
                    c.rank_priority ASC,
                    CASE
                        WHEN c.Date_Difference_Days IS NULL THEN 999999
                        ELSE c.Date_Difference_Days
                    END ASC,
                    c.inbound_row_id DESC
            ) AS rn
        FROM #original_candidates AS c
    ) AS x
    WHERE x.rn = 1;

    CREATE UNIQUE CLUSTERED INDEX CX_original_best
        ON #original_best (FFM_Coverage_Year, FFM_Policy_ID, FFM_Enrollee_ID);


    -- =============================================================================
    -- A5 — ORIGINAL_FORWARD_CLASSIFICATION
    -- =============================================================================
    IF OBJECT_ID('tempdb..#original_classification') IS NOT NULL DROP TABLE #original_classification;

    SELECT
        t.FFM_Coverage_Year,
        t.FFM_Issuer,
        t.FFM_Policy_ID,
        t.FFM_Enrollee_ID,
        t.FFM_Enrollment_Status,
        t.FFM_Enrollee_Status,
        CASE
            WHEN b.FFM_Enrollee_ID IS NULL THEN 'NO_INBOUND_ENROLLEE_EVIDENCE'
            ELSE 'HAS_INBOUND_EVIDENCE'
        END AS Original_Evidence_Classification,
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
        END AS Original_Match_Level,
        b.Matched_Inbound_ID_Type AS Original_Matched_Inbound_ID_Type,
        b.Inbound_Coverage_Year AS Original_Inbound_Coverage_Year,
        b.Inbound_Issuer AS Original_Inbound_Issuer,
        b.Inbound_Policy_ID AS Original_Inbound_Policy_ID,
        b.Inbound_Health_Coverage_Policy_No AS Original_Inbound_Health_Coverage_Policy_No,
        b.Inbound_Member_ID AS Original_Inbound_Member_ID,
        b.Inbound_Issuer_Indiv_Identifier AS Original_Inbound_Issuer_Indiv_Identifier,
        b.Inbound_Exchange_Assigned_Enrollee_ID
            AS Original_Inbound_Exchange_Assigned_Enrollee_ID,
        b.Inbound_Status_Raw AS Original_Inbound_Status,
        b.folder_year AS Original_Folder_Year,
        b.Inbound_Source_File AS Original_Source_File
    INTO #original_classification
    FROM #original_target AS t
    LEFT JOIN #original_best AS b
        ON t.FFM_Coverage_Year = b.FFM_Coverage_Year
    AND t.FFM_Policy_ID = b.FFM_Policy_ID
    AND t.FFM_Enrollee_ID = b.FFM_Enrollee_ID;

    CREATE UNIQUE CLUSTERED INDEX CX_original_classification
        ON #original_classification (
            FFM_Coverage_Year,
            FFM_Policy_ID,
            FFM_Enrollee_ID
        );

    DECLARE @original_no_inbound_count BIGINT = (
        SELECT COUNT_BIG(*)
        FROM #original_classification
        WHERE Original_Evidence_Classification = 'NO_INBOUND_ENROLLEE_EVIDENCE'
    );


    -- =============================================================================
    -- B1 — NEW export target population, built independently
    -- =============================================================================
    RAISERROR('DIAGNOSTIC B1: build new-export target independently', 10, 1) WITH NOWAIT;

    IF OBJECT_ID('tempdb..#new_target') IS NOT NULL DROP TABLE #new_target;

    SELECT
        e.coverage_year AS FFM_Coverage_Year,
        CAST(e.hios_issuer_id AS VARCHAR(20)) AS FFM_Issuer,
        CAST(e.enrollment_id AS VARCHAR(100)) AS FFM_Policy_ID,
        CAST(e.enrollee_id AS VARCHAR(100)) AS FFM_Enrollee_ID,
        e.enrollment_status_description AS FFM_Enrollment_Status,
        e.enrollee_status_description AS FFM_Enrollee_Status
    INTO #new_target
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

    CREATE UNIQUE CLUSTERED INDEX CX_new_target
        ON #new_target (FFM_Coverage_Year, FFM_Policy_ID, FFM_Enrollee_ID);
    CREATE NONCLUSTERED INDEX IX_new_target_enrollee
        ON #new_target (FFM_Enrollee_ID)
        INCLUDE (
            FFM_Issuer,
            FFM_Policy_ID,
            FFM_Enrollment_Status,
            FFM_Enrollee_Status
        );

    DECLARE @new_target_count BIGINT = (SELECT COUNT_BIG(*) FROM #new_target);

    IF @new_target_count <> @expected_target
    BEGIN
        RAISERROR(
            'DIAGNOSTIC STOP: new-export target=%I64d; expected %I64d.',
            16, 1, @new_target_count, @expected_target
        );
        RETURN;
    END;


    -- =============================================================================
    -- B2 — NEW export inbound stage: coverage_year IN (2025, 2026)
    -- =============================================================================
    RAISERROR('DIAGNOSTIC B2: stage new-export 2025/2026 inbound identifiers', 10, 1) WITH NOWAIT;

    IF OBJECT_ID('tempdb..#new_inbound_identifiers') IS NOT NULL DROP TABLE #new_inbound_identifiers;

    SELECT
        ia.id AS inbound_row_id,
        NULLIF(LTRIM(RTRIM(CAST(ia.member_id AS VARCHAR(100)))), '')
            AS Inbound_Member_ID,
        NULLIF(LTRIM(RTRIM(CAST(ia.issuer_indiv_identifier AS VARCHAR(100)))), '')
            AS Inbound_Issuer_Indiv_Identifier,
        NULLIF(LTRIM(RTRIM(CAST(ia.exchg_assigned_enrollee_id AS VARCHAR(100)))), '')
            AS Inbound_Exchange_Assigned_Enrollee_ID
    INTO #new_inbound_identifiers
    FROM dbo.inbound_automation AS ia
    WHERE ia.coverage_year IN (2025, 2026)
    AND (
            NULLIF(LTRIM(RTRIM(CAST(ia.member_id AS VARCHAR(100)))), '') IS NOT NULL
        OR NULLIF(LTRIM(RTRIM(CAST(ia.issuer_indiv_identifier AS VARCHAR(100)))), '') IS NOT NULL
        OR NULLIF(LTRIM(RTRIM(CAST(ia.exchg_assigned_enrollee_id AS VARCHAR(100)))), '') IS NOT NULL
    );

    CREATE UNIQUE CLUSTERED INDEX CX_new_inbound
        ON #new_inbound_identifiers (inbound_row_id);
    CREATE NONCLUSTERED INDEX IX_new_member
        ON #new_inbound_identifiers (Inbound_Member_ID);
    CREATE NONCLUSTERED INDEX IX_new_issuer_indiv
        ON #new_inbound_identifiers (Inbound_Issuer_Indiv_Identifier);
    CREATE NONCLUSTERED INDEX IX_new_exchange
        ON #new_inbound_identifiers (Inbound_Exchange_Assigned_Enrollee_ID);

    DECLARE @new_inbound_row_count BIGINT = (
        SELECT COUNT_BIG(*) FROM #new_inbound_identifiers
    );


    -- =============================================================================
    -- B3 — NEW_EXPORT_CLASSIFICATION: exact three NOT EXISTS checks
    -- =============================================================================
    IF OBJECT_ID('tempdb..#new_classification') IS NOT NULL DROP TABLE #new_classification;

    SELECT
        t.FFM_Coverage_Year,
        t.FFM_Policy_ID,
        t.FFM_Enrollee_ID,
        CASE
            WHEN NOT EXISTS (
                    SELECT 1
                    FROM #new_inbound_identifiers AS i
                    WHERE i.Inbound_Member_ID = t.FFM_Enrollee_ID
                )
            AND NOT EXISTS (
                    SELECT 1
                    FROM #new_inbound_identifiers AS i
                    WHERE i.Inbound_Issuer_Indiv_Identifier = t.FFM_Enrollee_ID
                )
            AND NOT EXISTS (
                    SELECT 1
                    FROM #new_inbound_identifiers AS i
                    WHERE i.Inbound_Exchange_Assigned_Enrollee_ID = t.FFM_Enrollee_ID
                )
                THEN 'NO_INBOUND_ENROLLEE_EVIDENCE'
            ELSE 'HAS_INBOUND_EVIDENCE'
        END AS New_Export_Evidence_Classification
    INTO #new_classification
    FROM #new_target AS t;

    CREATE UNIQUE CLUSTERED INDEX CX_new_classification
        ON #new_classification (
            FFM_Coverage_Year,
            FFM_Policy_ID,
            FFM_Enrollee_ID
        );

    DECLARE @new_no_inbound_count BIGINT = (
        SELECT COUNT_BIG(*)
        FROM #new_classification
        WHERE New_Export_Evidence_Classification = 'NO_INBOUND_ENROLLEE_EVIDENCE'
    );


    -- =============================================================================
    -- C — Isolate original HAS_INBOUND vs new NO_INBOUND
    -- =============================================================================
    IF OBJECT_ID('tempdb..#difference') IS NOT NULL DROP TABLE #difference;

    SELECT
        o.FFM_Coverage_Year,
        o.FFM_Issuer,
        o.FFM_Policy_ID,
        o.FFM_Enrollee_ID,
        o.FFM_Enrollment_Status,
        o.FFM_Enrollee_Status,
        o.Original_Match_Level,
        o.Original_Matched_Inbound_ID_Type,
        o.Original_Inbound_Coverage_Year,
        o.Original_Inbound_Issuer,
        o.Original_Inbound_Policy_ID,
        o.Original_Inbound_Health_Coverage_Policy_No,
        o.Original_Inbound_Member_ID,
        o.Original_Inbound_Issuer_Indiv_Identifier,
        o.Original_Inbound_Exchange_Assigned_Enrollee_ID,
        o.Original_Inbound_Status,
        o.Original_Folder_Year,
        o.Original_Source_File,
        CAST(
            CASE
                WHEN o.Original_Inbound_Coverage_Year IS NULL
                    THEN 'NULL_INBOUND_COVERAGE_YEAR'
                WHEN o.Original_Inbound_Coverage_Year NOT IN (2025, 2026)
                    THEN 'INBOUND_COVERAGE_YEAR_OUTSIDE_2025_2026'
                WHEN o.Original_Matched_Inbound_ID_Type NOT IN (
                        'MEMBER_ID',
                        'ISSUER_INDIV_IDENTIFIER',
                        'EXCHG_ASSIGNED_ENROLLEE_ID',
                        'MEMBER_ID+ISSUER_INDIV_IDENTIFIER',
                        'MEMBER_ID+EXCHG_ASSIGNED_ENROLLEE_ID',
                        'ISSUER_INDIV_IDENTIFIER+EXCHG_ASSIGNED_ENROLLEE_ID',
                        'ALL_THREE'
                    )
                    THEN 'ADDITIONAL_FORWARD_CANDIDATE_PATH'
                WHEN o.Original_Inbound_Coverage_Year IN (2025, 2026)
                    THEN 'IDENTIFIER_NORMALIZATION_DIFFERENCE'
                ELSE 'OTHER'
            END
            AS VARCHAR(60)
        ) AS Difference_Reason
    INTO #difference
    FROM #original_classification AS o
    INNER JOIN #new_classification AS n
        ON n.FFM_Coverage_Year = o.FFM_Coverage_Year
    AND n.FFM_Policy_ID = o.FFM_Policy_ID
    AND n.FFM_Enrollee_ID = o.FFM_Enrollee_ID
    WHERE o.Original_Evidence_Classification = 'HAS_INBOUND_EVIDENCE'
    AND n.New_Export_Evidence_Classification = 'NO_INBOUND_ENROLLEE_EVIDENCE';

    CREATE UNIQUE CLUSTERED INDEX CX_difference
        ON #difference (FFM_Coverage_Year, FFM_Policy_ID, FFM_Enrollee_ID);
    CREATE NONCLUSTERED INDEX IX_difference_reason_year
        ON #difference (Difference_Reason, Original_Inbound_Coverage_Year);

    DECLARE @difference_count BIGINT = (SELECT COUNT_BIG(*) FROM #difference);
    DECLARE @explained_by_year_scope BIGINT = (
        SELECT COUNT_BIG(*)
        FROM #difference
        WHERE Difference_Reason IN (
            'INBOUND_COVERAGE_YEAR_OUTSIDE_2025_2026',
            'NULL_INBOUND_COVERAGE_YEAR'
        )
    );

    SET @msg = CONCAT(
        'DIAGNOSTIC complete: original_no_inbound=', @original_no_inbound_count,
        '; new_no_inbound=', @new_no_inbound_count,
        '; difference=', @difference_count,
        '; elapsed_s=', DATEDIFF(second, @t0, SYSDATETIME())
    );
    RAISERROR(@msg, 10, 1) WITH NOWAIT;


    -- =============================================================================
    -- RESULT SET 1 — Independent classification controls
    -- =============================================================================
    SELECT
        @original_target_count AS ORIGINAL_FORWARD_TARGET_COUNT,
        @new_target_count AS NEW_EXPORT_TARGET_COUNT,
        @new_inbound_row_count AS NEW_EXPORT_INBOUND_STAGED_ROWS,
        @original_no_inbound_count AS ORIGINAL_FORWARD_NO_INBOUND_COUNT,
        @expected_original_no_inbound AS EXPECTED_ORIGINAL_FORWARD_NO_INBOUND_COUNT,
        @new_no_inbound_count AS NEW_EXPORT_NO_INBOUND_COUNT,
        @expected_new_no_inbound AS OBSERVED_EXPECTED_NEW_EXPORT_NO_INBOUND_COUNT,
        @difference_count AS DIFFERENCE_COUNT,
        @expected_difference AS EXPECTED_DIFFERENCE_COUNT,
        @explained_by_year_scope AS DIFFERENCE_EXPLAINED_BY_YEAR_SCOPE,
        CASE
            WHEN @original_target_count = @expected_target
            AND @new_target_count = @expected_target
            AND @original_no_inbound_count = @expected_original_no_inbound
            AND @new_no_inbound_count = @expected_new_no_inbound
            AND @difference_count = @expected_difference
                THEN 'PASS'
            ELSE 'REVIEW'
        END AS CONTROL_STATUS;


    -- =============================================================================
    -- RESULT SET 2 — Difference summary
    -- =============================================================================
    SELECT
        Difference_Reason,
        Original_Inbound_Coverage_Year,
        COUNT_BIG(*) AS Difference_Record_Count
    FROM #difference
    GROUP BY
        Difference_Reason,
        Original_Inbound_Coverage_Year
    ORDER BY
        Difference_Record_Count DESC,
        Difference_Reason,
        Original_Inbound_Coverage_Year;


    -- =============================================================================
    -- RESULT SET 3 — Difference detail
    -- =============================================================================
    SELECT
        FFM_Coverage_Year,
        FFM_Issuer,
        FFM_Policy_ID,
        FFM_Enrollee_ID,
        FFM_Enrollment_Status,
        FFM_Enrollee_Status,
        Original_Match_Level,
        Original_Inbound_Coverage_Year,
        Original_Inbound_Issuer,
        Original_Inbound_Policy_ID,
        Original_Inbound_Health_Coverage_Policy_No,
        Original_Inbound_Member_ID,
        Original_Inbound_Issuer_Indiv_Identifier,
        Original_Inbound_Exchange_Assigned_Enrollee_ID,
        Original_Inbound_Status,
        Original_Source_File,
        Difference_Reason,
        Original_Matched_Inbound_ID_Type,
        Original_Folder_Year
    FROM #difference
    ORDER BY
        Difference_Reason,
        Original_Inbound_Coverage_Year,
        FFM_Issuer,
        FFM_Policy_ID,
        FFM_Enrollee_ID;


    -- =============================================================================
    -- RESULT SET 4 — Exact original logic required for parity
    -- =============================================================================
    SELECT
        CASE
            WHEN @difference_count = @explained_by_year_scope
                THEN 'REUSE_ORIGINAL_ALL_COVERAGE_YEAR_INBOUND_WORKING_SET'
            ELSE 'YEAR_SCOPE_DOES_NOT_EXPLAIN_ALL_DIFFERENCES_REVIEW_DETAIL'
        END AS Required_Original_Logic,
        CASE
            WHEN @difference_count = @explained_by_year_scope
                THEN
                    'To reproduce the validated forward population, enrollee evidence must be searched across the original unfiltered inbound_automation working set, including coverage years outside 2025/2026 and NULL coverage_year.'
            ELSE
                    'The original unfiltered inbound year scope explains only part of the difference; review non-year Difference_Reason rows before changing the export.'
        END AS Root_Cause_Conclusion,
        @difference_count AS Total_Difference,
        @explained_by_year_scope AS Explained_By_Original_All_Year_Scope;
