SELECT COUNT(*) AS main_rows
FROM dbo.outbound_automation;

SELECT COUNT(*) AS file_log_rows
FROM dbo.outbound_automation_file_log;

SELECT COUNT(*) AS run_log_rows
FROM dbo.outbound_automation_run_log;


-- =============================================================================
-- Azure SQL DDL v2: outbound_automation (TO files) — FINAL SCHEMA PROPOSAL
-- =============================================================================
-- Status: MANUAL EXECUTION ONLY (SSMS) — review/approve before running.
--
-- Purpose: rebuild the four outbound-only objects so they represent the real
-- outbound TO 834 data model (supersedes sql/outbound_automation_ddl.sql v1).
--
-- Objects dropped/created by this script (and NOTHING else):
--   dbo.outbound_automation_monthly_premium   (new child table)
--   dbo.outbound_automation                    (one row per outbound enrollee transaction)
--   dbo.outbound_automation_file_log          (one row per processed file)
--   dbo.outbound_automation_run_log           (one row per run)
--
-- Safety:
--   * Batch 1 aborts the whole script (SET NOEXEC ON) if any existing outbound
--     table contains rows. Drops only run when every outbound table is empty.
--   * Works on a fresh database too (all drops are IF EXISTS).
--   * No reference to any non-outbound table.
-- =============================================================================

SET NOCOUNT ON;
GO

-- -----------------------------------------------------------------------------
-- 0. Guard: refuse to drop non-empty outbound tables
-- -----------------------------------------------------------------------------
DECLARE @blocked NVARCHAR(400) = N'';

IF OBJECT_ID(N'dbo.outbound_automation_monthly_premium', N'U') IS NOT NULL
BEGIN
    IF EXISTS (SELECT 1 FROM dbo.outbound_automation_monthly_premium)
        SET @blocked += N' dbo.outbound_automation_monthly_premium';
END;
IF OBJECT_ID(N'dbo.outbound_automation', N'U') IS NOT NULL
BEGIN
    IF EXISTS (SELECT 1 FROM dbo.outbound_automation)
        SET @blocked += N' dbo.outbound_automation';
END;
IF OBJECT_ID(N'dbo.outbound_automation_file_log', N'U') IS NOT NULL
BEGIN
    IF EXISTS (SELECT 1 FROM dbo.outbound_automation_file_log)
        SET @blocked += N' dbo.outbound_automation_file_log';
END;
IF OBJECT_ID(N'dbo.outbound_automation_run_log', N'U') IS NOT NULL
BEGIN
    IF EXISTS (SELECT 1 FROM dbo.outbound_automation_run_log)
        SET @blocked += N' dbo.outbound_automation_run_log';
END;

IF @blocked <> N''
BEGIN
    RAISERROR(N'ABORTED: outbound table(s) not empty:%s. Nothing was dropped.', 16, 1, @blocked);
    SET NOEXEC ON;
END;
GO

-- -----------------------------------------------------------------------------
-- 1. Drop outbound-only tables (child first)
-- -----------------------------------------------------------------------------
DROP TABLE IF EXISTS dbo.outbound_automation_monthly_premium;
DROP TABLE IF EXISTS dbo.outbound_automation;
DROP TABLE IF EXISTS dbo.outbound_automation_file_log;
DROP TABLE IF EXISTS dbo.outbound_automation_run_log;
GO

-- -----------------------------------------------------------------------------
-- 2. dbo.outbound_automation — one row per <enrollee> transaction
-- -----------------------------------------------------------------------------
CREATE TABLE dbo.outbound_automation (
    -- surrogate / run
    id                              BIGINT IDENTITY(1,1) NOT NULL,
    load_run_id                     NVARCHAR(100)        NOT NULL,
    loaded_at                       DATETIME2(3)         NOT NULL
        CONSTRAINT DF_outbound_automation_loaded_at DEFAULT SYSUTCDATETIME(),

    -- source lineage
    issuer                          NVARCHAR(20)         NOT NULL,
    folder_year                     INT                  NOT NULL,
    folder_month                    INT                  NOT NULL,
    filename_file_year              INT                  NULL,
    filename_file_month             INT                  NULL,
    source_file                     NVARCHAR(500)        NOT NULL,
    source_file_path                NVARCHAR(1000)       NOT NULL,
    file_hash                       NVARCHAR(128)        NOT NULL,
    row_number_in_file              INT                  NOT NULL,
    raw_record_hash                 NVARCHAR(128)        NOT NULL,

    -- provenance / data quality
    parser_version                  NVARCHAR(50)         NULL,
    runner_version                  NVARCHAR(50)         NULL,
    git_commit                      NVARCHAR(100)        NULL,
    warning_count                   INT                  NULL,
    warning_codes                   NVARCHAR(2000)       NULL,

    -- transaction identity / classification
    enrollment_event_id             NVARCHAR(100)        NULL,   -- enrollee/enrollmentEventId (indexed, NOT unique)
    enrollment_action_code          NVARCHAR(50)         NULL,   -- enrollment/actionCode (BGN08)
    enrollee_event_type_code        NVARCHAR(50)         NULL,   -- enrollmentEvents/eventTypeLkp (INS03)
    enrollee_event_reason_code      NVARCHAR(50)         NULL,   -- enrollmentEvents/eventReasonLkp (INS04)
    maintenance_type_code           NVARCHAR(50)         NULL,   -- healthCoverage/maintenanceTypeCode (HD01)
    additional_maint_reason_code    NVARCHAR(50)         NULL,   -- memberReportingCategory/additionalMaintReason
    outbound_transaction_type       NVARCHAR(30)         NULL,   -- derived: ADD|CHANGE|CANCEL|TERM|CANCEL_OR_TERM|REINSTATE
    request_submit_timestamp        NVARCHAR(100)        NULL,   -- raw text; format not yet confirmed
    payment_txn_id                  NVARCHAR(100)        NULL,

    -- policy / member identifiers
    policy_id                       NVARCHAR(100)        NOT NULL, -- exchgAssignedPolicyID
    previous_policy_id              NVARCHAR(100)        NULL,
    member_id                       NVARCHAR(100)        NOT NULL, -- exchgIndivIdentifier
    subscriber_id                   NVARCHAR(100)        NULL,     -- exchgSubscriberIdentifier
    issuer_subscriber_identifier    NVARCHAR(100)        NULL,
    issuer_indiv_identifier         NVARCHAR(100)        NULL,
    subscriber_flag                 NVARCHAR(20)         NULL,
    relationship                    NVARCHAR(50)         NULL,
    member_first_name               NVARCHAR(200)        NULL,     -- PII
    member_last_name                NVARCHAR(200)        NULL,     -- PII

    -- coverage / plan
    insurance_type_code             NVARCHAR(50)         NULL,
    insurance_type                  NVARCHAR(50)         NULL,     -- configured map; NULL when code unknown
    insurer_cms_plan_id             NVARCHAR(50)         NULL,
    class_of_contract_code          NVARCHAR(50)         NULL,
    health_coverage_policy_no       NVARCHAR(100)        NULL,
    household_or_employee_case_id   NVARCHAR(100)        NULL,
    benefit_effective_date          DATE                 NULL,     -- benefitEffectiveBeginDate
    benefit_end_date                DATE                 NULL,
    member_maint_effective_date     DATE                 NULL,
    last_premium_paid_date          DATE                 NULL,
    coverage_year                   INT                  NULL,     -- year(benefit_effective_date) only
    coverage_year_source            NVARCHAR(50)         NULL,

    -- amounts / reporting category
    total_premium_amount            DECIMAL(18,4)        NULL,
    individual_responsibility_amount DECIMAL(18,4)       NULL,
    aptc_amount                     DECIMAL(18,4)        NULL,
    health_coverage_premium_amount  DECIMAL(18,4)        NULL,
    rating_area                     NVARCHAR(50)         NULL,
    source_exchg_id                 NVARCHAR(100)        NULL,

    -- enrollment control totals (QTY)
    qtyn                            NVARCHAR(50)         NULL,
    qtyy                            NVARCHAR(50)         NULL,
    qtyt                            NVARCHAR(50)         NULL,

    -- lossless source record (header + GS_Info + enrollment context + full enrollee subtree)
    source_xml_json                 NVARCHAR(MAX)        NOT NULL,

    CONSTRAINT PK_outbound_automation PRIMARY KEY CLUSTERED (id),
    CONSTRAINT UQ_outbound_automation_file_row UNIQUE (file_hash, row_number_in_file)
);
GO

CREATE INDEX IX_outbound_automation_source_file
    ON dbo.outbound_automation (source_file);
CREATE INDEX IX_outbound_automation_load_run_id
    ON dbo.outbound_automation (load_run_id);
CREATE INDEX IX_outbound_automation_issuer_folder
    ON dbo.outbound_automation (issuer, folder_year, folder_month);
CREATE INDEX IX_outbound_automation_issuer_filename_month
    ON dbo.outbound_automation (issuer, filename_file_year, filename_file_month);
CREATE INDEX IX_outbound_automation_issuer_coverage_txn
    ON dbo.outbound_automation (issuer, coverage_year, outbound_transaction_type);
CREATE INDEX IX_outbound_automation_policy_lifecycle
    ON dbo.outbound_automation (policy_id, member_id, request_submit_timestamp);
CREATE INDEX IX_outbound_automation_member_id
    ON dbo.outbound_automation (member_id);
CREATE INDEX IX_outbound_automation_enrollment_event_id
    ON dbo.outbound_automation (enrollment_event_id);
CREATE INDEX IX_outbound_automation_previous_policy_id
    ON dbo.outbound_automation (previous_policy_id);
CREATE INDEX IX_outbound_automation_issuer_plan
    ON dbo.outbound_automation (issuer, insurer_cms_plan_id);
GO

-- -----------------------------------------------------------------------------
-- 3. dbo.outbound_automation_monthly_premium — one row per <premium> element
-- -----------------------------------------------------------------------------
CREATE TABLE dbo.outbound_automation_monthly_premium (
    id                      BIGINT IDENTITY(1,1) NOT NULL,
    load_run_id             NVARCHAR(100)        NOT NULL,
    loaded_at               DATETIME2(3)         NOT NULL
        CONSTRAINT DF_outbound_automation_monthly_premium_loaded_at DEFAULT SYSUTCDATETIME(),

    -- parent lineage
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
        UNIQUE (file_hash, row_number_in_file, premium_seq),
    CONSTRAINT FK_outbound_automation_monthly_premium_parent
        FOREIGN KEY (file_hash, row_number_in_file)
        REFERENCES dbo.outbound_automation (file_hash, row_number_in_file)
);
GO

CREATE INDEX IX_outbound_automation_monthly_premium_policy_period
    ON dbo.outbound_automation_monthly_premium (policy_id, premium_year, premium_month);
CREATE INDEX IX_outbound_automation_monthly_premium_event
    ON dbo.outbound_automation_monthly_premium (enrollment_event_id);
CREATE INDEX IX_outbound_automation_monthly_premium_run
    ON dbo.outbound_automation_monthly_premium (load_run_id);
GO

-- -----------------------------------------------------------------------------
-- 4. dbo.outbound_automation_run_log
-- -----------------------------------------------------------------------------
CREATE TABLE dbo.outbound_automation_run_log (
    load_run_id                 NVARCHAR(100)    NOT NULL,
    started_at                  DATETIME2(3)     NOT NULL,
    completed_at                DATETIME2(3)     NULL,
    run_mode                    NVARCHAR(20)     NOT NULL,   -- dry_run | load
    source_mode                 NVARCHAR(20)     NOT NULL,   -- local
    year_filter                 NVARCHAR(50)     NULL,
    issuer_filter               NVARCHAR(200)    NULL,
    month_filter                NVARCHAR(50)     NULL,

    parser_version              NVARCHAR(50)     NULL,
    runner_version              NVARCHAR(50)     NULL,
    git_commit                  NVARCHAR(100)    NULL,

    files_discovered            INT              NOT NULL
        CONSTRAINT DF_outbound_automation_run_log_files_discovered DEFAULT 0,
    files_parsed                INT              NOT NULL
        CONSTRAINT DF_outbound_automation_run_log_files_parsed DEFAULT 0,
    files_loaded                INT              NOT NULL
        CONSTRAINT DF_outbound_automation_run_log_files_loaded DEFAULT 0,
    files_skipped_duplicate     INT              NOT NULL
        CONSTRAINT DF_outbound_automation_run_log_files_skipped_duplicate DEFAULT 0,
    files_failed                INT              NOT NULL
        CONSTRAINT DF_outbound_automation_run_log_files_failed DEFAULT 0,
    rows_parsed                 INT              NOT NULL
        CONSTRAINT DF_outbound_automation_run_log_rows_parsed DEFAULT 0,
    rows_inserted               INT              NOT NULL
        CONSTRAINT DF_outbound_automation_run_log_rows_inserted DEFAULT 0,
    rows_skipped                INT              NOT NULL
        CONSTRAINT DF_outbound_automation_run_log_rows_skipped DEFAULT 0,
    premium_rows_inserted       INT              NOT NULL
        CONSTRAINT DF_outbound_automation_run_log_premium_rows_inserted DEFAULT 0,
    total_warning_count         INT              NULL,
    unknown_path_count          INT              NULL,

    status                      NVARCHAR(20)     NOT NULL,   -- running | success | failed
    error_summary               NVARCHAR(MAX)    NULL,
    report_output_path          NVARCHAR(1000)   NULL,

    CONSTRAINT PK_outbound_automation_run_log PRIMARY KEY (load_run_id)
);
GO

-- -----------------------------------------------------------------------------
-- 5. dbo.outbound_automation_file_log
-- -----------------------------------------------------------------------------
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

    txn_create_datetime     DATETIME2(0)         NULL,   -- enrollments/txnCreateDateTime
    job_execution_id        NVARCHAR(100)        NULL,   -- enrollments/jobExecutionId

    parse_status            NVARCHAR(20)         NOT NULL,   -- loaded | failed
    row_count               INT                  NOT NULL
        CONSTRAINT DF_outbound_automation_file_log_row_count DEFAULT 0,
    premium_row_count       INT                  NULL,
    unknown_path_count      INT                  NULL,
    parse_duration_ms       INT                  NULL,
    error_message           NVARCHAR(MAX)        NULL,

    CONSTRAINT PK_outbound_automation_file_log PRIMARY KEY CLUSTERED (id),
    CONSTRAINT UQ_outbound_automation_file_log_hash UNIQUE (file_hash)
);
GO

CREATE INDEX IX_outbound_automation_file_log_run
    ON dbo.outbound_automation_file_log (load_run_id);
CREATE INDEX IX_outbound_automation_file_log_source_file
    ON dbo.outbound_automation_file_log (source_file);
CREATE INDEX IX_outbound_automation_file_log_job
    ON dbo.outbound_automation_file_log (job_execution_id);
GO

SET NOEXEC OFF;
GO
