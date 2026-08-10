/* ============================================================
   CLEANUP
   ============================================================ */

DROP TABLE IF EXISTS #comparison_results;


/* ============================================================
   1. TARGET FFM ENROLLEES
   Put Swathi's COMPLETE enrollee list here
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
   2. REBUILD FFM / BUSINESS PAIRS

   IMPORTANT:
   NO COVERAGE YEAR FILTER

   We only want:
       Enrollee ID
            +
       Policy ID
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

    -- NO COVERAGE YEAR FILTER
),


/* ============================================================
   3. ALL 37301 INBOUND AUTOMATION HISTORY

   IMPORTANT:
   NO FOLDER YEAR FILTER
   NO COVERAGE YEAR FILTER
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

    -- NO YEAR FILTER AT ALL
),


/* ============================================================
   4. EXACT PAIR COMPARISON

   MATCH LOGIC:
       enrollee_id
           +
       policy_id

   YEAR DOES NOT PARTICIPATE IN MATCHING
   ============================================================ */

comparison AS (

    SELECT

        /* ---------- FFM / BUSINESS ---------- */

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

        f.hios_issuer_id AS ffm_issuer,
        f.source AS ffm_source,

        f.enrollment_status_description
            AS ffm_enrollment_status,

        f.enrollee_status_description
            AS ffm_enrollee_status,

        f.benefit_effective_date,
        f.benefit_end_date,

        f.enrollment_create_date,
        f.enrollment_last_update_date,


        /* ---------- AUTOMATION ---------- */

        a.enrollee_id AS automation_enrollee_id,
        a.policy_id   AS automation_policy_id,

        a.issuer AS automation_issuer,

        a.coverage_year AS automation_coverage_year,

        a.folder_year,
        a.folder_month,

        a.automation_status,

        a.member_maint_effective_date,

        a.loaded_at,

        a.source_file,


        /* ---------- CLASSIFICATION ---------- */

        CASE
            WHEN a.enrollee_id IS NOT NULL
             AND a.policy_id IS NOT NULL

            THEN 'EXACT ENROLLEE + POLICY MATCH'

            ELSE 'NOT FOUND AS EXACT PAIR'

        END AS pair_match_status


    FROM ffm_business f

    LEFT JOIN automation a

        ON a.enrollee_id = f.enrollee_id
       AND a.policy_id   = f.policy_id

)


/* ============================================================
   5. SAVE RESULTS
   ============================================================ */

SELECT *
INTO #comparison_results
FROM comparison;


/* ============================================================
   RESULT SET 1
   FULL DETAIL

   This is where we see WHERE the pair was found:
   folder_year / coverage_year / source_file / status
   ============================================================ */

SELECT *

FROM #comparison_results

ORDER BY

    ffm_enrollee_id,
    ffm_policy_id,

    folder_year,
    folder_month,

    source_file;


/* ============================================================
   RESULT SET 2
   OVERALL EXACT-PAIR SUMMARY
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
   WHERE DID THE EXACT MATCHES ACTUALLY COME FROM?

   This is now based on AUTOMATION FOLDER YEAR,
   not FFM coverage year.
   ============================================================ */

SELECT

    folder_year AS Automation_Folder_Year,

    COUNT(
        DISTINCT CONCAT(
            ffm_enrollee_id,
            '|',
            ffm_policy_id
        )
    ) AS Exact_Matched_Pairs,

    COUNT(DISTINCT ffm_enrollee_id)
        AS Distinct_Enrollees,

    COUNT(DISTINCT ffm_policy_id)
        AS Distinct_Policies

FROM #comparison_results

WHERE pair_match_status =
      'EXACT ENROLLEE + POLICY MATCH'

GROUP BY
    folder_year

ORDER BY
    folder_year;


/* ============================================================
   RESULT SET 4
   COVERAGE YEAR VS PHYSICAL FOLDER YEAR

   VERY IMPORTANT FOR THE 2024 QUESTION
   ============================================================ */

SELECT

    ffm_coverage_year,

    automation_coverage_year,

    folder_year AS Automation_Folder_Year,

    COUNT(
        DISTINCT CONCAT(
            ffm_enrollee_id,
            '|',
            ffm_policy_id
        )
    ) AS Exact_Matched_Pairs

FROM #comparison_results

WHERE pair_match_status =
      'EXACT ENROLLEE + POLICY MATCH'

GROUP BY

    ffm_coverage_year,
    automation_coverage_year,
    folder_year

ORDER BY

    ffm_coverage_year,
    folder_year,
    automation_coverage_year;
