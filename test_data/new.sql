SELECT
    issuer AS [HIOS Issuer ID],
    insurance_type AS [Insurance Type],
    coverage_year AS [Coverage Year],
    folder_year AS [Source Folder Year],

    COALESCE(
        NULLIF(LTRIM(RTRIM(policy_id)), ''),
        NULLIF(LTRIM(RTRIM(health_coverage_policy_no)), '')
    ) AS [Policy ID],

    COALESCE(
        NULLIF(LTRIM(RTRIM(member_id)), ''),
        NULLIF(LTRIM(RTRIM(issuer_indiv_identifier)), ''),
        NULLIF(LTRIM(RTRIM(exchg_assigned_enrollee_id)), '')
    ) AS [Enrollee ID],

    policy_id AS [Original Policy ID],
    health_coverage_policy_no AS [Health Coverage Policy Number],

    member_id AS [Original Member ID],
    issuer_indiv_identifier AS [Issuer Individual Identifier],
    exchg_assigned_enrollee_id AS [Exchange Assigned Enrollee ID],

    enrollee_status AS [Enrollee Status],
    maintenance_type_code AS [Maintenance Type Code],

    member_maint_effective_date AS [Enrollment / Maintenance Effective Date],

    source_file_name AS [Source File Name],
    loaded_at AS [Azure Loaded Date]

FROM dbo.inbound_automation
WHERE issuer = '83502'
ORDER BY
    coverage_year,
    [Policy ID],
    [Enrollee ID],
    member_maint_effective_date,
    source_file_name;


SELECT
    ORDINAL_POSITION,
    COLUMN_NAME,
    DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'dbo'
  AND TABLE_NAME = 'inbound_automation'
  AND (
        COLUMN_NAME LIKE '%benefit%'
     OR COLUMN_NAME LIKE '%effective%'
     OR COLUMN_NAME LIKE '%start%'
     OR COLUMN_NAME LIKE '%end%'
     OR COLUMN_NAME LIKE '%status%'
     OR COLUMN_NAME LIKE '%enrollment%'
  )
ORDER BY ORDINAL_POSITION;
