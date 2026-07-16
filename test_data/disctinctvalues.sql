SELECT
    issuer AS [HIOS Issuer ID],
    insurance_type AS [Insurance Type],
    coverage_year AS [Coverage Year],

    COUNT(DISTINCT COALESCE(
        NULLIF(policy_id, ''),
        NULLIF(health_coverage_policy_no, '')
    )) AS [Our Enrollments Total],

    COUNT(DISTINCT COALESCE(
        NULLIF(member_id, ''),
        NULLIF(issuer_indiv_identifier, ''),
        NULLIF(exchg_assigned_enrollee_id, '')
    )) AS [Our Enrollees Total],

    COUNT_BIG(*) AS [Our Raw Rows]

FROM dbo.inbound_automation
WHERE folder_year IN (2025, 2026)
  AND coverage_year IN (2025, 2026)
  AND insurance_type IN ('Health', 'Dental')
GROUP BY
    issuer,
    insurance_type,
    coverage_year
ORDER BY
    issuer,
    insurance_type,
    coverage_year;
