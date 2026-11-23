


.\.venv\Scripts\python.exe run_outbound_automation_load.py --dry-run --issuer 15105 --year 2026 --month 10
-- =============================================================================
-- Azure SQL RECOVERY DDL: dbo.outbound_automation_monthly_premium
-- =============================================================================
-- Status: MANUAL EXECUTION ONLY (SSMS).
--
-- Purpose: create the one object that failed during outbound_automation_ddl_v2.sql
-- (REFERENCES permission denied on the FK). Create-only and idempotent:
--   * creates dbo.outbound_automation_monthly_premium only if it does not exist
--   * creates its indexes only if they do not exist
--   * no DROP / ALTER / TRUNCATE / DELETE of any object
--   * no FOREIGN KEY; parent link (file_hash, row_number_in_file) to
--     dbo.outbound_automation is enforced by the outbound writer
-- =============================================================================

SET NOCOUNT ON;
GO

IF OBJECT_ID(N'dbo.outbound_automation_monthly_premium', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.outbound_automation_monthly_premium (
        id                      BIGINT IDENTITY(1,1) NOT NULL,
        load_run_id             NVARCHAR(100)        NOT NULL,
        loaded_at               DATETIME2(3)         NOT NULL
            CONSTRAINT DF_outbound_automation_monthly_premium_loaded_at DEFAULT SYSUTCDATETIME(),

        -- logical parent key: (file_hash, row_number_in_file) in dbo.outbound_automation
        file_hash               NVARCHAR(128)        NOT NULL,
        row_number_in_file      INT                  NOT NULL,
        premium_seq             INT                  NOT NULL,   -- 1..N document order within parent

        -- denormalized parent keys
        issuer                  NVARCHAR(20)         NOT NULL,
        policy_id               NVARCHAR(100)        NOT NULL,
        member_id               NVARCHAR(100)        NOT NULL,
        enrollment_event_id     NVARCHAR(100)        NULL,

        -- premium values
        month_start_date        DATE                 NULL,
        premium_year            INT                  NULL,
        premium_month           INT                  NULL,
        gross_premium_amount    DECIMAL(18,4)        NULL,
        aptc_amount             DECIMAL(18,4)        NULL,
        net_premium_amount      DECIMAL(18,4)        NULL,

        -- lossless <premium> element (unknown/future tags, e.g. state subsidy)
        premium_json            NVARCHAR(MAX)        NOT NULL,

        CONSTRAINT PK_outbound_automation_monthly_premium PRIMARY KEY CLUSTERED (id),
        CONSTRAINT UQ_outbound_automation_monthly_premium_row
            UNIQUE (file_hash, row_number_in_file, premium_seq)
    );
END;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_outbound_automation_monthly_premium_policy_period'
      AND object_id = OBJECT_ID(N'dbo.outbound_automation_monthly_premium')
)
    CREATE INDEX IX_outbound_automation_monthly_premium_policy_period
        ON dbo.outbound_automation_monthly_premium (policy_id, premium_year, premium_month);
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_outbound_automation_monthly_premium_event'
      AND object_id = OBJECT_ID(N'dbo.outbound_automation_monthly_premium')
)
    CREATE INDEX IX_outbound_automation_monthly_premium_event
        ON dbo.outbound_automation_monthly_premium (enrollment_event_id);
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_outbound_automation_monthly_premium_run'
      AND object_id = OBJECT_ID(N'dbo.outbound_automation_monthly_premium')
)
    CREATE INDEX IX_outbound_automation_monthly_premium_run
        ON dbo.outbound_automation_monthly_premium (load_run_id);
GO
