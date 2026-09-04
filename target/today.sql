-- =============================================================================
-- RCNI Phase 2 — manual Azure SQL / SQL Server table creation
-- =============================================================================
-- ONE self-contained script. Open in Azure Query Editor or SSMS and execute
-- manually. Do NOT run from Python. The application never creates these tables.
--
-- Safe to re-run:
--   tables  — created only when OBJECT_ID is NULL
--   indexes — created only when the named index is missing
--
-- Does not DROP, TRUNCATE, ALTER, or INSERT.
-- Does not use CREATE TABLE IF NOT EXISTS.
--
-- Execution order:
--   1. dbo.rcni_run_log
--   2. dbo.rcni_file_log
--   3. dbo.rcni_raw
--   4. dbo.rcni_data_quality_issue
--   5. dbo.rcni_stage
--   then all indexes (PK / UNIQUE constraints are created with the tables)
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. dbo.rcni_run_log
-- -----------------------------------------------------------------------------
IF OBJECT_ID(N'dbo.rcni_run_log', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.rcni_run_log
    (
        load_run_id             UNIQUEIDENTIFIER    NOT NULL
            CONSTRAINT PK_rcni_run_log PRIMARY KEY,
        started_at              DATETIME2(0)        NOT NULL
            CONSTRAINT DF_rcni_run_log_started_at DEFAULT SYSUTCDATETIME(),
        completed_at            DATETIME2(0)        NULL,
        run_mode                VARCHAR(50)         NOT NULL,
        issuer_scope            NVARCHAR(500)       NULL,
        year_scope              NVARCHAR(100)       NULL,
        month_scope             NVARCHAR(100)       NULL,
        files_discovered        INT                 NOT NULL
            CONSTRAINT DF_rcni_run_log_disc DEFAULT 0,
        files_attempted         INT                 NOT NULL
            CONSTRAINT DF_rcni_run_log_att DEFAULT 0,
        files_successful        INT                 NOT NULL
            CONSTRAINT DF_rcni_run_log_ok DEFAULT 0,
        files_failed            INT                 NOT NULL
            CONSTRAINT DF_rcni_run_log_fail DEFAULT 0,
        files_skipped           INT                 NOT NULL
            CONSTRAINT DF_rcni_run_log_skip DEFAULT 0,
        rows_parsed             BIGINT              NOT NULL
            CONSTRAINT DF_rcni_run_log_parsed DEFAULT 0,
        rows_loaded             BIGINT              NOT NULL
            CONSTRAINT DF_rcni_run_log_loaded DEFAULT 0,
        rows_flagged            BIGINT              NOT NULL
            CONSTRAINT DF_rcni_run_log_flagged DEFAULT 0,
        status                  VARCHAR(50)         NOT NULL,
        error_message           NVARCHAR(MAX)       NULL
    );
END;
GO


-- -----------------------------------------------------------------------------
-- 2. dbo.rcni_file_log
-- processing_status and file_disposition are independent.
-- file_hash is NOT unique.
-- -----------------------------------------------------------------------------
IF OBJECT_ID(N'dbo.rcni_file_log', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.rcni_file_log
    (
        file_id                 BIGINT IDENTITY(1,1) NOT NULL
            CONSTRAINT PK_rcni_file_log PRIMARY KEY CLUSTERED,
        source_file             NVARCHAR(500)       NOT NULL,
        source_path             NVARCHAR(1500)      NOT NULL,
        issuer_id               VARCHAR(20)         NOT NULL,
        document_type           VARCHAR(100)        NOT NULL
            CONSTRAINT DF_rcni_file_log_doc DEFAULT 'INDV_MONTHLYDISCREPANCY',
        coverage_year           INT                 NULL,
        processing_year         INT                 NULL,
        processing_month        TINYINT             NULL,
        processing_day          TINYINT             NULL,
        file_timestamp          DATETIME2(0)        NULL,
        compression_type        VARCHAR(30)         NOT NULL,
        file_size_bytes         BIGINT              NULL,
        file_hash               CHAR(64)            NOT NULL,
        rows_read               BIGINT              NOT NULL
            CONSTRAINT DF_rcni_file_log_read DEFAULT 0,
        rows_parsed             BIGINT              NOT NULL
            CONSTRAINT DF_rcni_file_log_parsed DEFAULT 0,
        rows_loaded             BIGINT              NOT NULL
            CONSTRAINT DF_rcni_file_log_loaded DEFAULT 0,
        rows_flagged            BIGINT              NOT NULL
            CONSTRAINT DF_rcni_file_log_flagged DEFAULT 0,
        rows_rejected           BIGINT              NOT NULL
            CONSTRAINT DF_rcni_file_log_rej DEFAULT 0,
        processing_status       VARCHAR(50)         NOT NULL,
        file_disposition        VARCHAR(50)         NOT NULL
            CONSTRAINT DF_rcni_file_log_disposition DEFAULT 'NEW',
        error_message           NVARCHAR(MAX)       NULL,
        load_run_id             UNIQUEIDENTIFIER    NULL,
        first_seen_at           DATETIME2(0)        NOT NULL
            CONSTRAINT DF_rcni_file_log_first_seen DEFAULT SYSUTCDATETIME(),
        started_at              DATETIME2(0)        NULL,
        completed_at            DATETIME2(0)        NULL,
        loaded_at               DATETIME2(0)        NULL
    );
END;
GO


-- -----------------------------------------------------------------------------
-- 3. dbo.rcni_raw
-- Grain: ONE ROW = ONE parsed RCNI discrepancy record.
-- Identifiers remain text. date_of_discrepancy is NVARCHAR, not DATE.
-- raw_record is NOT stored on this table.
-- -----------------------------------------------------------------------------
IF OBJECT_ID(N'dbo.rcni_raw', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.rcni_raw
    (
        rcni_raw_id                         BIGINT IDENTITY(1,1) NOT NULL
            CONSTRAINT PK_rcni_raw PRIMARY KEY CLUSTERED,
        issuer_id                           VARCHAR(20)         NOT NULL,
        coverage_year                       INT                 NULL,
        processing_year                     INT                 NULL,
        processing_month                    TINYINT             NULL,
        processing_day                      TINYINT             NULL,
        file_timestamp                      DATETIME2(0)        NULL,
        source_file                         NVARCHAR(500)       NOT NULL,
        source_path                         NVARCHAR(1500)      NOT NULL,
        file_hash                           CHAR(64)            NOT NULL,
        row_number_in_file                  BIGINT              NOT NULL,
        load_run_id                         UNIQUEIDENTIFIER    NOT NULL,
        loaded_at                           DATETIME2(0)        NOT NULL
            CONSTRAINT DF_rcni_raw_loaded_at DEFAULT SYSUTCDATETIME(),
        quality_status                      VARCHAR(30)         NOT NULL,
        exchange_assigned_policy_id         NVARCHAR(100)       NULL,
        plan_id                             NVARCHAR(100)       NULL,
        member_last_name                    NVARCHAR(255)       NULL,
        member_first_name                   NVARCHAR(255)       NULL,
        exchange_assigned_member_id         NVARCHAR(100)       NULL,
        issuer_assigned_member_id           NVARCHAR(100)       NULL,
        subscriber_last_name                NVARCHAR(255)       NULL,
        subscriber_first_name               NVARCHAR(255)       NULL,
        exchange_assigned_subscriber_id     NVARCHAR(100)       NULL,
        issuer_assigned_subscriber_id       NVARCHAR(100)       NULL,
        discrepancy_reason_code             NVARCHAR(100)       NULL,
        discrepancy_reason_text             NVARCHAR(500)       NULL,
        hix_value                           NVARCHAR(1000)      NULL,
        issuer_value                        NVARCHAR(1000)      NULL,
        date_of_discrepancy                 NVARCHAR(50)        NULL,
        recon_file_name                     NVARCHAR(255)       NULL,
        autofixed_by_hix                    NVARCHAR(50)        NULL,
        assignee                            NVARCHAR(100)       NULL,
        enrollment_status                   NVARCHAR(100)       NULL
    );
END;
GO


-- -----------------------------------------------------------------------------
-- 4. dbo.rcni_data_quality_issue
-- Technical anomalies. raw_record NVARCHAR(MAX) lives here, not on rcni_raw.
-- -----------------------------------------------------------------------------
IF OBJECT_ID(N'dbo.rcni_data_quality_issue', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.rcni_data_quality_issue
    (
        quality_issue_id        BIGINT IDENTITY(1,1) NOT NULL
            CONSTRAINT PK_rcni_data_quality_issue PRIMARY KEY CLUSTERED,
        load_run_id             UNIQUEIDENTIFIER    NULL,
        source_file             NVARCHAR(500)       NOT NULL,
        source_path             NVARCHAR(1500)      NOT NULL,
        file_hash               CHAR(64)            NOT NULL,
        issuer_id               VARCHAR(20)         NULL,
        coverage_year           INT                 NULL,
        row_number_in_file      BIGINT              NULL,
        physical_line_number    BIGINT              NULL,
        column_name             NVARCHAR(255)       NULL,
        invalid_value           NVARCHAR(MAX)       NULL,
        issue_code              VARCHAR(100)        NOT NULL,
        issue_message           NVARCHAR(1000)      NOT NULL,
        expected_column_count   INT                 NULL,
        observed_column_count   INT                 NULL,
        raw_record              NVARCHAR(MAX)       NULL,
        created_at              DATETIME2(0)        NOT NULL
            CONSTRAINT DF_rcni_dq_created DEFAULT SYSUTCDATETIME()
    );
END;
GO


-- -----------------------------------------------------------------------------
-- 5. dbo.rcni_stage
-- Permanent shared working table. Never TRUNCATE.
-- Delete only by load_run_id + file_hash (or file_hash on retry).
-- UX_rcni_stage_attempt is a UNIQUE CONSTRAINT here; do not recreate as an index.
-- -----------------------------------------------------------------------------
IF OBJECT_ID(N'dbo.rcni_stage', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.rcni_stage
    (
        stage_id                            BIGINT IDENTITY(1,1) NOT NULL
            CONSTRAINT PK_rcni_stage PRIMARY KEY CLUSTERED,
        load_run_id                         UNIQUEIDENTIFIER    NOT NULL,
        file_hash                           CHAR(64)            NOT NULL,
        issuer_id                           VARCHAR(20)         NOT NULL,
        coverage_year                       INT                 NULL,
        processing_year                     INT                 NULL,
        processing_month                    TINYINT             NULL,
        processing_day                      TINYINT             NULL,
        file_timestamp                      DATETIME2(0)        NULL,
        source_file                         NVARCHAR(500)       NOT NULL,
        source_path                         NVARCHAR(1500)      NOT NULL,
        row_number_in_file                  BIGINT              NOT NULL,
        quality_status                      VARCHAR(30)         NOT NULL,
        exchange_assigned_policy_id         NVARCHAR(100)       NULL,
        plan_id                             NVARCHAR(100)       NULL,
        member_last_name                    NVARCHAR(255)       NULL,
        member_first_name                   NVARCHAR(255)       NULL,
        exchange_assigned_member_id         NVARCHAR(100)       NULL,
        issuer_assigned_member_id           NVARCHAR(100)       NULL,
        subscriber_last_name                NVARCHAR(255)       NULL,
        subscriber_first_name               NVARCHAR(255)       NULL,
        exchange_assigned_subscriber_id     NVARCHAR(100)       NULL,
        issuer_assigned_subscriber_id       NVARCHAR(100)       NULL,
        discrepancy_reason_code             NVARCHAR(100)       NULL,
        discrepancy_reason_text             NVARCHAR(500)       NULL,
        hix_value                           NVARCHAR(1000)      NULL,
        issuer_value                        NVARCHAR(1000)      NULL,
        date_of_discrepancy                 NVARCHAR(50)        NULL,
        recon_file_name                     NVARCHAR(255)       NULL,
        autofixed_by_hix                    NVARCHAR(50)        NULL,
        assignee                            NVARCHAR(100)       NULL,
        enrollment_status                   NVARCHAR(100)       NULL,
        CONSTRAINT UX_rcni_stage_attempt UNIQUE (load_run_id, file_hash, row_number_in_file)
    );
END;
GO


-- =============================================================================
-- INDEXES
-- PK / UNIQUE constraints above already created their backing indexes.
-- Do not recreate PK_rcni_* or UX_rcni_stage_attempt.
-- =============================================================================

-- dbo.rcni_run_log
IF NOT EXISTS
(
    SELECT 1
    FROM sys.indexes
    WHERE name = N'IX_rcni_run_log_started'
      AND object_id = OBJECT_ID(N'dbo.rcni_run_log')
)
BEGIN
    CREATE INDEX IX_rcni_run_log_started
        ON dbo.rcni_run_log (started_at);
END;
GO

IF NOT EXISTS
(
    SELECT 1
    FROM sys.indexes
    WHERE name = N'IX_rcni_run_log_status'
      AND object_id = OBJECT_ID(N'dbo.rcni_run_log')
)
BEGIN
    CREATE INDEX IX_rcni_run_log_status
        ON dbo.rcni_run_log (status);
END;
GO

-- dbo.rcni_file_log
IF NOT EXISTS
(
    SELECT 1
    FROM sys.indexes
    WHERE name = N'IX_rcni_file_log_hash'
      AND object_id = OBJECT_ID(N'dbo.rcni_file_log')
)
BEGIN
    CREATE INDEX IX_rcni_file_log_hash
        ON dbo.rcni_file_log (file_hash, processing_status);
END;
GO

IF NOT EXISTS
(
    SELECT 1
    FROM sys.indexes
    WHERE name = N'IX_rcni_file_log_logical_identity'
      AND object_id = OBJECT_ID(N'dbo.rcni_file_log')
)
BEGIN
    CREATE INDEX IX_rcni_file_log_logical_identity
        ON dbo.rcni_file_log (issuer_id, document_type, coverage_year, file_timestamp);
END;
GO

IF NOT EXISTS
(
    SELECT 1
    FROM sys.indexes
    WHERE name = N'IX_rcni_file_log_run'
      AND object_id = OBJECT_ID(N'dbo.rcni_file_log')
)
BEGIN
    CREATE INDEX IX_rcni_file_log_run
        ON dbo.rcni_file_log (load_run_id);
END;
GO

IF NOT EXISTS
(
    SELECT 1
    FROM sys.indexes
    WHERE name = N'IX_rcni_file_log_processing_period'
      AND object_id = OBJECT_ID(N'dbo.rcni_file_log')
)
BEGIN
    CREATE INDEX IX_rcni_file_log_processing_period
        ON dbo.rcni_file_log (processing_year, processing_month);
END;
GO

-- dbo.rcni_raw
IF NOT EXISTS
(
    SELECT 1
    FROM sys.indexes
    WHERE name = N'UX_rcni_raw_file_row'
      AND object_id = OBJECT_ID(N'dbo.rcni_raw')
)
BEGIN
    CREATE UNIQUE INDEX UX_rcni_raw_file_row
        ON dbo.rcni_raw (file_hash, row_number_in_file);
END;
GO

IF NOT EXISTS
(
    SELECT 1
    FROM sys.indexes
    WHERE name = N'IX_rcni_raw_issuer_coverage'
      AND object_id = OBJECT_ID(N'dbo.rcni_raw')
)
BEGIN
    CREATE INDEX IX_rcni_raw_issuer_coverage
        ON dbo.rcni_raw (issuer_id, coverage_year);
END;
GO

IF NOT EXISTS
(
    SELECT 1
    FROM sys.indexes
    WHERE name = N'IX_rcni_raw_processing_period'
      AND object_id = OBJECT_ID(N'dbo.rcni_raw')
)
BEGIN
    CREATE INDEX IX_rcni_raw_processing_period
        ON dbo.rcni_raw (processing_year, processing_month);
END;
GO

IF NOT EXISTS
(
    SELECT 1
    FROM sys.indexes
    WHERE name = N'IX_rcni_raw_run'
      AND object_id = OBJECT_ID(N'dbo.rcni_raw')
)
BEGIN
    CREATE INDEX IX_rcni_raw_run
        ON dbo.rcni_raw (load_run_id);
END;
GO

IF NOT EXISTS
(
    SELECT 1
    FROM sys.indexes
    WHERE name = N'IX_rcni_raw_source_file'
      AND object_id = OBJECT_ID(N'dbo.rcni_raw')
)
BEGIN
    CREATE INDEX IX_rcni_raw_source_file
        ON dbo.rcni_raw (source_file);
END;
GO

-- dbo.rcni_data_quality_issue
IF NOT EXISTS
(
    SELECT 1
    FROM sys.indexes
    WHERE name = N'IX_rcni_dq_file_hash'
      AND object_id = OBJECT_ID(N'dbo.rcni_data_quality_issue')
)
BEGIN
    CREATE INDEX IX_rcni_dq_file_hash
        ON dbo.rcni_data_quality_issue (file_hash);
END;
GO

IF NOT EXISTS
(
    SELECT 1
    FROM sys.indexes
    WHERE name = N'IX_rcni_dq_run'
      AND object_id = OBJECT_ID(N'dbo.rcni_data_quality_issue')
)
BEGIN
    CREATE INDEX IX_rcni_dq_run
        ON dbo.rcni_data_quality_issue (load_run_id);
END;
GO

IF NOT EXISTS
(
    SELECT 1
    FROM sys.indexes
    WHERE name = N'IX_rcni_dq_issue_code'
      AND object_id = OBJECT_ID(N'dbo.rcni_data_quality_issue')
)
BEGIN
    CREATE INDEX IX_rcni_dq_issue_code
        ON dbo.rcni_data_quality_issue (issue_code);
END;
GO

IF NOT EXISTS
(
    SELECT 1
    FROM sys.indexes
    WHERE name = N'IX_rcni_dq_issuer_coverage'
      AND object_id = OBJECT_ID(N'dbo.rcni_data_quality_issue')
)
BEGIN
    CREATE INDEX IX_rcni_dq_issuer_coverage
        ON dbo.rcni_data_quality_issue (issuer_id, coverage_year);
END;
GO

IF NOT EXISTS
(
    SELECT 1
    FROM sys.indexes
    WHERE name = N'UX_rcni_dq_row_issue'
      AND object_id = OBJECT_ID(N'dbo.rcni_data_quality_issue')
)
BEGIN
    CREATE UNIQUE INDEX UX_rcni_dq_row_issue
        ON dbo.rcni_data_quality_issue (file_hash, row_number_in_file, issue_code, column_name)
        WHERE row_number_in_file IS NOT NULL;
END;
GO

IF NOT EXISTS
(
    SELECT 1
    FROM sys.indexes
    WHERE name = N'UX_rcni_dq_file_issue'
      AND object_id = OBJECT_ID(N'dbo.rcni_data_quality_issue')
)
BEGIN
    CREATE UNIQUE INDEX UX_rcni_dq_file_issue
        ON dbo.rcni_data_quality_issue (file_hash, issue_code)
        WHERE row_number_in_file IS NULL;
END;
GO

-- dbo.rcni_stage
-- UX_rcni_stage_attempt already exists as a UNIQUE CONSTRAINT on the table.
IF NOT EXISTS
(
    SELECT 1
    FROM sys.indexes
    WHERE name = N'IX_rcni_stage_run_hash'
      AND object_id = OBJECT_ID(N'dbo.rcni_stage')
)
BEGIN
    CREATE INDEX IX_rcni_stage_run_hash
        ON dbo.rcni_stage (load_run_id, file_hash);
END;
GO

IF NOT EXISTS
(
    SELECT 1
    FROM sys.indexes
    WHERE name = N'IX_rcni_stage_file_row'
      AND object_id = OBJECT_ID(N'dbo.rcni_stage')
)
BEGIN
    CREATE INDEX IX_rcni_stage_file_row
        ON dbo.rcni_stage (file_hash, row_number_in_file);
END;
GO


-- =============================================================================
-- VERIFICATION (commented out — do not execute as part of this script)
-- =============================================================================
--
-- SELECT
--     s.name AS schema_name,
--     t.name AS table_name
-- FROM sys.tables AS t
-- INNER JOIN sys.schemas AS s ON s.schema_id = t.schema_id
-- WHERE t.name IN (
--     N'rcni_run_log',
--     N'rcni_file_log',
--     N'rcni_raw',
--     N'rcni_data_quality_issue',
--     N'rcni_stage'
-- )
-- ORDER BY t.name;
--
-- SELECT
--     OBJECT_SCHEMA_NAME(i.object_id) AS schema_name,
--     OBJECT_NAME(i.object_id) AS table_name,
--     i.name AS index_name,
--     i.is_unique,
--     i.has_filter,
--     i.filter_definition
-- FROM sys.indexes AS i
-- WHERE OBJECT_NAME(i.object_id) IN (
--     N'rcni_run_log',
--     N'rcni_file_log',
--     N'rcni_raw',
--     N'rcni_data_quality_issue',
--     N'rcni_stage'
-- )
--   AND i.name IS NOT NULL
-- ORDER BY table_name, index_name;
--
-- SELECT COUNT(*) AS rcni_run_log_rows FROM dbo.rcni_run_log;
-- SELECT COUNT(*) AS rcni_file_log_rows FROM dbo.rcni_file_log;
-- SELECT COUNT(*) AS rcni_raw_rows FROM dbo.rcni_raw;
-- SELECT COUNT(*) AS rcni_data_quality_issue_rows FROM dbo.rcni_data_quality_issue;
-- SELECT COUNT(*) AS rcni_stage_rows FROM dbo.rcni_stage;
--
-- SELECT TOP (10) * FROM dbo.rcni_run_log;
-- SELECT TOP (10) * FROM dbo.rcni_file_log;
-- SELECT TOP (10) * FROM dbo.rcni_raw;
-- SELECT TOP (10) * FROM dbo.rcni_data_quality_issue;
-- SELECT TOP (10) * FROM dbo.rcni_stage;
--
