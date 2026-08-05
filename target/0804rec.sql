

WITH target_policies AS (
    SELECT DISTINCT
        LTRIM(RTRIM(CAST(policy_id AS VARCHAR(200)))) AS policy_id
    FROM (VALUES
        ('1000008526'),
        ('1000013043'),
        ('1000022427'),
        ('11566586')
        -- Kalan policy ID'lerini buraya ekle
    ) v(policy_id)
),

business_members AS (
    SELECT DISTINCT
        LTRIM(RTRIM(CAST(e.enrollment_id AS VARCHAR(200)))) AS policy_id,
        LTRIM(RTRIM(CAST(e.enrollee_id AS VARCHAR(200)))) AS enrollee_id,

        e.person_type,
        e.relationship_type,
        e.consumer_category,

        e.coverage_year,
        e.source,
        e.Insurance_Type,
        e.enrollment_status_description,
        e.enrollee_status_description

    FROM dbo.Enrollments_TEST e
    INNER JOIN target_policies t
        ON LTRIM(RTRIM(CAST(e.enrollment_id AS VARCHAR(200))))
         = t.policy_id
),

raw_members AS (
    SELECT DISTINCT
        COALESCE(
            NULLIF(
                LTRIM(RTRIM(CAST(ia.policy_id AS VARCHAR(200)))),
                ''
            ),
            NULLIF(
                LTRIM(RTRIM(
                    CAST(ia.health_coverage_policy_no AS VARCHAR(200))
                )),
                ''
            )
        ) AS policy_id,

        COALESCE(
            NULLIF(
                LTRIM(RTRIM(CAST(ia.member_id AS VARCHAR(200)))),
                ''
            ),
            NULLIF(
                LTRIM(RTRIM(
                    CAST(ia.issuer_indiv_identifier AS VARCHAR(200))
                )),
                ''
            ),
            NULLIF(
                LTRIM(RTRIM(
                    CAST(ia.exchg_assigned_enrollee_id AS VARCHAR(200))
                )),
                ''
            )
        ) AS enrollee_id

    FROM dbo.inbound_automation ia
    INNER JOIN target_policies t
        ON COALESCE(
            NULLIF(
                LTRIM(RTRIM(CAST(ia.policy_id AS VARCHAR(200)))),
                ''
            ),
            NULLIF(
                LTRIM(RTRIM(
                    CAST(ia.health_coverage_policy_no AS VARCHAR(200))
                )),
                ''
            )
        ) = t.policy_id

    WHERE ia.issuer = '37301'
      AND ia.folder_year IN (2025, 2026)
),

classified_pairs AS (
    SELECT
        b.policy_id,
        b.enrollee_id,

        b.person_type,
        b.relationship_type,
        b.consumer_category,

        CASE
            WHEN r.enrollee_id IS NOT NULL
                THEN 'MATCHED'
            ELSE 'BUSINESS ONLY'
        END AS match_status,

        CASE
            WHEN
                UPPER(COALESCE(b.person_type, ''))
                    LIKE '%SUBSCRIBER%'
                OR UPPER(COALESCE(b.relationship_type, ''))
                    LIKE '%SELF%'
                OR UPPER(COALESCE(b.relationship_type, ''))
                    LIKE '%SUBSCRIBER%'
            THEN 'SUBSCRIBER'

            WHEN
                UPPER(COALESCE(b.relationship_type, ''))
                    LIKE '%SPOUSE%'
            THEN 'SPOUSE'

            WHEN
                UPPER(COALESCE(b.relationship_type, ''))
                    LIKE '%CHILD%'
                OR UPPER(COALESCE(b.relationship_type, ''))
                    LIKE '%DEPENDENT%'
            THEN 'CHILD / DEPENDENT'

            ELSE 'OTHER / UNMAPPED'
        END AS member_role

    FROM business_members b
    LEFT JOIN raw_members r
        ON r.policy_id = b.policy_id
       AND r.enrollee_id = b.enrollee_id
)

SELECT
    match_status,
    member_role,

    COUNT(DISTINCT CONCAT(policy_id, '|', enrollee_id))
        AS policy_enrollee_pairs,

    COUNT(DISTINCT policy_id)
        AS distinct_policies,

    COUNT(DISTINCT enrollee_id)
        AS distinct_enrollees

FROM classified_pairs

GROUP BY
    match_status,
    member_role

ORDER BY
    CASE
        WHEN match_status = 'MATCHED' THEN 1
        ELSE 2
    END,
    member_role;

=============================
WITH target_policies AS (
    SELECT DISTINCT
        LTRIM(RTRIM(CAST(policy_id AS VARCHAR(200)))) AS policy_id
    FROM (VALUES
        ('1000008526'),
        ('1000022427'),
        ('11566586')
        -- diğer policy ID'leri buraya ekle
    ) v(policy_id)
),

business_members AS (
    SELECT DISTINCT
        LTRIM(RTRIM(CAST(e.enrollment_id AS VARCHAR(200)))) AS policy_id,
        LTRIM(RTRIM(CAST(e.enrollee_id AS VARCHAR(200)))) AS enrollee_id,
        e.person_type,
        e.relationship_type,
        e.consumer_category,
        e.coverage_year,
        e.source,
        e.enrollment_status_description,
        e.enrollee_status_description
    FROM dbo.Enrollments_TEST e
    INNER JOIN target_policies t
        ON LTRIM(RTRIM(CAST(e.enrollment_id AS VARCHAR(200)))) = t.policy_id
),

raw_members AS (
    SELECT DISTINCT
        COALESCE(
            NULLIF(LTRIM(RTRIM(CAST(ia.policy_id AS VARCHAR(200)))), ''),
            NULLIF(LTRIM(RTRIM(
                CAST(ia.health_coverage_policy_no AS VARCHAR(200))
            )), '')
        ) AS policy_id,

        COALESCE(
            NULLIF(LTRIM(RTRIM(CAST(ia.member_id AS VARCHAR(200)))), ''),
            NULLIF(LTRIM(RTRIM(
                CAST(ia.issuer_indiv_identifier AS VARCHAR(200))
            )), ''),
            NULLIF(LTRIM(RTRIM(
                CAST(ia.exchg_assigned_enrollee_id AS VARCHAR(200))
            )), '')
        ) AS enrollee_id,

        ia.enrolleeStatus,
        ia.folder_year,
        ia.folder_month,
        ia.source_file
    FROM dbo.inbound_automation ia
    INNER JOIN target_policies t
        ON COALESCE(
            NULLIF(LTRIM(RTRIM(CAST(ia.policy_id AS VARCHAR(200)))), ''),
            NULLIF(LTRIM(RTRIM(
                CAST(ia.health_coverage_policy_no AS VARCHAR(200))
            )), '')
        ) = t.policy_id
    WHERE ia.issuer = '37301'
      AND ia.folder_year IN (2025, 2026)
),

business_summary AS (
    SELECT
        b.policy_id,
        COUNT(DISTINCT b.enrollee_id) AS Business_Enrollees,

        COUNT(DISTINCT CASE
            WHEN UPPER(COALESCE(b.person_type, '')) LIKE '%SUBSCRIBER%'
              OR UPPER(COALESCE(b.relationship_type, '')) LIKE '%SELF%'
              OR UPPER(COALESCE(b.relationship_type, '')) LIKE '%SUBSCRIBER%'
            THEN b.enrollee_id
        END) AS Business_Subscribers,

        COUNT(DISTINCT CASE
            WHEN UPPER(COALESCE(b.relationship_type, '')) LIKE '%SPOUSE%'
            THEN b.enrollee_id
        END) AS Business_Spouses,

        COUNT(DISTINCT CASE
            WHEN UPPER(COALESCE(b.relationship_type, '')) LIKE '%CHILD%'
              OR UPPER(COALESCE(b.relationship_type, '')) LIKE '%DEPENDENT%'
            THEN b.enrollee_id
        END) AS Business_Children_Dependents
    FROM business_members b
    GROUP BY b.policy_id
),

raw_summary AS (
    SELECT
        r.policy_id,
        COUNT(DISTINCT r.enrollee_id) AS Raw_Enrollees,
        COUNT(DISTINCT r.source_file) AS Raw_Files
    FROM raw_members r
    GROUP BY r.policy_id
),

matched_summary AS (
    SELECT
        b.policy_id,

        COUNT(DISTINCT CASE
            WHEN r.enrollee_id IS NOT NULL THEN b.enrollee_id
        END) AS Matched_Enrollees,

        COUNT(DISTINCT CASE
            WHEN r.enrollee_id IS NULL THEN b.enrollee_id
        END) AS Business_Only_Enrollees,

        COUNT(DISTINCT CASE
            WHEN r.enrollee_id IS NULL
             AND (
                    UPPER(COALESCE(b.relationship_type, '')) LIKE '%SPOUSE%'
                 OR UPPER(COALESCE(b.relationship_type, '')) LIKE '%CHILD%'
                 OR UPPER(COALESCE(b.relationship_type, '')) LIKE '%DEPENDENT%'
                 )
            THEN b.enrollee_id
        END) AS Missing_Spouse_Child_Dependent
    FROM business_members b
    LEFT JOIN raw_members r
        ON r.policy_id = b.policy_id
       AND r.enrollee_id = b.enrollee_id
    GROUP BY b.policy_id
)

SELECT
    t.policy_id,
    COALESCE(bs.Business_Enrollees, 0) AS Business_Enrollees,
    COALESCE(rs.Raw_Enrollees, 0) AS Raw_Enrollees,
    COALESCE(ms.Matched_Enrollees, 0) AS Matched_Enrollees,
    COALESCE(ms.Business_Only_Enrollees, 0)
        AS Business_Only_Enrollees,

    COALESCE(bs.Business_Subscribers, 0) AS Business_Subscribers,
    COALESCE(bs.Business_Spouses, 0) AS Business_Spouses,
    COALESCE(bs.Business_Children_Dependents, 0)
        AS Business_Children_Dependents,

    COALESCE(ms.Missing_Spouse_Child_Dependent, 0)
        AS Missing_Spouse_Child_Dependent,

    COALESCE(rs.Raw_Files, 0) AS Matching_Raw_Files,

    CASE
        WHEN COALESCE(ms.Matched_Enrollees, 0) > 0
         AND COALESCE(ms.Business_Only_Enrollees, 0) > 0
         AND COALESCE(ms.Missing_Spouse_Child_Dependent, 0) > 0
        THEN 'SUBSCRIBER MATCHED; DEPENDENT(S) BUSINESS ONLY'

        WHEN COALESCE(ms.Business_Only_Enrollees, 0) = 0
         AND COALESCE(ms.Matched_Enrollees, 0) > 0
        THEN 'ALL BUSINESS ENROLLEES MATCHED'

        WHEN COALESCE(rs.Raw_Enrollees, 0) = 0
        THEN 'POLICY NOT FOUND IN RAW'

        ELSE 'REVIEW'
    END AS Policy_Classification

FROM target_policies t
LEFT JOIN business_summary bs
    ON bs.policy_id = t.policy_id
LEFT JOIN raw_summary rs
    ON rs.policy_id = t.policy_id
LEFT JOIN matched_summary ms
    ON ms.policy_id = t.policy_id
ORDER BY
    Policy_Classification,
    t.policy_id;

==============================
WITH target_policies AS (
    SELECT DISTINCT
        LTRIM(RTRIM(CAST(policy_id AS VARCHAR(200)))) AS policy_id
    FROM (VALUES
        ('1000008526'),
        ('1000013043'),
        ('1000022427')
        -- kalan policy ID'leri buraya ekle
    ) v(policy_id)
),

business_records AS (
    SELECT DISTINCT
        LTRIM(RTRIM(CAST(e.enrollment_id AS VARCHAR(200)))) AS policy_id,
        LTRIM(RTRIM(CAST(e.enrollee_id AS VARCHAR(200)))) AS enrollee_id,

        e.coverage_year,
        e.hios_issuer_id,
        e.source,
        e.Insurance_Type,
        e.enrollment_status_description,
        e.enrollee_status_description,
        e.benefit_effective_date,
        e.benefit_end_date,
        e.enrollment_create_date,
        e.enrollment_last_update_date,
        e.enrollee_create_date,
        e.enrollee_last_update_date

    FROM dbo.Enrollments_TEST e
    INNER JOIN target_policies t
        ON LTRIM(RTRIM(CAST(e.enrollment_id AS VARCHAR(200)))) = t.policy_id
),

raw_records AS (
    SELECT DISTINCT
        COALESCE(
            NULLIF(LTRIM(RTRIM(CAST(ia.policy_id AS VARCHAR(200)))), ''),
            NULLIF(LTRIM(RTRIM(CAST(ia.health_coverage_policy_no AS VARCHAR(200)))), '')
        ) AS policy_id,

        COALESCE(
            NULLIF(LTRIM(RTRIM(CAST(ia.member_id AS VARCHAR(200)))), ''),
            NULLIF(LTRIM(RTRIM(CAST(ia.issuer_indiv_identifier AS VARCHAR(200)))), ''),
            NULLIF(LTRIM(RTRIM(CAST(ia.exchg_assigned_enrollee_id AS VARCHAR(200)))), '')
        ) AS enrollee_id,

        ia.issuer,
        ia.coverage_year,
        ia.folder_year,
        ia.folder_month,
        ia.enrolleeStatus,
        ia.member_maint_effective_date,
        ia.loaded_at,
        ia.source_file,
        ia.file_hash,
        ia.row_number_in_file

    FROM dbo.inbound_automation ia
    INNER JOIN target_policies t
        ON COALESCE(
            NULLIF(LTRIM(RTRIM(CAST(ia.policy_id AS VARCHAR(200)))), ''),
            NULLIF(LTRIM(RTRIM(CAST(ia.health_coverage_policy_no AS VARCHAR(200)))), '')
        ) = t.policy_id
),

all_pairs AS (
    SELECT
        policy_id,
        enrollee_id
    FROM business_records

    UNION

    SELECT
        policy_id,
        enrollee_id
    FROM raw_records
)

SELECT
    p.policy_id,
    p.enrollee_id,

    CASE
        WHEN b.policy_id IS NOT NULL
         AND r.policy_id IS NOT NULL
            THEN 'MATCHED POLICY + ENROLLEE'

        WHEN b.policy_id IS NOT NULL
         AND r.policy_id IS NULL
            THEN 'BUSINESS ONLY'

        WHEN b.policy_id IS NULL
         AND r.policy_id IS NOT NULL
            THEN 'RAW ONLY'

        ELSE 'UNCLASSIFIED'
    END AS match_status,

    /* Business side */
    b.coverage_year AS business_coverage_year,
    b.hios_issuer_id AS business_issuer,
    b.source AS business_source,
    b.Insurance_Type AS business_insurance_type,
    b.enrollment_status_description AS business_enrollment_status,
    b.enrollee_status_description AS business_enrollee_status,
    b.benefit_effective_date,
    b.benefit_end_date,
    b.enrollment_create_date,
    b.enrollment_last_update_date,
    b.enrollee_create_date,
    b.enrollee_last_update_date,

    /* Raw inbound side */
    r.issuer AS raw_issuer,
    r.coverage_year AS raw_coverage_year,
    r.folder_year,
    r.folder_month,
    r.enrolleeStatus AS raw_status,
    r.member_maint_effective_date,
    r.loaded_at,
    r.source_file,
    r.file_hash,
    r.row_number_in_file

FROM all_pairs p

LEFT JOIN business_records b
    ON b.policy_id = p.policy_id
   AND b.enrollee_id = p.enrollee_id

LEFT JOIN raw_records r
    ON r.policy_id = p.policy_id
   AND r.enrollee_id = p.enrollee_id

ORDER BY
    p.policy_id,
    p.enrollee_id,
    match_status,
    r.folder_year,
    r.folder_month,
    r.source_file;

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
