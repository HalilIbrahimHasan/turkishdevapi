SELECT
    issuer AS [HIOS Issuer ID],
    insurance_type AS [Insurance Type],
    coverage_year AS [Coverage Year],

    COALESCE(
        NULLIF(policy_id, ''),
        NULLIF(health_coverage_policy_no, '')
    ) AS [Policy ID],

    COALESCE(
        NULLIF(member_id, ''),
        NULLIF(issuer_indiv_identifier, ''),
        NULLIF(exchg_assigned_enrollee_id, '')
    ) AS [Enrollee ID],

    policy_id AS [Original Policy ID],
    health_coverage_policy_no AS [Health Coverage Policy Number],
    member_id AS [Original Member ID],
    issuer_indiv_identifier AS [Issuer Individual Identifier],
    exchg_assigned_enrollee_id AS [Exchange Assigned Enrollee ID],

    policy_benefit_start_date AS [Policy Benefit Start Date],
    policy_benefit_end_date AS [Policy Benefit End Date],

    enrollee_benefit_start_date AS [Enrollee Benefit Start Date],
    enrollee_benefit_end_date AS [Enrollee Benefit End Date],

    enrollment_status AS [Enrollment Status],
    enrollee_status AS [Enrollee Status],
    enrollment_date AS [Enrollment Date],

    maintenance_type_code AS [Maintenance Type Code],
    member_maint_effective_date AS [Maintenance Effective Date],

    source_file_name AS [Source File],
    folder_year AS [Folder Year],
    loaded_at AS [Loaded Date]

FROM dbo.inbound_automation
WHERE issuer = '83502'
  AND coverage_year = 2026
  AND insurance_type = 'Health'
ORDER BY
    [Policy ID],
    [Enrollee ID],
    member_maint_effective_date,
    source_file_name;
