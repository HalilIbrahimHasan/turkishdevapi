







WITH target_pairs AS (
    SELECT *
    FROM (VALUES
        ('211386306', '1000615233'),
        ('211358549', '1000378196'),
        ('211496204', '1000143675'),
        ('212221579', '1000615231'),
        ('211059524', '1001692606'),
        ('211354345', '1000992750')
    ) v(target_policy_id, target_enrollee_id)
),

/* Swathi pair'inin Enrollments_TEST içinde exact olarak bulunup bulunmadığı */
exact_pair_check AS (
    SELECT DISTINCT
        t.target_policy_id,
        t.target_enrollee_id,

        e.household_id,
        e.coverage_year,
        CAST(e.enrollment_id AS VARCHAR(200)) AS enrollment_id,
        CAST(e.enrollee_id AS VARCHAR(200)) AS enrollee_id,
        e.enrollee_first_name,
        e.enrollee_last_name,
        e.birth_date,
        e.hios_issuer_id,
        e.source,
        e.person_type,
        e.relationship_type,
        e.enrollment_status_description,
        e.enrollee_status_description

    FROM target_pairs t
    LEFT JOIN dbo.Enrollments_TEST e
        ON LTRIM(RTRIM(CAST(e.enrollment_id AS VARCHAR(200))))
             = t.target_policy_id
       AND LTRIM(RTRIM(CAST(e.enrollee_id AS VARCHAR(200))))
             = t.target_enrollee_id
),

/* Policy'nin Enrollments_TEST içindeki gerçek üyeleri */
actual_policy_members AS (
    SELECT DISTINCT
        t.target_policy_id,
        t.target_enrollee_id,

        e.household_id,
        e.coverage_year,

        LTRIM(RTRIM(CAST(e.enrollment_id AS VARCHAR(200))))
            AS actual_policy_id,

        LTRIM(RTRIM(CAST(e.enrollee_id AS VARCHAR(200))))
            AS actual_policy_enrollee_id,

        e.enrollee_first_name,
        e.enrollee_last_name,
        e.birth_date,
        e.person_type,
        e.relationship_type,
        e.hios_issuer_id,
        e.source,
        e.enrollment_status_description,
        e.enrollee_status_description

    FROM target_pairs t
    INNER JOIN dbo.Enrollments_TEST e
        ON LTRIM(RTRIM(CAST(e.enrollment_id AS VARCHAR(200))))
             = t.target_policy_id
),

/* Target enrollee'nin gerçekte hangi policy ve household altında olduğu */
actual_enrollee_history AS (
    SELECT DISTINCT
        t.target_policy_id,
        t.target_enrollee_id,

        e.household_id AS enrollee_actual_household_id,
        e.coverage_year AS enrollee_actual_coverage_year,

        LTRIM(RTRIM(CAST(e.enrollment_id AS VARCHAR(200))))
            AS enrollee_actual_policy_id,

        LTRIM(RTRIM(CAST(e.enrollee_id AS VARCHAR(200))))
            AS actual_enrollee_id,

        e.enrollee_first_name AS actual_enrollee_first_name,
        e.enrollee_last_name AS actual_enrollee_last_name,
        e.birth_date AS actual_enrollee_birth_date,
        e.hios_issuer_id AS enrollee_actual_issuer,
        e.source AS enrollee_actual_source,
        e.enrollment_status_description AS enrollee_actual_status

    FROM target_pairs t
    INNER JOIN dbo.Enrollments_TEST e
        ON LTRIM(RTRIM(CAST(e.enrollee_id AS VARCHAR(200))))
             = t.target_enrollee_id
),

/* Exact policy–enrollee pair raw inbound'da var mı? */
raw_exact_pair AS (
    SELECT DISTINCT
        t.target_policy_id,
        t.target_enrollee_id,

        ia.issuer AS raw_issuer,
        ia.coverage_year AS raw_coverage_year,
        ia.folder_year,
        ia.folder_month,
        ia.enrolleeStatus AS raw_status,
        ia.source_file

    FROM target_pairs t
    INNER JOIN dbo.inbound_automation ia
        ON COALESCE(
            NULLIF(LTRIM(RTRIM(CAST(ia.policy_id AS VARCHAR(200)))), ''),
            NULLIF(
                LTRIM(RTRIM(
                    CAST(ia.health_coverage_policy_no AS VARCHAR(200))
                )),
                ''
            )
        ) = t.target_policy_id

       AND COALESCE(
            NULLIF(LTRIM(RTRIM(CAST(ia.member_id AS VARCHAR(200)))), ''),
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
        ) = t.target_enrollee_id
)

/* ==========================================================
   RESULT SET 1 — Summary and classification for every pair
   ========================================================== */
SELECT
    t.target_policy_id,
    t.target_enrollee_id,

    CASE
        WHEN EXISTS (
            SELECT 1
            FROM exact_pair_check x
            WHERE x.target_policy_id = t.target_policy_id
              AND x.target_enrollee_id = t.target_enrollee_id
              AND x.enrollment_id IS NOT NULL
        )
        THEN 'YES'
        ELSE 'NO'
    END AS Exact_Pair_In_Enrollments_TEST,

    CASE
        WHEN EXISTS (
            SELECT 1
            FROM raw_exact_pair r
            WHERE r.target_policy_id = t.target_policy_id
              AND r.target_enrollee_id = t.target_enrollee_id
        )
        THEN 'YES'
        ELSE 'NO'
    END AS Exact_Pair_In_Raw_Inbound,

    (
        SELECT COUNT(DISTINCT p.actual_policy_enrollee_id)
        FROM actual_policy_members p
        WHERE p.target_policy_id = t.target_policy_id
    ) AS Actual_Members_Under_Policy,

    (
        SELECT COUNT(DISTINCT h.enrollee_actual_policy_id)
        FROM actual_enrollee_history h
        WHERE h.target_enrollee_id = t.target_enrollee_id
    ) AS Other_Policies_For_Target_Enrollee,

    CASE
        WHEN EXISTS (
            SELECT 1
            FROM exact_pair_check x
            WHERE x.target_policy_id = t.target_policy_id
              AND x.target_enrollee_id = t.target_enrollee_id
              AND x.enrollment_id IS NOT NULL
        )
        THEN 'PAIR IS VALID IN ENROLLMENTS_TEST'

        WHEN EXISTS (
            SELECT 1
            FROM actual_policy_members p
            WHERE p.target_policy_id = t.target_policy_id
        )
         AND EXISTS (
            SELECT 1
            FROM actual_enrollee_history h
            WHERE h.target_enrollee_id = t.target_enrollee_id
        )
        THEN 'POLICY AND ENROLLEE BOTH EXIST, BUT NOT AS THE SAME PAIR'

        WHEN EXISTS (
            SELECT 1
            FROM actual_policy_members p
            WHERE p.target_policy_id = t.target_policy_id
        )
        THEN 'POLICY EXISTS; TARGET ENROLLEE NOT FOUND'

        WHEN EXISTS (
            SELECT 1
            FROM actual_enrollee_history h
            WHERE h.target_enrollee_id = t.target_enrollee_id
        )
        THEN 'ENROLLEE EXISTS; TARGET POLICY NOT FOUND'

        ELSE 'NEITHER FOUND'
    END AS Pair_Classification

FROM target_pairs t
ORDER BY t.target_policy_id;


/* ==========================================================
   RESULT SET 2 — Actual members currently tied to each policy
   ========================================================== */
SELECT
    target_policy_id,
    target_enrollee_id AS Expected_Enrollee_From_List,

    actual_policy_id,
    actual_policy_enrollee_id,
    enrollee_first_name,
    enrollee_last_name,
    birth_date,
    household_id,
    coverage_year,
    person_type,
    relationship_type,
    hios_issuer_id,
    source,
    enrollment_status_description,
    enrollee_status_description

FROM actual_policy_members
ORDER BY
    target_policy_id,
    actual_policy_enrollee_id;


/* ==========================================================
   RESULT SET 3 — Where the expected enrollee actually belongs
   ========================================================== */
SELECT
    target_policy_id AS Expected_Policy_From_List,
    target_enrollee_id,

    actual_enrollee_first_name,
    actual_enrollee_last_name,
    actual_enrollee_birth_date,

    enrollee_actual_household_id,
    enrollee_actual_coverage_year,
    enrollee_actual_policy_id,
    enrollee_actual_issuer,
    enrollee_actual_source,
    enrollee_actual_status

FROM actual_enrollee_history
ORDER BY
    target_enrollee_id,
    enrollee_actual_coverage_year,
    enrollee_actual_policy_id;


/* ==========================================================
   RESULT SET 4 — Exact raw inbound pair evidence, if any
   ========================================================== */
SELECT
    target_policy_id,
    target_enrollee_id,
    raw_issuer,
    raw_coverage_year,
    folder_year,
    folder_month,
    raw_status,
    source_file

FROM raw_exact_pair
ORDER BY
    target_policy_id,
    target_enrollee_id,
    folder_year,
    folder_month;


===========================
SELECT

coverage_year,
household_id,

enrollee_id,

enrollee_first_name,
enrollee_last_name,

enrollment_id,

hios_issuer_id,

enrollment_status_description,

benefit_effective_date,
benefit_end_date,

enrollment_create_date

FROM dbo.Enrollments_TEST

WHERE enrollee_id IN
(
1000615233,
1001041714
)

ORDER BY

coverage_year,
enrollment_create_date;

====================
SELECT
coverage_year,
household_id,
enrollee_id,
enrollee_first_name,
enrollee_last_name,
birth_date,
enrollment_id,
hios_issuer_id,
enrollment_status_description
FROM dbo.Enrollments_TEST
WHERE enrollment_id=211386306
ORDER BY enrollee_id;

==============
SELECT
    coverage_year,
    household_id,
    enrollee_id,
    enrollment_id,
    hios_issuer_id,
    Insurance_Type,
    source,

    enrollee_first_name,
    enrollee_last_name,
    first_name,
    last_name,
    birth_date,

    enrollment_status_description,
    enrollee_status_description,

    benefit_effective_date,
    benefit_end_date,

    enrollment_create_date,
    enrollment_last_update_date

FROM dbo.Enrollments_TEST

WHERE
    UPPER(LTRIM(RTRIM(enrollee_first_name))) = 'KRISTLE'
AND UPPER(LTRIM(RTRIM(enrollee_last_name))) = 'CHESTER'

ORDER BY
    coverage_year,
    enrollment_create_date,
    enrollment_id;

==================
SELECT
    coverage_year,
    household_id,
    enrollee_id,
    enrollment_id,
    hios_issuer_id,
    Insurance_Type,
    source,

    first_name,
    last_name,
    birth_date,

    enrollment_status_description,
    enrollee_status_description,

    benefit_effective_date,
    benefit_end_date,

    enrollment_create_date,
    enrollment_last_update_date

FROM dbo.Enrollments_TEST

WHERE
    first_name = 'Kristle'
AND last_name = 'Chester'

ORDER BY
    coverage_year,
    enrollment_create_date,
    enrollment_id;

=============================
SELECT
    'RAW_INBOUND_CHECK' AS Query_Check,

    ia.issuer,
    ia.coverage_year,
    ia.folder_year,
    ia.folder_month,

    LTRIM(RTRIM(CAST(ia.policy_id AS VARCHAR(200))))
        AS inbound_policy_id,

    LTRIM(RTRIM(CAST(ia.member_id AS VARCHAR(200))))
        AS inbound_enrollee_id,

    ia.enrolleeStatus AS raw_status,
    ia.member_maint_effective_date,
    ia.source_file

FROM dbo.inbound_automation ia

WHERE ia.issuer = '37301'
  AND LTRIM(RTRIM(CAST(ia.policy_id AS VARCHAR(200)))) IN (
        '210435217',
        '211129273'
      )

ORDER BY
    inbound_policy_id,
    inbound_enrollee_id,
    ia.member_maint_effective_date;

======================
SELECT
    ia.issuer,
    ia.coverage_year,
    ia.folder_year,
    ia.folder_month,

    COALESCE(
        NULLIF(LTRIM(RTRIM(CAST(ia.policy_id AS VARCHAR(200)))), ''),
        NULLIF(LTRIM(RTRIM(CAST(ia.health_coverage_policy_no AS VARCHAR(200)))), '')
    ) AS inbound_policy_id,

    COALESCE(
        NULLIF(LTRIM(RTRIM(CAST(ia.member_id AS VARCHAR(200)))), ''),
        NULLIF(LTRIM(RTRIM(CAST(ia.issuer_indiv_identifier AS VARCHAR(200)))), ''),
        NULLIF(LTRIM(RTRIM(CAST(ia.exchg_assigned_enrollee_id AS VARCHAR(200)))), '')
    ) AS inbound_enrollee_id,

    ia.enrolleeStatus,
    ia.member_maint_effective_date,
    ia.loaded_at,
    ia.source_file

FROM dbo.inbound_automation ia

WHERE ia.issuer = '37301'
  AND (
        LTRIM(RTRIM(CAST(ia.policy_id AS VARCHAR(200)))) IN (
            '210435217',
            '211129273'
        )
        OR
        LTRIM(RTRIM(CAST(ia.health_coverage_policy_no AS VARCHAR(200)))) IN (
            '210435217',
            '211129273'
        )
      )

ORDER BY
    inbound_policy_id,
    inbound_enrollee_id,
    ia.member_maint_effective_date,
    ia.source_file;

===================
SELECT
    ia.issuer,
    ia.coverage_year,
    ia.folder_year,
    ia.folder_month,

    COALESCE(
        NULLIF(LTRIM(RTRIM(CAST(ia.policy_id AS VARCHAR(200)))), ''),
        NULLIF(LTRIM(RTRIM(CAST(ia.health_coverage_policy_no AS VARCHAR(200)))), '')
    ) AS inbound_policy_id,

    COALESCE(
        NULLIF(LTRIM(RTRIM(CAST(ia.member_id AS VARCHAR(200)))), ''),
        NULLIF(LTRIM(RTRIM(CAST(ia.issuer_indiv_identifier AS VARCHAR(200)))), ''),
        NULLIF(LTRIM(RTRIM(CAST(ia.exchg_assigned_enrollee_id AS VARCHAR(200)))), '')
    ) AS inbound_enrollee_id,

    ia.enrolleeStatus,
    ia.member_maint_effective_date,
    ia.loaded_at,
    ia.source_file,
    ia.file_hash,
    ia.row_number_in_file

FROM dbo.inbound_automation ia

WHERE ia.issuer = '37301'

  AND COALESCE(
        NULLIF(LTRIM(RTRIM(CAST(ia.policy_id AS VARCHAR(200)))), ''),
        NULLIF(LTRIM(RTRIM(CAST(ia.health_coverage_policy_no AS VARCHAR(200)))), '')
      ) IN (
        '210435217',
        '211129273'
      )

  AND COALESCE(
        NULLIF(LTRIM(RTRIM(CAST(ia.member_id AS VARCHAR(200)))), ''),
        NULLIF(LTRIM(RTRIM(CAST(ia.issuer_indiv_identifier AS VARCHAR(200)))), ''),
        NULLIF(LTRIM(RTRIM(CAST(ia.exchg_assigned_enrollee_id AS VARCHAR(200)))), '')
      ) IN (
        '1002234726',
        '1002234727'
      )

ORDER BY
    inbound_policy_id,
    inbound_enrollee_id,
    ia.member_maint_effective_date,
    ia.loaded_at,
    ia.source_file;

======================
SELECT
    household_id,
    coverage_year,
    enrollment_id,
    enrollee_id,
    hios_issuer_id,
    source,

    enrollment_status_description,
    enrollee_status_description,

    benefit_effective_date,
    benefit_end_date,

    enrollment_create_date,
    enrollment_confirmation_date,
    enrollment_last_update_date,

    application_create_date,
    application_last_update_date

FROM dbo.Enrollments_TEST

WHERE household_id = 1217178

ORDER BY

    enrollment_create_date,
    coverage_year,
    enrollment_id,
    enrollee_id;

============================
WITH target_policies AS (
    SELECT DISTINCT
        policy_id
    FROM (VALUES
        ('1000008526')
        -- Policy ID listesi
    ) v(policy_id)
),

business_members AS (

SELECT DISTINCT
    CAST(e.enrollment_id AS varchar(50)) AS policy_id,
    CAST(e.enrollee_id AS varchar(50)) AS enrollee_id,
    e.person_type,
    e.relationship_type,
    e.source,
    e.coverage_year,
    e.household_id,
    e.enrollment_status_description,
    e.enrollee_status_description,
    e.benefit_effective_date,
    e.benefit_end_date,
    e.enrollment_create_date

FROM dbo.Enrollments_TEST e
INNER JOIN target_policies t
ON CAST(e.enrollment_id AS varchar(50))=t.policy_id
),

raw_members AS (

SELECT DISTINCT

COALESCE(
CAST(policy_id AS varchar(50)),
CAST(health_coverage_policy_no AS varchar(50))
) policy_id,

CAST(member_id AS varchar(50)) enrollee_id

FROM dbo.inbound_automation
WHERE issuer='37301'
)

SELECT *

FROM business_members b

LEFT JOIN raw_members r

ON b.policy_id=r.policy_id
AND b.enrollee_id=r.enrollee_id

WHERE r.enrollee_id IS NULL

AND
(
UPPER(person_type) LIKE '%SUBSCRIBER%'
OR UPPER(relationship_type) LIKE '%SELF%'
OR UPPER(relationship_type) LIKE '%SUBSCRIBER%'
)

ORDER BY
policy_id;

========================

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
