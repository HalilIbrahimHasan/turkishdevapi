WITH ffm_policies AS (
    SELECT DISTINCT policy_id
    FROM (VALUES
        ('142635'),
        ('320279'),
        ('4688103'),
        ('3830094')
        -- Excel'deki unique Policy IDs
    ) v(policy_id)
),

raw_matches AS (
    SELECT DISTINCT
        LTRIM(RTRIM(CAST(
            COALESCE(
                NULLIF(policy_id, ''),
                NULLIF(health_coverage_policy_no, '')
            ) AS VARCHAR(200)
        ))) AS policy_id,

        issuer,
        coverage_year,
        folder_year,
        folder_month,
        source_file,
        enrolleeStatus

    FROM dbo.inbound_automation

    WHERE folder_year IN (2025,2026)
      AND issuer='37301'
)

SELECT ...
