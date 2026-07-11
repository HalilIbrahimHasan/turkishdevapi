DECLARE @folder_year INT = 2026;   -- change or set NULL for all years
DECLARE @issuer      NVARCHAR(20) = NULL;  -- e.g. N'68806' or NULL for all

1. Quick summary (raw rows + policy + member counts)
SELECT
    COUNT(*) AS total_raw_rows,                    -- 1 row per <enrollee> loaded
    COUNT(DISTINCT policy_id) AS distinct_policy_id,
    COUNT(DISTINCT health_coverage_policy_no) AS distinct_health_policy_no,
    COUNT(DISTINCT COALESCE(policy_id, health_coverage_policy_no))
        AS distinct_policy_any,                    -- use when policy_id is NULL (60224/68806)
    COUNT(DISTINCT member_id) AS distinct_member_id,
    COUNT(DISTINCT subscriber_id) AS distinct_subscriber_id
FROM dbo.inbound_automation
WHERE (@folder_year IS NULL OR folder_year = @folder_year)
  AND (@issuer IS NULL OR issuer = @issuer);



2. Enrollee rows + policy holders not counted as enrollees (Tom scenario)
This adds subscribers who appear as subscriber_id on other rows but never appear as member_id (subscriber not an <enrollee>).

DECLARE @folder_year INT = 2026;
DECLARE @issuer      NVARCHAR(20) = NULL;

WITH base AS (
    SELECT *
    FROM dbo.inbound_automation
    WHERE (@folder_year IS NULL OR folder_year = @folder_year)
      AND (@issuer IS NULL OR issuer = @issuer)
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
    (SELECT COUNT(*) FROM base) AS total_enrollee_rows,
    (SELECT COUNT(*) FROM subscriber_only) AS subscriber_only_policy_holders,
    (SELECT COUNT(*) FROM base)
        + (SELECT COUNT(*) FROM subscriber_only)
        AS enrollee_rows_plus_subscriber_only_holders
;


3. By issuer (same combined logic)

DECLARE @folder_year INT = 2026;

WITH base AS (
    SELECT issuer, member_id, subscriber_id
    FROM dbo.inbound_automation
    WHERE folder_year = @folder_year
),
members AS (
    SELECT issuer, member_id
    FROM base
    WHERE member_id IS NOT NULL
    GROUP BY issuer, member_id
),
subscriber_only AS (
    SELECT b.issuer, b.subscriber_id
    FROM base b
    WHERE b.subscriber_id IS NOT NULL
      AND NOT EXISTS (
          SELECT 1
          FROM members m
          WHERE m.issuer = b.issuer
            AND m.member_id = b.subscriber_id
      )
    GROUP BY b.issuer, b.subscriber_id
)
SELECT
    b.issuer,
    COUNT(*) AS total_enrollee_rows,
    COUNT(DISTINCT b.policy_id) AS distinct_policy_id,
    COUNT(DISTINCT b.member_id) AS distinct_member_id,
    COUNT(DISTINCT b.subscriber_id) AS distinct_subscriber_id,
    (SELECT COUNT(*) FROM subscriber_only s WHERE s.issuer = b.issuer)
        AS subscriber_only_policy_holders,
    COUNT(*)
        + (SELECT COUNT(*) FROM subscriber_only s WHERE s.issuer = b.issuer)
        AS enrollee_rows_plus_subscriber_only_holders
FROM base b
GROUP BY b.issuer
ORDER BY b.issuer;

DECLARE @folder_year INT = 2026;   -- change as needed, or NULL for all years

WITH base AS (
    SELECT member_id, subscriber_id
    FROM dbo.inbound_automation
    WHERE (@folder_year IS NULL OR folder_year = @folder_year)
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
    (SELECT COUNT(*) FROM dbo.inbound_automation
     WHERE (@folder_year IS NULL OR folder_year = @folder_year))
        AS total_enrollee_rows,

    (SELECT COUNT(*) FROM subscriber_only)
        AS subscriber_only_policy_holders,

    (SELECT COUNT(*) FROM dbo.inbound_automation
     WHERE (@folder_year IS NULL OR folder_year = @folder_year))
        + (SELECT COUNT(*) FROM subscriber_only)
        AS enrollee_rows_plus_subscriber_only_holders,

    (SELECT COUNT(DISTINCT member_id) FROM base WHERE member_id IS NOT NULL)
        AS distinct_member_id,

    (SELECT COUNT(*) FROM subscriber_only)
        + (SELECT COUNT(DISTINCT member_id) FROM base WHERE member_id IS NOT NULL)
        AS unique_people_estimate;
