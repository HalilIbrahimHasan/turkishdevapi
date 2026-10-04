-- =============================================================================
-- PROFILE — VALIDATED 2026 NO_INBOUND_ENROLLEE_EVIDENCE PREMIUM
-- =============================================================================
-- Source population:
--   Exact validated logic from:
--   sql/export_2026_no_inbound_enrollee_evidence.sql
--
-- Validated controls:
--   2026 FFM Enrolled/Pending target = 960,531 Policy + Enrollee pairs
--   NO_INBOUND_ENROLLEE_EVIDENCE     = 109,776 Policy + Enrollee pairs
--
-- Grain:
--   FFM_Coverage_Year + FFM_Policy_ID + FFM_Enrollee_ID
--
-- Safety:
--   READ ONLY on permanent tables. Temp tables/indexes only.
--   No RCNI. No Auto-Renewal analysis. No permanent writes.
--
-- Premium-column workflow:
--   1) Run with @NetPremiumColumn = NULL.
--   2) RESULT 0 lists candidate premium columns from dbo.Enrollments_TEST,
--      then the script stops.
--   3) Confirm the exact Net Premium Amount field, set @NetPremiumColumn to
--      that exact column name, and rerun the complete script.
--
-- Do not set @NetPremiumColumn based only on a similar name.
-- =============================================================================

SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @CoverageYear INT = 2026;
DECLARE @ExpectedFFMTarget BIGINT = 960531;
DECLARE @ExpectedNoInbound BIGINT = 109776;

-- Keep NULL until RESULT 0 has been reviewed and the exact field confirmed.
DECLARE @NetPremiumColumn SYSNAME = NULL;

DECLARE @StartedAt DATETIME2 = SYSDATETIME();
DECLARE @Message NVARCHAR(400);


-- =============================================================================
-- RESULT 0 — dbo.Enrollments_TEST premium-column schema check
-- =============================================================================
SELECT
    c.column_id AS Column_Ordinal,
    c.name AS Candidate_Premium_Column,
    t.name AS Data_Type,
    c.max_length AS Max_Length,
    c.precision AS Numeric_Precision,
    c.scale AS Numeric_Scale,
    c.is_nullable AS Is_Nullable,
    CASE
        WHEN LOWER(c.name) IN (
            'net_premium_amount',
            'net_premium_amt',
            'netpremiumamount',
            'netpremiumamt'
        ) THEN 'NAME_RESEMBLES_NET_PREMIUM_CONFIRM_BEFORE_USE'
        ELSE 'RELATED_PREMIUM_OR_RESPONSIBILITY_FIELD_REVIEW'
    END AS Review_Note
FROM sys.columns AS c
INNER JOIN sys.types AS t
    ON t.user_type_id = c.user_type_id
WHERE c.object_id = OBJECT_ID(N'dbo.Enrollments_TEST')
  AND (
         LOWER(c.name) LIKE '%premium%'
      OR LOWER(c.name) LIKE '%responsibility%'
  )
ORDER BY
    CASE
        WHEN LOWER(c.name) IN (
            'net_premium_amount',
            'net_premium_amt',
            'netpremiumamount',
            'netpremiumamt'
        ) THEN 0
        ELSE 1
    END,
    c.column_id;

IF @NetPremiumColumn IS NULL
BEGIN
    THROW 50001,
        'STOP: Review RESULT 0, confirm the exact dbo.Enrollments_TEST Net Premium Amount field, set @NetPremiumColumn, and rerun.',
        1;
END;

IF NOT EXISTS (
    SELECT 1
    FROM sys.columns AS c
    WHERE c.object_id = OBJECT_ID(N'dbo.Enrollments_TEST')
      AND c.name = @NetPremiumColumn
)
BEGIN
    THROW 50002,
        'STOP: @NetPremiumColumn does not exist in dbo.Enrollments_TEST.',
        1;
END;


-- =============================================================================
-- STEP 1 — Exact validated 2026 FFM target population and deduplication
-- =============================================================================
RAISERROR('PREMIUM PROFILE STEP1: build validated FFM target', 10, 1) WITH NOWAIT;

IF OBJECT_ID('tempdb..#ffm_target') IS NOT NULL DROP TABLE #ffm_target;

CREATE TABLE #ffm_target (
    FFM_Coverage_Year INT NULL,
    FFM_Issuer VARCHAR(20) NULL,
    FFM_Policy_ID VARCHAR(100) NULL,
    FFM_Enrollee_ID VARCHAR(100) NULL,
    FFM_Enrollment_Status NVARCHAR(255) NULL,
    FFM_Enrollee_Status NVARCHAR(255) NULL,
    Net_Premium_Amount DECIMAL(38, 10) NULL
);

DECLARE @LoadFFMTargetSQL NVARCHAR(MAX) =
    N'
    INSERT INTO #ffm_target (
        FFM_Coverage_Year,
        FFM_Issuer,
        FFM_Policy_ID,
        FFM_Enrollee_ID,
        FFM_Enrollment_Status,
        FFM_Enrollee_Status,
        Net_Premium_Amount
    )
    SELECT
        e.coverage_year,
        CAST(e.hios_issuer_id AS VARCHAR(20)),
        CAST(e.enrollment_id AS VARCHAR(100)),
        CAST(e.enrollee_id AS VARCHAR(100)),
        e.enrollment_status_description,
        e.enrollee_status_description,
        TRY_CONVERT(DECIMAL(38, 10), e.Net_Premium_Source_Value)
    FROM (
        SELECT
            src.coverage_year,
            src.hios_issuer_id,
            src.enrollment_id,
            src.enrollee_id,
            src.enrollment_status_description,
            src.enrollee_status_description,
            src.enrollment_create_date,
            src.enrollment_last_update_date,
            src.' + QUOTENAME(@NetPremiumColumn) + N' AS Net_Premium_Source_Value,
            ROW_NUMBER() OVER (
                PARTITION BY
                    src.coverage_year,
                    src.enrollment_id,
                    src.enrollee_id
                ORDER BY
                    src.enrollment_last_update_date DESC,
                    src.enrollment_create_date DESC
            ) AS _rn
        FROM dbo.Enrollments_TEST AS src
        WHERE src.coverage_year = @DynamicCoverageYear
          AND UPPER(LTRIM(RTRIM(src.enrollment_status_description)))
              IN (''ENROLLED'', ''PENDING'')
    ) AS e
    WHERE e._rn = 1;';

EXEC sys.sp_executesql
    @LoadFFMTargetSQL,
    N'@DynamicCoverageYear INT',
    @DynamicCoverageYear = @CoverageYear;

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
        FFM_Enrollee_Status,
        Net_Premium_Amount
    );

DECLARE @FFMTargetCount BIGINT = (
    SELECT COUNT_BIG(*) FROM #ffm_target
);

IF @FFMTargetCount <> @ExpectedFFMTarget
BEGIN
    RAISERROR(
        'STOP: FFM_TARGET_COUNT=%I64d; expected %I64d. No premium profile returned.',
        16, 1, @FFMTargetCount, @ExpectedFFMTarget
    );
    RETURN;
END;


-- =============================================================================
-- STEP 2 — Exact validated all-history inbound enrollee identifier stage
-- =============================================================================
RAISERROR('PREMIUM PROFILE STEP2: stage all-history inbound identifiers', 10, 1) WITH NOWAIT;

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
-- STEP 3 — Exact validated NO_INBOUND_ENROLLEE_EVIDENCE population
-- =============================================================================
RAISERROR('PREMIUM PROFILE STEP3: build validated NO_INBOUND population', 10, 1) WITH NOWAIT;

IF OBJECT_ID('tempdb..#no_inbound_premium') IS NOT NULL
    DROP TABLE #no_inbound_premium;

SELECT
    t.FFM_Coverage_Year,
    t.FFM_Issuer,
    t.FFM_Policy_ID,
    t.FFM_Enrollee_ID,
    t.FFM_Enrollment_Status,
    t.FFM_Enrollee_Status,
    t.Net_Premium_Amount,
    CAST(
        CASE
            WHEN t.Net_Premium_Amount IS NULL THEN 'NULL_PREMIUM'
            WHEN t.Net_Premium_Amount = 0 THEN 'ZERO_DOLLAR'
            ELSE 'NON_ZERO'
        END
        AS VARCHAR(20)
    ) AS Premium_Category,
    CAST('NO_INBOUND_ENROLLEE_EVIDENCE' AS VARCHAR(40)) AS Match_Level
INTO #no_inbound_premium
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

CREATE UNIQUE CLUSTERED INDEX CX_no_inbound_premium
    ON #no_inbound_premium (
        FFM_Coverage_Year,
        FFM_Policy_ID,
        FFM_Enrollee_ID
    );

CREATE NONCLUSTERED INDEX IX_no_inbound_premium_category
    ON #no_inbound_premium (Premium_Category)
    INCLUDE (
        FFM_Issuer,
        FFM_Enrollment_Status,
        FFM_Enrollee_Status
    );

DECLARE @NoInboundCount BIGINT = (
    SELECT COUNT_BIG(*) FROM #no_inbound_premium
);

IF @NoInboundCount <> @ExpectedNoInbound
BEGIN
    RAISERROR(
        'STOP: NO_INBOUND_COUNT=%I64d; expected %I64d. No premium profile returned.',
        16, 1, @NoInboundCount, @ExpectedNoInbound
    );
    RETURN;
END;

SET @Message = CONCAT(
    'PREMIUM PROFILE population validated; FFM_TARGET_COUNT=', @FFMTargetCount,
    '; NO_INBOUND_COUNT=', @NoInboundCount,
    '; elapsed_s=', DATEDIFF(second, @StartedAt, SYSDATETIME())
);
RAISERROR(@Message, 10, 1) WITH NOWAIT;


-- =============================================================================
-- REQUIRED CONTROL
-- =============================================================================
SELECT
    @FFMTargetCount AS FFM_TARGET_COUNT,
    @NoInboundCount AS NO_INBOUND_COUNT,
    CAST('PASS' AS VARCHAR(4)) AS CONTROL_STATUS;


-- =============================================================================
-- RESULT 1 — Premium category distribution
-- =============================================================================
SELECT
    Premium_Category,
    COUNT_BIG(*) AS Record_Count,
    CAST(
        100.0 * COUNT_BIG(*) / NULLIF(@ExpectedNoInbound, 0)
        AS DECIMAL(10, 4)
    ) AS Percent_of_109776
FROM #no_inbound_premium
GROUP BY Premium_Category
ORDER BY
    CASE Premium_Category
        WHEN 'ZERO_DOLLAR' THEN 1
        WHEN 'NON_ZERO' THEN 2
        WHEN 'NULL_PREMIUM' THEN 3
        ELSE 99
    END;


-- =============================================================================
-- RESULT 2 — FFM enrollment status by premium category
-- =============================================================================
SELECT
    FFM_Enrollment_Status,
    Premium_Category,
    COUNT_BIG(*) AS Record_Count
FROM #no_inbound_premium
GROUP BY
    FFM_Enrollment_Status,
    Premium_Category
ORDER BY
    FFM_Enrollment_Status,
    CASE Premium_Category
        WHEN 'ZERO_DOLLAR' THEN 1
        WHEN 'NON_ZERO' THEN 2
        WHEN 'NULL_PREMIUM' THEN 3
        ELSE 99
    END;


-- =============================================================================
-- RESULT 3 — FFM enrollee status by premium category
-- =============================================================================
SELECT
    FFM_Enrollee_Status,
    Premium_Category,
    COUNT_BIG(*) AS Record_Count
FROM #no_inbound_premium
GROUP BY
    FFM_Enrollee_Status,
    Premium_Category
ORDER BY
    FFM_Enrollee_Status,
    CASE Premium_Category
        WHEN 'ZERO_DOLLAR' THEN 1
        WHEN 'NON_ZERO' THEN 2
        WHEN 'NULL_PREMIUM' THEN 3
        ELSE 99
    END;


-- =============================================================================
-- RESULT 4 — Issuer by premium category
-- =============================================================================
SELECT
    FFM_Issuer AS Issuer,
    Premium_Category,
    COUNT_BIG(*) AS Record_Count
FROM #no_inbound_premium
GROUP BY
    FFM_Issuer,
    Premium_Category
ORDER BY
    FFM_Issuer,
    CASE Premium_Category
        WHEN 'ZERO_DOLLAR' THEN 1
        WHEN 'NON_ZERO' THEN 2
        WHEN 'NULL_PREMIUM' THEN 3
        ELSE 99
    END;


-- =============================================================================
-- FINAL RESULT — All 109,776 validated row-level records
-- =============================================================================
SELECT
    FFM_Coverage_Year,
    FFM_Issuer,
    FFM_Policy_ID,
    FFM_Enrollee_ID,
    FFM_Enrollment_Status,
    FFM_Enrollee_Status,
    Net_Premium_Amount,
    Premium_Category
FROM #no_inbound_premium
WHERE Match_Level = 'NO_INBOUND_ENROLLEE_EVIDENCE'
ORDER BY
    FFM_Issuer,
    FFM_Policy_ID,
    FFM_Enrollee_ID;
