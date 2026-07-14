/* Subscriber-only = subscriber_id that never appears as member_id
   Dependents = distinct member_id on rows that reference that subscriber */

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
      AND subscriber_id NOT IN (SELECT member_id FROM members)
)
SELECT
    b.subscriber_id,
    STRING_AGG(DISTINCT CAST(b.issuer AS NVARCHAR(20)), ', ')
        WITHIN GROUP (ORDER BY b.issuer) AS hios_issuer_ids,
    COUNT(DISTINCT b.member_id) AS dependent_enrollee_count,   -- people like Julie/Rian/Angela
    COUNT(*) AS dependent_raw_row_count,                       -- all transactions for those dependents
    COUNT(DISTINCT b.policy_id) AS distinct_policy_id,
    COUNT(DISTINCT COALESCE(b.policy_id, b.health_coverage_policy_no)) AS distinct_policy_any,
    STRING_AGG(DISTINCT b.member_id, ', ')
        WITHIN GROUP (ORDER BY b.member_id) AS dependent_member_ids,
    STRING_AGG(DISTINCT ISNULL(b.member_first_name, '') + ' ' + ISNULL(b.member_last_name, ''), '; ')
        AS dependent_names
FROM base b
INNER JOIN subscriber_only s
    ON s.subscriber_id = b.subscriber_id
WHERE b.member_id IS NOT NULL
GROUP BY b.subscriber_id
ORDER BY dependent_enrollee_count DESC, b.subscriber_id;



SELECT COUNT(*) AS subscriber_only_count
FROM (
    SELECT DISTINCT subscriber_id
    FROM dbo.inbound_automation
    WHERE subscriber_id IS NOT NULL
      AND subscriber_id NOT IN (
          SELECT member_id
          FROM dbo.inbound_automation
          WHERE member_id IS NOT NULL
      )
) x;
