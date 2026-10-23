-- =============================================================================
-- PHASE 1 — DIRECT AUTO-RENEWAL INDICATOR DISCOVERY
-- =============================================================================
-- Purpose:
--   Search Azure SQL metadata for a direct, authoritative Auto-Renewal field
--   before any historical-lineage inference is attempted.
--
-- Repository finding before execution:
--   No executable SQL/Python classification for Auto-Renewal exists locally.
--   RENP/AUTORENEW appears only in Companion Guide documentation.
--
-- Safety:
--   READ ONLY. Temp tables only. No permanent writes. No RCNI data access.
--   This script does NOT classify any record as Auto-Renewal.
--   This script does NOT rebuild or alter the validated 109,776 population.
-- =============================================================================

SET NOCOUNT ON;
SET XACT_ABORT ON;


-- =============================================================================
-- 1) Candidate columns in tables/views
-- =============================================================================
IF OBJECT_ID('tempdb..#candidate_columns') IS NOT NULL
    DROP TABLE #candidate_columns;

;WITH object_inventory AS (
    SELECT
        o.object_id,
        s.name AS schema_name,
        o.name AS object_name,
        CASE o.type
            WHEN 'U' THEN 'TABLE'
            WHEN 'V' THEN 'VIEW'
            ELSE o.type_desc
        END AS object_type
    FROM sys.objects AS o
    INNER JOIN sys.schemas AS s
        ON s.schema_id = o.schema_id
    WHERE o.type IN ('U', 'V')
      AND o.is_ms_shipped = 0
),
column_inventory AS (
    SELECT
        oi.object_id,
        oi.schema_name,
        oi.object_name,
        oi.object_type,
        c.column_id,
        c.name AS column_name,
        t.name AS data_type,
        c.max_length,
        c.precision,
        c.scale,
        c.is_nullable,
        LOWER(
            REPLACE(
                REPLACE(
                    REPLACE(c.name, '_', ''),
                    ' ',
                    ''
                ),
                '-',
                ''
            )
        ) AS normalized_column_name
    FROM object_inventory AS oi
    INNER JOIN sys.columns AS c
        ON c.object_id = oi.object_id
    INNER JOIN sys.types AS t
        ON t.user_type_id = c.user_type_id
)
SELECT
    object_id,
    schema_name,
    object_name,
    object_type,
    column_id,
    column_name,
    data_type,
    max_length,
    precision,
    scale,
    is_nullable,
    normalized_column_name,
    CAST(
        CASE
            WHEN normalized_column_name LIKE '%autorenew%'
                THEN 'AUTO_RENEWAL_NAME'
            WHEN normalized_column_name LIKE '%passiverenew%'
                THEN 'PASSIVE_RENEWAL_NAME'
            WHEN normalized_column_name LIKE '%reenroll%'
                THEN 'REENROLLMENT_NAME'
            WHEN normalized_column_name LIKE '%renewal%'
              OR normalized_column_name LIKE '%renew%'
                THEN 'RENEWAL_NAME'
            WHEN normalized_column_name LIKE '%enrollmentorigin%'
              OR normalized_column_name LIKE '%origintype%'
              OR normalized_column_name LIKE '%origin%'
                THEN 'ORIGIN_NAME'
            ELSE 'OTHER'
        END
        AS VARCHAR(40)
    ) AS candidate_reason
INTO #candidate_columns
FROM column_inventory
WHERE normalized_column_name LIKE '%autorenew%'
   OR normalized_column_name LIKE '%passiverenew%'
   OR normalized_column_name LIKE '%reenroll%'
   OR normalized_column_name LIKE '%renewal%'
   OR normalized_column_name LIKE '%renew%'
   OR normalized_column_name LIKE '%enrollmentorigin%'
   OR normalized_column_name LIKE '%origintype%'
   OR normalized_column_name LIKE '%origin%';

CREATE CLUSTERED INDEX CX_candidate_columns
    ON #candidate_columns (
        candidate_reason,
        schema_name,
        object_name,
        column_id
    );


-- =============================================================================
-- 2) Candidate-object joinability inventory
-- =============================================================================
IF OBJECT_ID('tempdb..#candidate_objects') IS NOT NULL
    DROP TABLE #candidate_objects;

;WITH candidate_object_ids AS (
    SELECT DISTINCT
        object_id,
        schema_name,
        object_name,
        object_type
    FROM #candidate_columns
),
all_columns AS (
    SELECT
        co.object_id,
        co.schema_name,
        co.object_name,
        co.object_type,
        c.name AS column_name,
        LOWER(
            REPLACE(
                REPLACE(
                    REPLACE(c.name, '_', ''),
                    ' ',
                    ''
                ),
                '-',
                ''
            )
        ) AS normalized_column_name
    FROM candidate_object_ids AS co
    INNER JOIN sys.columns AS c
        ON c.object_id = co.object_id
)
SELECT
    object_id,
    schema_name,
    object_name,
    object_type,
    MAX(CASE
            WHEN normalized_column_name IN (
                'coverageyear',
                'planyear',
                'benefityear',
                'year'
            ) THEN column_name
        END) AS coverage_year_column,
    MAX(CASE
            WHEN normalized_column_name IN (
                'enrollmentid',
                'policyid',
                'exchangeassignedpolicyid',
                'exchgassignedpolicyid',
                'healthcoveragepolicyno'
            ) THEN column_name
        END) AS policy_key_column,
    MAX(CASE
            WHEN normalized_column_name IN (
                'enrolleeid',
                'memberid',
                'exchangeassignedenrolleeid',
                'exchgassignedenrolleeid',
                'issuerindividentifier'
            ) THEN column_name
        END) AS enrollee_key_column,
    MAX(CASE
            WHEN normalized_column_name IN (
                'hiosissuerid',
                'issuerid',
                'issuer'
            ) THEN column_name
        END) AS issuer_column,
    MAX(CASE
            WHEN normalized_column_name = 'enrollmentid'
                THEN 1 ELSE 0
        END) AS has_exact_ffm_policy_key,
    MAX(CASE
            WHEN normalized_column_name = 'enrolleeid'
                THEN 1 ELSE 0
        END) AS has_exact_ffm_enrollee_key,
    MAX(CASE
            WHEN normalized_column_name = 'coverageyear'
                THEN 1 ELSE 0
        END) AS has_exact_ffm_coverage_year
INTO #candidate_objects
FROM all_columns
GROUP BY
    object_id,
    schema_name,
    object_name,
    object_type;

CREATE UNIQUE CLUSTERED INDEX CX_candidate_objects
    ON #candidate_objects (object_id);


-- =============================================================================
-- 3) Profile distinct candidate values and coverage years
-- =============================================================================
-- Profiles ordinary scalar SQL types only. Unsupported/large object types remain
-- visible in the metadata result but are not dynamically converted.
-- =============================================================================
IF OBJECT_ID('tempdb..#candidate_value_profile') IS NOT NULL
    DROP TABLE #candidate_value_profile;

CREATE TABLE #candidate_value_profile (
    schema_name SYSNAME NOT NULL,
    object_name SYSNAME NOT NULL,
    object_type VARCHAR(20) NOT NULL,
    column_name SYSNAME NOT NULL,
    data_type SYSNAME NOT NULL,
    coverage_year_column SYSNAME NULL,
    coverage_year_value NVARCHAR(100) NULL,
    distinct_indicator_value NVARCHAR(4000) NULL,
    record_count BIGINT NOT NULL,
    profile_status VARCHAR(40) NOT NULL
);

DECLARE
    @schema_name SYSNAME,
    @object_name SYSNAME,
    @object_type VARCHAR(20),
    @column_name SYSNAME,
    @data_type SYSNAME,
    @coverage_year_column SYSNAME,
    @profile_sql NVARCHAR(MAX);

DECLARE candidate_cursor CURSOR LOCAL FAST_FORWARD FOR
SELECT
    c.schema_name,
    c.object_name,
    c.object_type,
    c.column_name,
    c.data_type,
    o.coverage_year_column
FROM #candidate_columns AS c
INNER JOIN #candidate_objects AS o
    ON o.object_id = c.object_id
ORDER BY
    c.schema_name,
    c.object_name,
    c.column_id;

OPEN candidate_cursor;

FETCH NEXT FROM candidate_cursor INTO
    @schema_name,
    @object_name,
    @object_type,
    @column_name,
    @data_type,
    @coverage_year_column;

WHILE @@FETCH_STATUS = 0
BEGIN
    IF @data_type IN (
        'bit',
        'tinyint',
        'smallint',
        'int',
        'bigint',
        'decimal',
        'numeric',
        'money',
        'smallmoney',
        'float',
        'real',
        'char',
        'varchar',
        'nchar',
        'nvarchar',
        'date',
        'datetime',
        'datetime2',
        'smalldatetime',
        'datetimeoffset',
        'uniqueidentifier'
    )
    BEGIN
        SET @profile_sql =
            N'INSERT INTO #candidate_value_profile (
                schema_name,
                object_name,
                object_type,
                column_name,
                data_type,
                coverage_year_column,
                coverage_year_value,
                distinct_indicator_value,
                record_count,
                profile_status
            )
            SELECT
                @p_schema_name,
                @p_object_name,
                @p_object_type,
                @p_column_name,
                @p_data_type,
                @p_coverage_year_column,'
            + CASE
                WHEN @coverage_year_column IS NULL
                    THEN N'CAST(NULL AS NVARCHAR(100)),'
                ELSE
                    N'TRY_CONVERT(
                        NVARCHAR(100),
                        src.' + QUOTENAME(@coverage_year_column) + N'
                    ),'
              END
            + N'TRY_CONVERT(
                    NVARCHAR(4000),
                    src.' + QUOTENAME(@column_name) + N'
                ),
                COUNT_BIG(*),
                ''PROFILED''
            FROM '
            + QUOTENAME(@schema_name)
            + N'.'
            + QUOTENAME(@object_name)
            + N' AS src
            GROUP BY '
            + CASE
                WHEN @coverage_year_column IS NULL
                    THEN N''
                ELSE
                    N'TRY_CONVERT(
                        NVARCHAR(100),
                        src.' + QUOTENAME(@coverage_year_column) + N'
                    ),'
              END
            + N'TRY_CONVERT(
                    NVARCHAR(4000),
                    src.' + QUOTENAME(@column_name) + N'
                );';

        EXEC sys.sp_executesql
            @profile_sql,
            N'@p_schema_name SYSNAME,
              @p_object_name SYSNAME,
              @p_object_type VARCHAR(20),
              @p_column_name SYSNAME,
              @p_data_type SYSNAME,
              @p_coverage_year_column SYSNAME',
            @p_schema_name = @schema_name,
            @p_object_name = @object_name,
            @p_object_type = @object_type,
            @p_column_name = @column_name,
            @p_data_type = @data_type,
            @p_coverage_year_column = @coverage_year_column;
    END
    ELSE
    BEGIN
        INSERT INTO #candidate_value_profile (
            schema_name,
            object_name,
            object_type,
            column_name,
            data_type,
            coverage_year_column,
            coverage_year_value,
            distinct_indicator_value,
            record_count,
            profile_status
        )
        VALUES (
            @schema_name,
            @object_name,
            @object_type,
            @column_name,
            @data_type,
            @coverage_year_column,
            NULL,
            NULL,
            0,
            'UNSUPPORTED_TYPE_NOT_PROFILED'
        );
    END;

    FETCH NEXT FROM candidate_cursor INTO
        @schema_name,
        @object_name,
        @object_type,
        @column_name,
        @data_type,
        @coverage_year_column;
END;

CLOSE candidate_cursor;
DEALLOCATE candidate_cursor;


-- =============================================================================
-- 4) Stored procedure, function, view, and trigger definitions mentioning
--    renewal/origin concepts
-- =============================================================================
IF OBJECT_ID('tempdb..#module_matches') IS NOT NULL
    DROP TABLE #module_matches;

SELECT
    s.name AS schema_name,
    o.name AS object_name,
    o.type_desc AS object_type,
    CASE
        WHEN LOWER(m.definition) LIKE '%autorenew%'
          OR LOWER(m.definition) LIKE '%auto-renew%'
          OR LOWER(m.definition) LIKE '%auto renewal%'
            THEN 'AUTO_RENEWAL_TEXT'
        WHEN LOWER(m.definition) LIKE '%passive%renew%'
            THEN 'PASSIVE_RENEWAL_TEXT'
        WHEN LOWER(m.definition) LIKE '%reenroll%'
            THEN 'REENROLLMENT_TEXT'
        WHEN LOWER(m.definition) LIKE '%renew%'
            THEN 'RENEWAL_TEXT'
        WHEN LOWER(m.definition) LIKE '%origin%'
            THEN 'ORIGIN_TEXT'
        ELSE 'OTHER'
    END AS match_reason
INTO #module_matches
FROM sys.sql_modules AS m
INNER JOIN sys.objects AS o
    ON o.object_id = m.object_id
INNER JOIN sys.schemas AS s
    ON s.schema_id = o.schema_id
WHERE o.is_ms_shipped = 0
  AND (
         LOWER(m.definition) LIKE '%autorenew%'
      OR LOWER(m.definition) LIKE '%auto-renew%'
      OR LOWER(m.definition) LIKE '%auto renewal%'
      OR LOWER(m.definition) LIKE '%passive%renew%'
      OR LOWER(m.definition) LIKE '%reenroll%'
      OR LOWER(m.definition) LIKE '%renew%'
      OR LOWER(m.definition) LIKE '%origin%'
  );


-- =============================================================================
-- RESULT 1 — Candidate Auto-Renewal columns and joinability
-- =============================================================================
SELECT
    c.schema_name AS Schema_Name,
    c.object_name AS Object_Name,
    c.object_type AS Object_Type,
    c.column_name AS Column_Name,
    c.data_type AS Data_Type,
    c.max_length AS Max_Length,
    c.precision AS Numeric_Precision,
    c.scale AS Numeric_Scale,
    c.is_nullable AS Is_Nullable,
    c.candidate_reason AS Candidate_Reason,
    o.coverage_year_column AS Coverage_Year_Column,
    o.policy_key_column AS Candidate_Policy_Key,
    o.enrollee_key_column AS Candidate_Enrollee_Key,
    o.issuer_column AS Candidate_Issuer_Column,
    CASE
        WHEN o.has_exact_ffm_coverage_year = 1
         AND o.has_exact_ffm_policy_key = 1
         AND o.has_exact_ffm_enrollee_key = 1
            THEN 'DIRECT_VALIDATED_GRAIN_AVAILABLE'
        WHEN o.policy_key_column IS NOT NULL
         AND o.enrollee_key_column IS NOT NULL
            THEN 'POTENTIAL_POLICY_ENROLLEE_JOIN_REQUIRES_VALIDATION'
        WHEN o.enrollee_key_column IS NOT NULL
            THEN 'ENROLLEE_ONLY_JOIN_RISK_OF_MULTIPLICATION'
        ELSE 'NO_OBVIOUS_JOIN_TO_VALIDATED_GRAIN'
    END AS Joinability_Assessment
FROM #candidate_columns AS c
INNER JOIN #candidate_objects AS o
    ON o.object_id = c.object_id
ORDER BY
    CASE c.candidate_reason
        WHEN 'AUTO_RENEWAL_NAME' THEN 1
        WHEN 'PASSIVE_RENEWAL_NAME' THEN 2
        WHEN 'REENROLLMENT_NAME' THEN 3
        WHEN 'RENEWAL_NAME' THEN 4
        WHEN 'ORIGIN_NAME' THEN 5
        ELSE 99
    END,
    c.schema_name,
    c.object_name,
    c.column_id;


-- =============================================================================
-- RESULT 2 — Distinct values, coverage years, and record counts
-- =============================================================================
SELECT
    schema_name AS Schema_Name,
    object_name AS Object_Name,
    object_type AS Object_Type,
    column_name AS Column_Name,
    data_type AS Data_Type,
    coverage_year_column AS Coverage_Year_Column,
    coverage_year_value AS Coverage_Year_Value,
    distinct_indicator_value AS Distinct_Indicator_Value,
    record_count AS Record_Count,
    profile_status AS Profile_Status
FROM #candidate_value_profile
ORDER BY
    schema_name,
    object_name,
    column_name,
    coverage_year_value,
    record_count DESC,
    distinct_indicator_value;


-- =============================================================================
-- RESULT 3 — Candidate object totals and candidate indicator counts
-- =============================================================================
SELECT
    p.schema_name AS Schema_Name,
    p.object_name AS Object_Name,
    p.object_type AS Object_Type,
    p.column_name AS Column_Name,
    p.data_type AS Data_Type,
    p.coverage_year_column AS Coverage_Year_Column,
    COUNT(*) AS Profiled_Value_Year_Combinations,
    SUM(p.record_count) AS Total_Records_Profiled,
    COUNT(DISTINCT p.distinct_indicator_value) AS Distinct_Indicator_Values,
    COUNT(DISTINCT p.coverage_year_value) AS Distinct_Coverage_Years
FROM #candidate_value_profile AS p
WHERE p.profile_status = 'PROFILED'
GROUP BY
    p.schema_name,
    p.object_name,
    p.object_type,
    p.column_name,
    p.data_type,
    p.coverage_year_column
ORDER BY
    p.schema_name,
    p.object_name,
    p.column_name;


-- =============================================================================
-- RESULT 4 — SQL modules containing renewal/origin logic
-- =============================================================================
SELECT
    schema_name AS Schema_Name,
    object_name AS Object_Name,
    object_type AS Object_Type,
    match_reason AS Match_Reason
FROM #module_matches
ORDER BY
    CASE match_reason
        WHEN 'AUTO_RENEWAL_TEXT' THEN 1
        WHEN 'PASSIVE_RENEWAL_TEXT' THEN 2
        WHEN 'REENROLLMENT_TEXT' THEN 3
        WHEN 'RENEWAL_TEXT' THEN 4
        WHEN 'ORIGIN_TEXT' THEN 5
        ELSE 99
    END,
    schema_name,
    object_name;


-- =============================================================================
-- RESULT 5 — Phase 1 disposition
-- =============================================================================
SELECT
    (SELECT COUNT_BIG(*) FROM #candidate_columns)
        AS Candidate_Column_Count,
    (SELECT COUNT_BIG(*) FROM #candidate_objects)
        AS Candidate_Object_Count,
    (SELECT COUNT_BIG(*) FROM #module_matches)
        AS Candidate_Module_Count,
    CAST(109776 AS BIGINT) AS Validated_No_Inbound_Control,
    CAST(75390 AS BIGINT) AS Business_Reported_Auto_Renewal_Reference,
    CAST(
        CASE
            WHEN EXISTS (
                SELECT 1
                FROM #candidate_columns AS c
                INNER JOIN #candidate_objects AS o
                    ON o.object_id = c.object_id
                WHERE c.candidate_reason IN (
                    'AUTO_RENEWAL_NAME',
                    'PASSIVE_RENEWAL_NAME'
                )
                  AND o.has_exact_ffm_coverage_year = 1
                  AND o.has_exact_ffm_policy_key = 1
                  AND o.has_exact_ffm_enrollee_key = 1
            )
                THEN 'DIRECT_CANDIDATE_FOUND_REQUIRES_BUSINESS_VALIDATION'
            WHEN EXISTS (
                SELECT 1
                FROM #candidate_columns
                WHERE candidate_reason IN (
                    'AUTO_RENEWAL_NAME',
                    'PASSIVE_RENEWAL_NAME',
                    'REENROLLMENT_NAME',
                    'RENEWAL_NAME'
                )
            )
                THEN 'RENEWAL_CANDIDATE_FOUND_JOIN_OR_SEMANTICS_UNPROVEN'
            ELSE 'NO_DIRECT_RENEWAL_COLUMN_FOUND_PROCEED_TO_LINEAGE_PHASE'
        END
        AS VARCHAR(70)
    ) AS Phase_1_Status;
