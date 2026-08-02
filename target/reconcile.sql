

SELECT
    issuer,
    coverage_year,
    folder_year,
    folder_month,

    policy_id,
    health_coverage_policy_no,

    member_id,

    enrolleeStatus,

    source_file,

    member_maint_effective_date

FROM dbo.inbound_automation

WHERE issuer = '37301'

AND (
        member_id = '1000162542'
     OR issuer_indiv_identifier = '1000162542'
     OR exchg_assigned_enrollee_id = '1000162542'
)

ORDER BY
member_maint_effective_date;
