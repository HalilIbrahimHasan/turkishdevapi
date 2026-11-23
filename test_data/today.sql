-- =============================================================================
-- Azure SQL DDL: outbound_automation raw ingestion (NEW TABLES ONLY)
-- =============================================================================
-- Status: MANUAL EXECUTION ONLY (SSMS) — review before running.
-- Mirrors sql/inbound_automation_ddl.sql 1:1 with inbound -> outbound renames.
-- Does NOT modify dbo.inbound_automation, dbo.inbound_automation_run_log,
-- dbo.inbound_automation_file_log, or any other existing table.
--
-- Tables:
--   1. dbo.outbound_automation          — one row per Parser834 enrollee
--   2. dbo.outbound_automation_run_log  — one row per load run
--   3. dbo.outbound_automation_file_log — one row per successfully processed file
--
-- Safety: CREATE TABLE IF NOT EXISTS only. No DROP / TRUNCATE / ALTER.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. dbo.outbound_automation
-- -----------------------------------------------------------------------------
IF OBJECT_ID(N'dbo.outbound_automation', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.outbound_automation (
        -- surrogate / run
        id                              BIGINT IDENTITY(1,1) NOT NULL,
        load_run_id                     NVARCHAR(100)        NOT NULL,
        loaded_at                       DATETIME2(3)         NOT NULL
            CONSTRAINT DF_outbound_automation_loaded_at DEFAULT SYSUTCDATETIME(),

        -- automation lineage
        folder_year                     INT                  NOT NULL,
        folder_month                    INT                  NOT NULL,
        filename_file_year              INT                  NULL,
        filename_file_month             INT                  NULL,
        source_file                     NVARCHAR(500)        NOT NULL,
        source_file_path                NVARCHAR(1000)       NOT NULL,
        file_hash                       NVARCHAR(128)        NOT NULL,
        row_number_in_file              INT                  NOT NULL,
        raw_record_hash                 NVARCHAR(128)        NOT NULL,

        -- provenance / coverage (runner-added)
        parser_version                  NVARCHAR(50)         NULL,
        runner_version                  NVARCHAR(50)         NULL,
        git_commit                      NVARCHAR(100)        NULL,
        coverage_year                   INT                  NULL,
        coverage_year_source            NVARCHAR(50)         NULL,
        warning_count                   INT                  NULL,

        -- derived (not parser-native)
        insurance_type                  NVARCHAR(50)         NULL,
        enrolleeStatus                  NVARCHAR(50)         NULL,

        -- Parser834 keys (43) — exact snake_case names from parse_file()
        issuer                          NVARCHAR(20)         NOT NULL,
        year                            NVARCHAR(4)          NOT NULL,
        month                           NVARCHAR(2)          NOT NULL,
        file_name                       NVARCHAR(500)        NOT NULL,
        raw_xml_path                    NVARCHAR(1000)       NOT NULL,
        created_at                      NVARCHAR(40)         NOT NULL,

        policy_id                       NVARCHAR(100)        NULL,
        member_id                       NVARCHAR(100)        NULL,          -- PII: member identifier
        subscriber_id                   NVARCHAR(100)        NULL,          -- PII: member identifier
        exchg_assigned_enrollee_id      NVARCHAR(100)        NULL,          -- PII: member identifier
        issuer_subscriber_identifier    NVARCHAR(100)        NULL,          -- PII: member identifier
        issuer_indiv_identifier         NVARCHAR(100)        NULL,          -- PII: member identifier
        member_first_name               NVARCHAR(200)        NULL,          -- PII
        member_last_name                NVARCHAR(200)        NULL,          -- PII
        relationship                    NVARCHAR(50)         NULL,
        subscriber_flag                 NVARCHAR(20)         NULL,
        enrollee_event_type_code        NVARCHAR(50)         NULL,
        enrollee_event_reason_code      NVARCHAR(50)         NULL,
        action_code                     NVARCHAR(50)         NULL,
        action_code_description         NVARCHAR(100)        NULL,
        maintenance_type_code           NVARCHAR(50)         NULL,
        additional_maint_reason_code    NVARCHAR(50)         NULL,
        coverage_status                 NVARCHAR(100)        NULL,
        benefit_effective_date          DATE                 NULL,
        benefit_end_date                DATE                 NULL,
        member_maint_effective_date     DATE                 NULL,
        last_premium_paid_date          NVARCHAR(20)         NULL,
        request_submit_timestamp        NVARCHAR(100)        NULL,
        total_premium_amount            DECIMAL(18,4)        NULL,
        individual_responsibility_amount DECIMAL(18,4)       NULL,
        aptc_amount                     DECIMAL(18,4)        NULL,
        user_fee_amount                 DECIMAL(18,4)        NULL,
        insurance_type_code             NVARCHAR(50)         NULL,
        health_coverage_policy_no       NVARCHAR(100)        NULL,
        household_or_employee_case_id   NVARCHAR(100)        NULL,
        rating_area                     NVARCHAR(50)         NULL,
        source_exchg_id                 NVARCHAR(100)        NULL,
        enrollment_action_code          NVARCHAR(50)         NULL,
        insurer_tax_id_number           NVARCHAR(50)         NULL,
        qtyn                            NVARCHAR(50)         NULL,
        qtyy                            NVARCHAR(50)         NULL,
        qtyt                            NVARCHAR(50)         NULL,
        raw_payload                     NVARCHAR(MAX)        NOT NULL,

        -- lossless enriched backup (parser row + automation + derived + provenance)
        raw_json                        NVARCHAR(MAX)        NOT NULL,

        CONSTRAINT PK_outbound_automation PRIMARY KEY CLUSTERED (id),
        CONSTRAINT UQ_outbound_automation_file_row UNIQUE (file_hash, row_number_in_file)
    );
END;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_outbound_automation_source_file'
      AND object_id = OBJECT_ID(N'dbo.outbound_automation')
)
    CREATE INDEX IX_outbound_automation_source_file
        ON dbo.outbound_automation (source_file);
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_outbound_automation_issuer_folder'
      AND object_id = OBJECT_ID(N'dbo.outbound_automation')
)
    CREATE INDEX IX_outbound_automation_issuer_folder
        ON dbo.outbound_automation (issuer, folder_year, folder_month);
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_outbound_automation_issuer_filename_month'
      AND object_id = OBJECT_ID(N'dbo.outbound_automation')
)
    CREATE INDEX IX_outbound_automation_issuer_filename_month
        ON dbo.outbound_automation (issuer, filename_file_year, filename_file_month);
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_outbound_automation_coverage_year'
      AND object_id = OBJECT_ID(N'dbo.outbound_automation')
)
    CREATE INDEX IX_outbound_automation_coverage_year
        ON dbo.outbound_automation (issuer, coverage_year);
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_outbound_automation_policy_id'
      AND object_id = OBJECT_ID(N'dbo.outbound_automation')
)
    CREATE INDEX IX_outbound_automation_policy_id
        ON dbo.outbound_automation (policy_id);
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_outbound_automation_member_id'
      AND object_id = OBJECT_ID(N'dbo.outbound_automation')
)
    CREATE INDEX IX_outbound_automation_member_id
        ON dbo.outbound_automation (member_id);
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_outbound_automation_load_run_id'
      AND object_id = OBJECT_ID(N'dbo.outbound_automation')
)
    CREATE INDEX IX_outbound_automation_load_run_id
        ON dbo.outbound_automation (load_run_id);
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_outbound_automation_file_hash'
      AND object_id = OBJECT_ID(N'dbo.outbound_automation')
)
    CREATE INDEX IX_outbound_automation_file_hash
        ON dbo.outbound_automation (file_hash);
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_outbound_automation_enrolleeStatus'
      AND object_id = OBJECT_ID(N'dbo.outbound_automation')
)
    CREATE INDEX IX_outbound_automation_enrolleeStatus
        ON dbo.outbound_automation (enrolleeStatus);
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_outbound_automation_insurance_type'
      AND object_id = OBJECT_ID(N'dbo.outbound_automation')
)
    CREATE INDEX IX_outbound_automation_insurance_type
        ON dbo.outbound_automation (insurance_type);
GO


-- -----------------------------------------------------------------------------
-- 2. dbo.outbound_automation_run_log
-- -----------------------------------------------------------------------------
IF OBJECT_ID(N'dbo.outbound_automation_run_log', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.outbound_automation_run_log (
        load_run_id                 NVARCHAR(100)    NOT NULL,
        started_at                  DATETIME2(3)     NOT NULL,
        completed_at                DATETIME2(3)     NULL,
        run_mode                    NVARCHAR(20)     NOT NULL,   -- dry_run | load | create_table
        source_mode                 NVARCHAR(20)     NOT NULL,   -- local | sftp
        year_filter                 NVARCHAR(50)     NULL,       -- e.g. 2025 or ALL
        issuer_filter               NVARCHAR(200)    NULL,
        month_filter                NVARCHAR(50)     NULL,

        parser_version              NVARCHAR(50)     NULL,
        runner_version              NVARCHAR(50)     NULL,
        git_commit                  NVARCHAR(100)    NULL,

        files_discovered            INT              NOT NULL DEFAULT 0,
        files_parsed                INT              NOT NULL DEFAULT 0,
        files_loaded                INT              NOT NULL DEFAULT 0,
        files_skipped_duplicate     INT              NOT NULL DEFAULT 0,
        files_failed                INT              NOT NULL DEFAULT 0,
        rows_parsed                 INT              NOT NULL DEFAULT 0,
        rows_inserted               INT              NOT NULL DEFAULT 0,
        rows_skipped                INT              NOT NULL DEFAULT 0,
        total_warning_count         INT              NULL,

        status                      NVARCHAR(20)     NOT NULL,   -- running | success | failed | dry_run
        error_summary               NVARCHAR(MAX)    NULL,
        report_output_path          NVARCHAR(1000)   NULL,

        CONSTRAINT PK_outbound_automation_run_log PRIMARY KEY (load_run_id)
    );
END;
GO


-- -----------------------------------------------------------------------------
-- 3. dbo.outbound_automation_file_log
-- -----------------------------------------------------------------------------
IF OBJECT_ID(N'dbo.outbound_automation_file_log', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.outbound_automation_file_log (
        id                      BIGINT IDENTITY(1,1) NOT NULL,
        load_run_id             NVARCHAR(100)        NOT NULL,
        loaded_at               DATETIME2(3)         NOT NULL,

        issuer                  NVARCHAR(20)         NOT NULL,
        folder_year             INT                  NOT NULL,
        folder_month            INT                  NOT NULL,
        filename_file_year      INT                  NULL,
        filename_file_month     INT                  NULL,

        source_file             NVARCHAR(500)        NOT NULL,
        source_file_path        NVARCHAR(1000)       NOT NULL,
        file_hash               NVARCHAR(128)        NOT NULL,
        file_size_bytes         BIGINT               NULL,

        parse_status            NVARCHAR(20)         NOT NULL,   -- loaded | skipped_duplicate | failed | dry_run
        row_count               INT                  NOT NULL DEFAULT 0,
        parse_duration_ms       INT                  NULL,
        error_message           NVARCHAR(MAX)        NULL,

        CONSTRAINT PK_outbound_automation_file_log PRIMARY KEY CLUSTERED (id),
        CONSTRAINT UQ_outbound_automation_file_log_hash UNIQUE (file_hash)
    );
END;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_outbound_automation_file_log_run'
      AND object_id = OBJECT_ID(N'dbo.outbound_automation_file_log')
)
    CREATE INDEX IX_outbound_automation_file_log_run
        ON dbo.outbound_automation_file_log (load_run_id);
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_outbound_automation_file_log_source_file'
      AND object_id = OBJECT_ID(N'dbo.outbound_automation_file_log')
)
    CREATE INDEX IX_outbound_automation_file_log_source_file
        ON dbo.outbound_automation_file_log (source_file);
GO
