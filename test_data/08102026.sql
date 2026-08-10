

/* ============================================================
   CLEANUP
   ============================================================ */

DROP TABLE IF EXISTS #target_enrollees;
DROP TABLE IF EXISTS #ffm_pairs;
DROP TABLE IF EXISTS #automation_all;
DROP TABLE IF EXISTS #pair_classification;


/* ============================================================
   1. TARGET ENROLLEES
   Put Swathi's complete enrollee list here
   ============================================================ */

SELECT DISTINCT
    LTRIM(RTRIM(CAST(enrollee_id AS VARCHAR(200)))) AS enrollee_id
INTO #target_enrollees
FROM (VALUES

    ('1000923947'),
    ('1001301643'),
    ('1001302403'),
    ('1001302341'),
    ('1001303876'),
    ('1001305545'),
    ('1001305548'),
    ('1002235873')

    -- Add ALL remaining enrollee IDs here

) v(enrollee_id);


/* ============================================================
   2. BUILD FFM / BUSINESS PAIRS
   Source:
     PY242526_Applicants_test
     Enrollments_TEST

   NO YEAR FILTER
   Issuer = 37301
   ============================================================ */

SELECT DISTINCT

    CAST(A.ssn AS VARCHAR(50)) AS ssn,

    LTRIM(RTRIM(CAST(A.applicant_guid AS VARCHAR(200))))
        AS applicant_guid,

    LTRIM(RTRIM(CAST(E.enrollee_id AS VARCHAR(200))))
        AS enrollee_id,

    LTRIM(RTRIM(CAST(E.enrollment_id AS VARCHAR(200))))
        AS policy_id,

    E.household_id,

    E.enrollee_first_name,
    E.enrollee_last_name,

    E.person_type,
    E.relationship_type,

    E.coverage_year,

    E.hios_issuer_id,

    E.enrollment_status_description,
    E.enrollee_status_description,

    E.enrollment_create_date,
    E.enrollment_last_update_date

INTO #ffm_pairs

FROM dbo.PY242526_Applicants_test A

INNER JOIN dbo.Enrollments_TEST E
    ON LTRIM(RTRIM(CAST(A.applicant_guid AS VARCHAR(200))))
     = LTRIM(RTRIM(CAST(E.enrollee_id AS VARCHAR(200))))

INNER JOIN #target_enrollees T
    ON LTRIM(RTRIM(CAST(E.enrollee_id AS VARCHAR(200))))
     = T.enrollee_id

WHERE E.hios_issuer_id = 37301;


/* ============================================================
   3. BUILD AUTOMATION POPULATION
   ALL ISSUERS
   ALL YEARS
   ============================================================ */

SELECT DISTINCT

    COALESCE(
        NULLIF(
            LTRIM(RTRIM(CAST(ia.member_id AS VARCHAR(200)))),
            ''
        ),
        NULLIF(
            LTRIM(RTRIM(CAST(ia.issuer_indiv_identifier AS VARCHAR(200)))),
            ''
        ),
        NULLIF(
            LTRIM(RTRIM(CAST(ia.exchg_assigned_enrollee_id AS VARCHAR(200)))),
            ''
        )
    ) AS enrollee_id,

    COALESCE(
        NULLIF(
            LTRIM(RTRIM(CAST(ia.policy_id AS VARCHAR(200)))),
            ''
        ),
        NULLIF(
            LTRIM(RTRIM(CAST(ia.health_coverage_policy_no AS VARCHAR(200)))),
            ''
        )
    ) AS policy_id,

    ia.issuer,
    ia.coverage_year,
    ia.folder_year,
    ia.folder_month,

    ia.enrolleeStatus,
    ia.member_maint_effective_date,
    ia.loaded_at,
    ia.source_file

INTO #automation_all

FROM dbo.inbound_automation ia;


/* ============================================================
   OPTIONAL CHECK
   Shows the REAL temp-table column names
   ============================================================ */

SELECT TOP 5 *
FROM #ffm_pairs;

SELECT TOP 5 *
FROM #automation_all;


/* ============================================================
   RESULT SET 1
   HOW MANY FFM ENROLLEES EXIST ANYWHERE IN AUTOMATION?
   ============================================================ */

SELECT

    COUNT(DISTINCT f.enrollee_id)
        AS Total_FFM_Enrollees,

    COUNT(
        DISTINCT CASE
            WHEN a.enrollee_id IS NOT NULL
            THEN f.enrollee_id
        END
    ) AS Enrollees_Found_Anywhere_In_Automation,

    COUNT(
        DISTINCT CASE
            WHEN a.enrollee_id IS NULL
            THEN f.enrollee_id
        END
    ) AS Enrollees_Not_Found_Anywhere

FROM #ffm_pairs f

LEFT JOIN #automation_all a
    ON a.enrollee_id = f.enrollee_id;


/* ============================================================
   RESULT SET 2
   HOW MANY FFM POLICIES EXIST ANYWHERE IN AUTOMATION?
   ============================================================ */

SELECT

    COUNT(DISTINCT f.policy_id)
        AS Total_FFM_Policies,

    COUNT(
        DISTINCT CASE
            WHEN a.policy_id IS NOT NULL
            THEN f.policy_id
        END
    ) AS Policies_Found_Anywhere_In_Automation,

    COUNT(
        DISTINCT CASE
            WHEN a.policy_id IS NULL
            THEN f.policy_id
        END
    ) AS Policies_Not_Found_Anywhere

FROM #ffm_pairs f

LEFT JOIN #automation_all a
    ON a.policy_id = f.policy_id;


/* ============================================================
   4. CLASSIFY EACH UNIQUE FFM ENROLLEE + POLICY PAIR
   ============================================================ */

SELECT DISTINCT

    f.enrollee_id,
    f.policy_id,

    CASE

        WHEN EXISTS (
            SELECT 1
            FROM #automation_all a
            WHERE a.enrollee_id = f.enrollee_id
              AND a.policy_id   = f.policy_id
        )
        THEN 'EXACT PAIR FOUND ANYWHERE'

        WHEN EXISTS (
            SELECT 1
            FROM #automation_all a
            WHERE a.enrollee_id = f.enrollee_id
        )
        AND EXISTS (
            SELECT 1
            FROM #automation_all a
            WHERE a.policy_id = f.policy_id
        )
        THEN 'ENROLLEE + POLICY BOTH EXIST, BUT NOT AS SAME PAIR'

        WHEN EXISTS (
            SELECT 1
            FROM #automation_all a
            WHERE a.enrollee_id = f.enrollee_id
        )
        THEN 'ENROLLEE FOUND, POLICY NOT FOUND'

        WHEN EXISTS (
            SELECT 1
            FROM #automation_all a
            WHERE a.policy_id = f.policy_id
        )
        THEN 'POLICY FOUND, ENROLLEE NOT FOUND'

        ELSE 'NEITHER FOUND'

    END AS Match_Category

INTO #pair_classification

FROM #ffm_pairs f;


/* ============================================================
   RESULT SET 3
   PAIR CLASSIFICATION SUMMARY
   ============================================================ */

SELECT

    Match_Category,

    COUNT(*) AS Distinct_Enrollee_Policy_Pairs,

    COUNT(DISTINCT enrollee_id)
        AS Distinct_Enrollees,

    COUNT(DISTINCT policy_id)
        AS Distinct_Policies

FROM #pair_classification

GROUP BY
    Match_Category

ORDER BY
    Match_Category;


/* ============================================================
   RESULT SET 4
   FOR NON-EXACT PAIRS:
   SHOW WHERE THE SAME ENROLLEE ACTUALLY EXISTS
   ============================================================ */

SELECT DISTINCT

    f.enrollee_id
        AS FFM_Enrollee_ID,

    f.policy_id
        AS Expected_37301_Policy,

    f.enrollee_first_name,
    f.enrollee_last_name,

    f.coverage_year
        AS FFM_Coverage_Year,

    f.enrollment_status_description
        AS FFM_Enrollment_Status,

    a.policy_id
        AS Actual_Automation_Policy,

    a.issuer
        AS Actual_Automation_Issuer,

    a.coverage_year
        AS Automation_Coverage_Year,

    a.folder_year,
    a.folder_month,

    a.enrolleeStatus
        AS Automation_Status,

    a.member_maint_effective_date,

    a.source_file

FROM #ffm_pairs f

INNER JOIN #automation_all a
    ON a.enrollee_id = f.enrollee_id

WHERE NOT EXISTS (

    SELECT 1
    FROM #automation_all x

    WHERE x.enrollee_id = f.enrollee_id
      AND x.policy_id   = f.policy_id
)

ORDER BY

    f.enrollee_id,
    a.folder_year,
    a.folder_month,
    a.issuer,
    a.policy_id;
