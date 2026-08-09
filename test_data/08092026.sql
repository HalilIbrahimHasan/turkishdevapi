/* ============================================================
   CLEANUP TEMP TABLE
   ============================================================ */

DROP TABLE IF EXISTS #comparison_results;


/* ============================================================
   1. TARGET FFM ENROLLEES
   Put Swathi's complete enrollee list here
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

        -- Add ALL remaining FFM enrollee IDs here

    ) v(enrollee_id)
),


/* ============================================================
   2. REBUILD CORRECT FFM / ENROLLMENTS_TEST POPULATION

   Applicants:
       applicant_guid

            =

   Enrollments_TEST:
       enrollee_id
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

        ON LTRIM(RTRIM(
               CAST(A.applicant_guid AS VARCHAR(200))
           ))
         =
           LTRIM(RTRIM(
               CAST(E.enrollee_id AS VARCHAR(200))
           ))

    INNER JOIN target_enrollees t

        ON LTRIM(RTRIM(
               CAST(E.enrollee_id AS VARCHAR(200))
           ))
         =
           t.enrollee_id

    WHERE E.hios_issuer_id = 37301

      AND E.coverage_year IN (2025, 2026)

),


/* ============================================================
   3. NORMALIZE OUR INBOUND AUTOMATION POPULATION
   ============================================================ */

automation AS (

    SELECT DISTINCT

        COALESCE(

            NULLIF(
                LTRIM(RTRIM(
                    CAST(ia.member_id AS VARCHAR(200))
                )),
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

        ) AS enrollee_id,


        COALESCE(

            NULLIF(
                LTRIM(RTRIM(
                    CAST(ia.policy_id AS VARCHAR(200))
                )),
                ''
            ),

            NULLIF(
                LTRIM(RTRIM(
                    CAST(ia.health_coverage_policy_no AS VARCHAR(200))
                )),
                ''
            )

        ) AS policy_id,


        ia.issuer,

        ia.coverage_year,

        ia.folder_year,
        ia.folder_month,

        ia.enrolleeStatus AS automation_status,

        ia.member_maint_effective_date,

        ia.loaded_at,

        ia.source_file

    FROM dbo.inbound_automation ia

    WHERE ia.issuer = '37301'

      AND ia.folder_year IN (2025, 2026)

),


/* ============================================================
   4. EXACT ENROLLEE + POLICY COMPARISON
   ============================================================ */

comparison AS (

    SELECT

        /* -------------------------
           FFM / BUSINESS SIDE
           ------------------------- */

        f.ssn,

        f.applicant_guid,

        f.enrollee_id
            AS ffm_enrollee_id,

        f.policy_id
            AS ffm_policy_id,

        f.household_id,

        f.enrollee_first_name,
        f.enrollee_last_name,

        f.person_type,
        f.relationship_type,

        f.coverage_year
            AS ffm_coverage_year,

        f.hios_issuer_id
            AS ffm_issuer,

        f.source
            AS ffm_source,

        f.enrollment_status_description
            AS ffm_enrollment_status,

        f.enrollee_status_description
            AS ffm_enrollee_status,

        f.benefit_effective_date,

        f.benefit_end_date,

        f.enrollment_create_date,

        f.enrollment_last_update_date,


        /* -------------------------
           AUTOMATION SIDE
           ------------------------- */

        a.enrollee_id
            AS automation_enrollee_id,

        a.policy_id
            AS automation_policy_id,

        a.issuer
            AS automation_issuer,

        a.coverage_year
            AS automation_coverage_year,

        a.folder_year,

        a.folder_month,

        a.automation_status,

        a.member_maint_effective_date,

        a.loaded_at,

        a.source_file,


        /* -------------------------
           MATCH CLASSIFICATION
           ------------------------- */

        CASE

            WHEN
                a.enrollee_id IS NOT NULL
                AND a.policy_id IS NOT NULL

            THEN
                'EXACT ENROLLEE + POLICY MATCH'

            ELSE
                'NOT FOUND AS EXACT PAIR'

        END AS pair_match_status


    FROM ffm_business f


    LEFT JOIN automation a

        ON a.enrollee_id = f.enrollee_id

       AND a.policy_id = f.policy_id

)


/* ============================================================
   5. SAVE COMPARISON INTO TEMP TABLE

   This allows us to use the same comparison result
   for multiple SELECT statements.
   ============================================================ */

SELECT *
INTO #comparison_results
FROM comparison;


/* ============================================================
   RESULT SET 1
   FULL RECORD-LEVEL DETAIL
   ============================================================ */

SELECT *

FROM #comparison_results

ORDER BY

    ffm_enrollee_id,

    ffm_coverage_year,

    ffm_policy_id,

    folder_year,

    folder_month,

    source_file;


/* ============================================================
   RESULT SET 2
   OVERALL MATCH SUMMARY
   ============================================================ */

SELECT

    pair_match_status,

    COUNT(*) AS Total_Rows,

    COUNT(DISTINCT ffm_enrollee_id)
        AS Distinct_Enrollees,

    COUNT(DISTINCT ffm_policy_id)
        AS Distinct_Policies,

    COUNT(
        DISTINCT CONCAT(
            ffm_enrollee_id,
            '|',
            ffm_policy_id
        )
    ) AS Distinct_Enrollee_Policy_Pairs

FROM #comparison_results

GROUP BY
    pair_match_status

ORDER BY
    pair_match_status;


/* ============================================================
   RESULT SET 3
   2025 VS 2026 BREAKDOWN
   ============================================================ */

SELECT

    ffm_coverage_year,

    pair_match_status,

    COUNT(
        DISTINCT CONCAT(
            ffm_enrollee_id,
            '|',
            ffm_policy_id
        )
    ) AS Distinct_Pairs,

    COUNT(DISTINCT ffm_enrollee_id)
        AS Distinct_Enrollees,

    COUNT(DISTINCT ffm_policy_id)
        AS Distinct_Policies

FROM #comparison_results

GROUP BY

    ffm_coverage_year,

    pair_match_status

ORDER BY

    ffm_coverage_year,

    pair_match_status;

==================================

/* ============================================================
   4. Save comparison result temporarily
   ============================================================ */

DROP TABLE IF EXISTS #comparison_results;

SELECT *
INTO #comparison_results
FROM comparison;


/* ============================================================
   RESULT SET 1
   Detailed record-level comparison
   ============================================================ */

SELECT *
FROM #comparison_results
ORDER BY
    ffm_enrollee_id,
    ffm_coverage_year,
    ffm_policy_id,
    folder_year,
    folder_month,
    source_file;


/* ============================================================
   RESULT SET 2
   Overall Exact Match / Not Found Summary
   ============================================================ */

SELECT
    pair_match_status,

    COUNT(*) AS Rows,

    COUNT(DISTINCT ffm_enrollee_id)
        AS Distinct_Enrollees,

    COUNT(DISTINCT ffm_policy_id)
        AS Distinct_Policies,

    COUNT(
        DISTINCT CONCAT(
            ffm_enrollee_id,
            '|',
            ffm_policy_id
        )
    ) AS Distinct_Enrollee_Policy_Pairs

FROM #comparison_results

GROUP BY
    pair_match_status

ORDER BY
    pair_match_status;


/* ============================================================
   RESULT SET 3
   2025 vs 2026 Breakdown
   ============================================================ */

SELECT
    ffm_coverage_year,
    pair_match_status,

    COUNT(
        DISTINCT CONCAT(
            ffm_enrollee_id,
            '|',
            ffm_policy_id
        )
    ) AS Distinct_Pairs,

    COUNT(DISTINCT ffm_enrollee_id)
        AS Distinct_Enrollees,

    COUNT(DISTINCT ffm_policy_id)
        AS Distinct_Policies

FROM #comparison_results

GROUP BY
    ffm_coverage_year,
    pair_match_status

ORDER BY
    ffm_coverage_year,
    pair_match_status;

==============================

WITH target_enrollees AS (
    SELECT DISTINCT enrollee_id
    FROM (VALUES
        ('1000923947'),
        ('1001301643'),
        ('1001302403'),
        ('1001302341'),
        ('1001303876'),
        ('1001305545'),
        ('1001305548'),
        ('1002235873')
        -- Swathi'nin tüm FFM enrollee ID'lerini buraya ekle
    ) v(enrollee_id)
),

/* ============================================================
   1. Rebuild the FFM / Enrollments_TEST population correctly
   ============================================================ */
ffm_business AS (
    SELECT DISTINCT
        CAST(A.ssn AS VARCHAR(50)) AS ssn,
        LTRIM(RTRIM(CAST(A.applicant_guid AS VARCHAR(200)))) AS applicant_guid,

        LTRIM(RTRIM(CAST(E.enrollee_id AS VARCHAR(200)))) AS enrollee_id,
        LTRIM(RTRIM(CAST(E.enrollment_id AS VARCHAR(200)))) AS policy_id,

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
      AND E.coverage_year IN (2025, 2026)
),

/* ============================================================
   2. Normalize our inbound Automation population
   ============================================================ */
automation AS (
    SELECT DISTINCT

        COALESCE(
            NULLIF(LTRIM(RTRIM(CAST(ia.member_id AS VARCHAR(200)))), ''),
            NULLIF(LTRIM(RTRIM(CAST(ia.issuer_indiv_identifier AS VARCHAR(200)))), ''),
            NULLIF(LTRIM(RTRIM(CAST(ia.exchg_assigned_enrollee_id AS VARCHAR(200)))), '')
        ) AS enrollee_id,

        COALESCE(
            NULLIF(LTRIM(RTRIM(CAST(ia.policy_id AS VARCHAR(200)))), ''),
            NULLIF(LTRIM(RTRIM(CAST(ia.health_coverage_policy_no AS VARCHAR(200)))), '')
        ) AS policy_id,

        ia.issuer,
        ia.coverage_year,
        ia.folder_year,
        ia.folder_month,
        ia.enrolleeStatus AS automation_status,
        ia.member_maint_effective_date,
        ia.loaded_at,
        ia.source_file

    FROM dbo.inbound_automation ia

    WHERE ia.issuer = '37301'
      AND ia.folder_year IN (2025, 2026)
),

/* ============================================================
   3. Compare exact Enrollee + Policy pairs
   ============================================================ */
comparison AS (
    SELECT
        f.ssn,
        f.applicant_guid,
        f.enrollee_id AS ffm_enrollee_id,
        f.policy_id AS ffm_policy_id,

        f.household_id,
        f.enrollee_first_name,
        f.enrollee_last_name,
        f.person_type,
        f.relationship_type,

        f.coverage_year AS ffm_coverage_year,
        f.hios_issuer_id AS ffm_issuer,
        f.source AS ffm_source,

        f.enrollment_status_description AS ffm_enrollment_status,
        f.enrollee_status_description AS ffm_enrollee_status,

        f.benefit_effective_date,
        f.benefit_end_date,
        f.enrollment_create_date,
        f.enrollment_last_update_date,

        a.enrollee_id AS automation_enrollee_id,
        a.policy_id AS automation_policy_id,
        a.issuer AS automation_issuer,
        a.coverage_year AS automation_coverage_year,
        a.folder_year,
        a.folder_month,
        a.automation_status,
        a.member_maint_effective_date,
        a.loaded_at,
        a.source_file,

        CASE
            WHEN a.enrollee_id IS NOT NULL
             AND a.policy_id IS NOT NULL
                THEN 'EXACT ENROLLEE + POLICY MATCH'
            ELSE 'NOT FOUND AS EXACT PAIR'
        END AS pair_match_status

    FROM ffm_business f

    LEFT JOIN automation a
        ON a.enrollee_id = f.enrollee_id
       AND a.policy_id = f.policy_id
)

/* ============================================================
   4. Detailed output
   ============================================================ */
SELECT
    *
FROM comparison
ORDER BY
    ffm_enrollee_id,
    ffm_coverage_year,
    ffm_policy_id,
    folder_year,
    folder_month,
    source_file;
