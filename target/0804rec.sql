WITH ffm_policies AS (
    SELECT DISTINCT policy_id
    FROM (VALUES
        ('142635'),
        ('320279'),
        ('4688103'),
        ('3830094')
        -- Excel'deki unique enrollment_id değerlerini buraya ekle
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
    WHERE issuer = '37301'
      AND folder_year IN (2025, 2026)
      AND COALESCE(
            NULLIF(policy_id, ''),
            NULLIF(health_coverage_policy_no, '')
          ) IS NOT NULL
)

SELECT
    f.policy_id,

    CASE
        WHEN r.policy_id IS NOT NULL THEN 'FOUND'
        ELSE 'NOT FOUND'
    END AS inbound_match_status,

    r.coverage_year,
    r.folder_year,
    r.folder_month,
    r.enrolleeStatus,
    r.source_file

FROM ffm_policies f
LEFT JOIN raw_matches r
    ON r.policy_id = f.policy_id

ORDER BY
    inbound_match_status DESC,
    f.policy_id,
    r.folder_year,
    r.folder_month;
