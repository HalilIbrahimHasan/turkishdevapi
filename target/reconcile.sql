

SELECT
    issuer,
    coverage_year,
    folder_year,
    folder_month,

    COALESCE(
        NULLIF(policy_id,''),
        NULLIF(health_coverage_policy_no,'')
    ) AS inbound_policy,

    COALESCE(
        NULLIF(member_id,''),
        NULLIF(issuer_indiv_identifier,''),
        NULLIF(exchg_assigned_enrollee_id,'')
    ) AS inbound_enrollee,

    enrolleeStatus,
    member_maint_effective_date,
    loaded_at,
    source_file

FROM dbo.inbound_automation
WHERE
    COALESCE(
        NULLIF(member_id,''),
        NULLIF(issuer_indiv_identifier,''),
        NULLIF(exchg_assigned_enrollee_id,'')
    ) = '1000162542'

ORDER BY
    member_maint_effective_date,
    loaded_at;
