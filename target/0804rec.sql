
WITH ffm_pairs AS (
    SELECT DISTINCT enrollee_id, policy_id
    FROM (VALUES
        ('1000000001', '1000008526'),
        ('1000000002', '1000008526')
        -- Excel'deki tüm enrollee_id + enrollment_id çiftleri
    ) v(enrollee_id, policy_id)
),

raw_pairs AS (
    SELECT DISTINCT
        LTRIM(RTRIM(CAST(member_id AS VARCHAR(200)))) AS enrollee_id,

        COALESCE(
            NULLIF(LTRIM(RTRIM(CAST(policy_id AS VARCHAR(200)))), ''),
            NULLIF(LTRIM(RTRIM(CAST(health_coverage_policy_no AS VARCHAR(200)))), '')
        ) AS policy_id
    FROM dbo.inbound_automation
    WHERE issuer = '37301'
      AND folder_year IN (2025, 2026)
)

SELECT
    COUNT(*) AS Total_FFM_Policy_Enrollee_Pairs,

    SUM(CASE
        WHEN r.policy_id IS NOT NULL THEN 1
        ELSE 0
    END) AS Exact_Policy_Enrollee_Matches,

    SUM(CASE
        WHEN r.policy_id IS NULL THEN 1
        ELSE 0
    END) AS Policy_Found_But_Enrollee_Not_Found

FROM ffm_pairs f
LEFT JOIN raw_pairs r
    ON r.policy_id = f.policy_id
   AND r.enrollee_id = f.enrollee_id;

=======================
WITH ffm_policies AS (
    SELECT DISTINCT
        LTRIM(RTRIM(CAST(policy_id AS VARCHAR(200)))) AS policy_id
    FROM (VALUES
        ('142635'),
        ('320279'),
        ('4688103'),
        ('3830094')
        -- Kalan unique enrollment_id değerlerini buraya ekle
    ) v(policy_id)
),

raw_matches AS (
    SELECT DISTINCT
        COALESCE(
            NULLIF(
                LTRIM(RTRIM(CAST(policy_id AS VARCHAR(200)))),
                ''
            ),
            NULLIF(
                LTRIM(RTRIM(CAST(health_coverage_policy_no AS VARCHAR(200)))),
                ''
            )
        ) AS normalized_policy_id,

        issuer,
        coverage_year,
        folder_year,
        folder_month,
        source_file,
        enrolleeStatus

    FROM dbo.inbound_automation
    WHERE folder_year IN (2025, 2026)
      AND (
            NULLIF(
                LTRIM(RTRIM(CAST(policy_id AS VARCHAR(200)))),
                ''
            ) IS NOT NULL

            OR

            NULLIF(
                LTRIM(RTRIM(CAST(health_coverage_policy_no AS VARCHAR(200)))),
                ''
            ) IS NOT NULL
          )
)

SELECT
    f.policy_id AS FFM_Policy_ID,

    CASE
        WHEN r.normalized_policy_id IS NOT NULL
            THEN 'FOUND'
        ELSE 'NOT FOUND'
    END AS Inbound_Match_Status,

    r.issuer AS Found_Under_Issuer,
    r.coverage_year,
    r.folder_year,
    r.folder_month,
    r.enrolleeStatus,
    r.source_file

FROM ffm_policies f
LEFT JOIN raw_matches r
    ON r.normalized_policy_id = f.policy_id

ORDER BY
    Inbound_Match_Status DESC,
    f.policy_id,
    r.issuer,
    r.folder_year,
    r.folder_month;

========================
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
