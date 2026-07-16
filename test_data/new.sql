SELECT
    issuer AS [HIOS Issuer ID],
    insurance_type AS [Insurance Type],
    coverage_year AS [Coverage Year],
    folder_year AS [Folder Year],

    COALESCE(
        NULLIF(policy_id, ''),
        NULLIF(health_coverage_policy_no, '')
    ) AS [Policy ID],

    COALESCE(
        NULLIF(member_id, ''),
        NULLIF(issuer_indiv_identifier, ''),
        NULLIF(exchg_assigned_enrollee_id, '')
    ) AS [Enrollee ID],

    policy_id,
    health_coverage_policy_no,
    member_id,
    issuer_indiv_identifier,
    exchg_assigned_enrollee_id

FROM dbo.inbound_automation
WHERE issuer = '83502'
ORDER BY
    coverage_year,
    policy_id,
    member_id;
