

/* ============================================================
   CLEANUP
   ============================================================ */

DROP TABLE IF EXISTS #ffm_pairs;
DROP TABLE IF EXISTS #exact_matches;


/* ============================================================
   1. TARGET FFM ENROLLEES
   PUT SWATHI'S COMPLETE ENROLLEE LIST HERE
   ============================================================ */

WITH target_enrollees AS (

    SELECT DISTINCT
        LTRIM(RTRIM(CAST(enrollee_id AS VARCHAR(200)))) AS enrollee_id

    FROM (VALUES

        ('1000923947'),
        ('1001301643'),
        ('1001302403'),
        ('1001302341'),
        ('1001303876'),
        ('1001305545'),
        ('1001305548'),
        ('1002235873')

        -- ADD ALL FFM ENROLLEE IDs HERE

    ) v(enrollee_id)
),

/* ============================================================
   2. REBUILD ALL VALID 37301 FFM ENROLLEE + POLICY PAIRS
      NO YEAR FILTER
   ============================================================ */

ffm_business AS (

    SELECT DISTINCT

        CAST(A.ssn AS VARCHAR(50)) AS ssn,

        LTRIM(RTRIM(
            CAST(A.applicant_guid AS VARCHAR(200))
        )) AS applicant_guid,

        LTRIM(RTRIM(
            CAST(E.enrollee_id AS VARCHAR(200))
        )) AS enrollee_id,

        LTRIM(RTRIM(
            CAST(E.enrollment_id AS VARCHAR(200))
        )) AS policy_id,

        E.household_id,

        E.enrollee_first_name,
        E.enrollee_last_name,

        E.person_type,
        E.relationship_type,

        E.enrollment_status_description,
        E.enrollee_status_description,

        E.coverage_year,
        E.hios_issuer_id,
        E.source,

        E.benefit_effective_date,
        E.benefit_end_date,

        E.enrollment_create_date,
        E.enrollment_last_update_date

    FROM dbo.PY242526_Applicants_test A

    INNER JOIN dbo.Enrollments_TEST E
        ON LTRIM(RTRIM(CAST(A.applicant_guid AS VARCHAR(200))))
         = LTRIM(RTRIM(CAST(E.enrollee_id AS VARCHAR(200))))

    INNER JOIN target_enrollees t
        ON LTRIM(RTRIM(CAST(E.enrollee_id AS VARCHAR(200))))
         = t.enrollee_id

    WHERE E.hios_issuer_id = 37301
)

/* ============================================================
   SAVE UNIQUE BUSINESS PAIRS
   ============================================================ */

SELECT *
INTO #ffm_pairs
FROM ffm_business;


/* ============================================================
   3. FIND EXACT PAIR IN AUTOMATION

   KEY DIFFERENCE:
   DO NOT COALESCE IDs.

   ENROLLEE may match ANY of:
      member_id
      issuer_indiv_identifier
      exchg_assigned_enrollee_id

   POLICY may match ANY of:
      policy_id
      health_coverage_policy_no

   NO YEAR FILTER.
   ============================================================ */

SELECT DISTINCT

    f.ssn,
    f.applicant_guid,

    f.enrollee_id AS ffm_enrollee_id,
    f.policy_id   AS ffm_policy_id,

    f.household_id,

    f.enrollee_first_name,
    f.enrollee_last_name,

    f.person_type,
    f.relationship_type,

    f.coverage_year AS ffm_coverage_year,

    f.enrollment_status_description
        AS ffm_enrollment_status,

    f.enrollee_status_description
        AS ffm_enrollee_status,

    /* ------------------------------
       AUTOMATION RAW IDENTIFIERS
       ------------------------------ */

    LTRIM(RTRIM(CAST(ia.member_id AS VARCHAR(200))))
        AS automation_member_id,

    LTRIM(RTRIM(CAST(ia.issuer_indiv_identifier AS VARCHAR(200))))
        AS automation_issuer_indiv_identifier,

    LTRIM(RTRIM(CAST(ia.exchg_assigned_enrollee_id AS VARCHAR(200))))
        AS automation_exchange_enrollee_id,

    LTRIM(RTRIM(CAST(ia.policy_id AS VARCHAR(200))))
        AS automation_policy_id,

    LTRIM(RTRIM(CAST(ia.health_coverage_policy_no AS VARCHAR(200))))
        AS automation_health_policy_no,

    ia.issuer AS automation_issuer,

    ia.coverage_year AS automation_coverage_year,

    ia.folder_year,
    ia.folder_month,

    ia.enrolleeStatus AS automation_status,

    ia.member_maint_effective_date,

    ia.loaded_at,

    ia.source_file,


    /* ========================================================
       WHICH ENROLLEE COLUMN MATCHED?
       ======================================================== */

    CASE

        WHEN LTRIM(RTRIM(CAST(ia.member_id AS VARCHAR(200))))
                = f.enrollee_id
            THEN 'member_id'

        WHEN LTRIM(RTRIM(CAST(
                 ia.issuer_indiv_identifier AS VARCHAR(200)
             ))) = f.enrollee_id
            THEN 'issuer_indiv_identifier'

        WHEN LTRIM(RTRIM(CAST(
                 ia.exchg_assigned_enrollee_id AS VARCHAR(200)
             ))) = f.enrollee_id
            THEN 'exchg_assigned_enrollee_id'

    END AS matched_enrollee_column,


    /* ========================================================
       WHICH POLICY COLUMN MATCHED?
       ======================================================== */

    CASE

        WHEN LTRIM(RTRIM(CAST(ia.policy_id AS VARCHAR(200))))
                = f.policy_id
            THEN 'policy_id'

        WHEN LTRIM(RTRIM(CAST(
                 ia.health_coverage_policy_no AS VARCHAR(200)
             ))) = f.policy_id
            THEN 'health_coverage_policy_no'

    END AS matched_policy_column


INTO #exact_matches

FROM #ffm_pairs f

INNER JOIN dbo.inbound_automation ia

    ON
    (
        /* ENROLLEE CAN MATCH ANY IDENTIFIER */

        LTRIM(RTRIM(CAST(ia.member_id AS VARCHAR(200))))
            = f.enrollee_id

        OR

        LTRIM(RTRIM(CAST(
            ia.issuer_indiv_identifier AS VARCHAR(200)
        ))) = f.enrollee_id

        OR

        LTRIM(RTRIM(CAST(
            ia.exchg_assigned_enrollee_id AS VARCHAR(200)
        ))) = f.enrollee_id
    )

    AND

    (
        /* POLICY CAN MATCH EITHER POLICY FIELD */

        LTRIM(RTRIM(CAST(ia.policy_id AS VARCHAR(200))))
            = f.policy_id

        OR

        LTRIM(RTRIM(CAST(
            ia.health_coverage_policy_no AS VARCHAR(200)
        ))) = f.policy_id
    )

WHERE ia.issuer = '37301';


/* ============================================================
   RESULT SET 1
   EXACT MATCH DETAIL
   ============================================================ */

SELECT *
FROM #exact_matches

ORDER BY
    ffm_enrollee_id,
    ffm_policy_id,
    folder_year,
    folder_month,
    source_file;


/* ============================================================
   RESULT SET 2
   TRUE EXACT MATCH TOTALS
   ============================================================ */

SELECT

    COUNT(*) AS Matched_Transaction_Rows,

    COUNT(DISTINCT ffm_enrollee_id)
        AS Matched_Distinct_Enrollees,

    COUNT(DISTINCT ffm_policy_id)
        AS Matched_Distinct_Policies,

    COUNT(
        DISTINCT CONCAT(
            ffm_enrollee_id,
            '|',
            ffm_policy_id
        )
    ) AS Matched_Distinct_Enrollee_Policy_Pairs

FROM #exact_matches;


/* ============================================================
   RESULT SET 3
   WHICH AUTOMATION ID COLUMN PRODUCED THE MATCH?
   ============================================================ */

SELECT

    matched_enrollee_column,
    matched_policy_column,

    COUNT(
        DISTINCT CONCAT(
            ffm_enrollee_id,
            '|',
            ffm_policy_id
        )
    ) AS Distinct_Matched_Pairs,

    COUNT(DISTINCT ffm_enrollee_id)
        AS Distinct_Enrollees,

    COUNT(DISTINCT ffm_policy_id)
        AS Distinct_Policies

FROM #exact_matches

GROUP BY
    matched_enrollee_column,
    matched_policy_column

ORDER BY
    Distinct_Matched_Pairs DESC;


/* ============================================================
   RESULT SET 4
   WHERE DO THE MATCHES PHYSICALLY LIVE?
   ============================================================ */

SELECT

    folder_year,
    automation_coverage_year,

    COUNT(
        DISTINCT CONCAT(
            ffm_enrollee_id,
            '|',
            ffm_policy_id
        )
    ) AS Distinct_Matched_Pairs,

    COUNT(DISTINCT ffm_enrollee_id)
        AS Distinct_Enrollees

FROM #exact_matches

GROUP BY
    folder_year,
    automation_coverage_year

ORDER BY
    folder_year,
    automation_coverage_year;
