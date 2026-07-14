WITH base AS (
    SELECT *
    FROM dbo.inbound_automation
    -- optional:
    -- WHERE folder_year = 2026
),
members AS (
    SELECT DISTINCT member_id
    FROM base
    WHERE member_id IS NOT NULL
),
subscriber_only AS (
    SELECT DISTINCT subscriber_id
    FROM base
    WHERE subscriber_id IS NOT NULL
      AND NOT EXISTS (
          SELECT 1
          FROM members m
          WHERE m.member_id = base.subscriber_id
      )
),
dep_rows AS (
    SELECT
        b.subscriber_id,
        b.issuer,
        b.member_id,
        b.policy_id,
        b.health_coverage_policy_no,
        b.member_first_name,
        b.member_last_name
    FROM base b
    INNER JOIN subscriber_only s
        ON s.subscriber_id = b.subscriber_id
    WHERE b.member_id IS NOT NULL
),
counts AS (
    SELECT
        subscriber_id,
        COUNT(DISTINCT member_id) AS dependent_enrollee_count,
        COUNT(*) AS dependent_raw_row_count,
        COUNT(DISTINCT policy_id) AS distinct_policy_id,
        COUNT(DISTINCT COALESCE(policy_id, health_coverage_policy_no)) AS distinct_policy_any
    FROM dep_rows
    GROUP BY subscriber_id
),
issuer_list AS (
    SELECT
        subscriber_id,
        STUFF((
            SELECT ', ' + x.issuer
            FROM (SELECT DISTINCT CAST(issuer AS NVARCHAR(20)) AS issuer
                  FROM dep_rows d2
                  WHERE d2.subscriber_id = d1.subscriber_id) x
            ORDER BY x.issuer
            FOR XML PATH(''), TYPE
        ).value('.', 'NVARCHAR(MAX)'), 1, 2, '') AS hios_issuer_ids
    FROM (SELECT DISTINCT subscriber_id FROM dep_rows) d1
),
member_list AS (
    SELECT
        subscriber_id,
        STUFF((
            SELECT ', ' + x.member_id
            FROM (SELECT DISTINCT CAST(member_id AS NVARCHAR(100)) AS member_id
                  FROM dep_rows d2
                  WHERE d2.subscriber_id = d1.subscriber_id) x
            ORDER BY x.member_id
            FOR XML PATH(''), TYPE
        ).value('.', 'NVARCHAR(MAX)'), 1, 2, '') AS dependent_member_ids
    FROM (SELECT DISTINCT subscriber_id FROM dep_rows) d1
),
name_list AS (
    SELECT
        subscriber_id,
        STUFF((
            SELECT '; ' + x.nm
            FROM (
                SELECT DISTINCT
                    LTRIM(RTRIM(ISNULL(member_first_name, '') + ' ' + ISNULL(member_last_name, ''))) AS nm
                FROM dep_rows d2
                WHERE d2.subscriber_id = d1.subscriber_id
            ) x
            WHERE x.nm <> ''
            ORDER BY x.nm
            FOR XML PATH(''), TYPE
        ).value('.', 'NVARCHAR(MAX)'), 1, 2, '') AS dependent_names
    FROM (SELECT DISTINCT subscriber_id FROM dep_rows) d1
)
SELECT
    c.subscriber_id,
    i.hios_issuer_ids,
    c.dependent_enrollee_count,
    c.dependent_raw_row_count,
    c.distinct_policy_id,
    c.distinct_policy_any,
    m.dependent_member_ids,
    n.dependent_names
FROM counts c
LEFT JOIN issuer_list i ON i.subscriber_id = c.subscriber_id
LEFT JOIN member_list m ON m.subscriber_id = c.subscriber_id
LEFT JOIN name_list n ON n.subscriber_id = c.subscriber_id
ORDER BY c.dependent_enrollee_count DESC, c.subscriber_id;
Simpler version (counts only — fastest)

WITH members AS (
    SELECT DISTINCT member_id
    FROM dbo.inbound_automation
    WHERE member_id IS NOT NULL
),
subscriber_only AS (
    SELECT DISTINCT subscriber_id
    FROM dbo.inbound_automation
    WHERE subscriber_id IS NOT NULL
      AND NOT EXISTS (
          SELECT 1
          FROM members m
          WHERE m.member_id = dbo.inbound_automation.subscriber_id
      )
)
SELECT
    b.subscriber_id,
    COUNT(DISTINCT b.member_id) AS dependent_enrollee_count,
    COUNT(*) AS dependent_raw_row_count,
    COUNT(DISTINCT b.issuer) AS issuer_count,
    COUNT(DISTINCT b.policy_id) AS distinct_policy_id
FROM dbo.inbound_automation b
INNER JOIN subscriber_only s
    ON s.subscriber_id = b.subscriber_id
WHERE b.member_id IS NOT NULL
GROUP BY b.subscriber_id
ORDER BY dependent_enrollee_count DESC, b.subscriber_id;
