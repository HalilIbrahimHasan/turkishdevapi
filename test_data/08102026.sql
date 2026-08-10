
/* ============================================================
   CLEANUP
   ============================================================ */

DROP TABLE IF EXISTS #target_enrollees;
DROP TABLE IF EXISTS #ffm_pairs;
DROP TABLE IF EXISTS #automation_all;


/* ============================================================
   1. TARGET FFM ENROLLEES
   Swathi'nin full enrollee listesini buraya koy
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

    -- Add all FFM enrollee IDs here

) v(enrollee_id);


/* ============================================================
   2. REBUILD CORRECT FFM PAIRS
   NO YEAR FILTER
   Issuer 37301 business population
   ============================================================ */

SELECT DISTINCT

    CAST(A.ssn AS VARCHAR(50)) AS ssn,

    LTRIM(RTRIM(CAST(A.applicant_guid AS VARCHAR(200))))
        AS applicant_guid,

    LTRIM(RTRIM(CAST(E.enrollee_id AS VARCHAR(200))))
        AS ffm_enrollee_id,

    LTRIM(RTRIM(CAST(E.enrollment_id AS VARCHAR(200))))
        AS ffm_policy_id,

    E.household_id,

    E.enrollee_first_name,
    E.enrollee_last_name,

    E.person_type,
    E.relationship_type,

    E.coverage_year AS ffm_coverage_year,
    E.hios_issuer_id AS ffm_issuer,

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
   3. NORMALIZE ALL AUTOMATION RECORDS
   IMPORTANT:
   ALL ISSUERS
   ALL YEARS
   ============================================================ */

SELECT DISTINCT

    COALESCE(
        NULLIF(LTRIM(RTRIM(CAST(ia.member_id AS VARCHAR(200)))), ''),
        NULLIF(LTRIM(RTRIM(CAST(ia.issuer_indiv_identifier AS VARCHAR(200)))), ''),
        NULLIF(LTRIM(RTRIM(CAST(ia.exchg_assigned_enrollee_id AS VARCHAR(200)))), '')
    ) AS automation_enrollee_id,

    COALESCE(
        NULLIF(LTRIM(RTRIM(CAST(ia.policy_id AS VARCHAR(200)))), ''),
        NULLIF(LTRIM(RTRIM(CAST(ia.health_coverage_policy_no AS VARCHAR(200)))), '')
    ) AS automation_policy_id,

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
   RESULT SET 1
   HOW MANY FFM ENROLLEES EXIST ANYWHERE IN AUTOMATION?
   ============================================================ */

SELECT

    COUNT(DISTINCT f.ffm_enrollee_id)
        AS Total_FFM_Enrollees,

    COUNT(
        DISTINCT CASE
            WHEN a.automation_enrollee_id IS NOT NULL
            THEN f.ffm_enrollee_id
        END
    ) AS Enrollees_Found_Anywhere_In_Automation,

    COUNT(
        DISTINCT CASE
            WHEN a.automation_enrollee_id IS NULL
            THEN f.ffm_enrollee_id
        END
    ) AS Enrollees_Not_Found_Anywhere

FROM #ffm_pairs f

LEFT JOIN #automation_all a
    ON a.automation_enrollee_id = f.ffm_enrollee_id;


/* ============================================================
   RESULT SET 2
   HOW MANY FFM POLICIES EXIST ANYWHERE IN AUTOMATION?
   ============================================================ */

SELECT

    COUNT(DISTINCT f.ffm_policy_id)
        AS Total_FFM_Policies,

    COUNT(
        DISTINCT CASE
            WHEN a.automation_policy_id IS NOT NULL
            THEN f.ffm_policy_id
        END
    ) AS Policies_Found_Anywhere_In_Automation,

    COUNT(
        DISTINCT CASE
            WHEN a.automation_policy_id IS NULL
            THEN f.ffm_policy_id
        END
    ) AS Policies_Not_Found_Anywhere

FROM #ffm_pairs f

LEFT JOIN #automation_all a
    ON a.automation_policy_id = f.ffm_policy_id;


/* ============================================================
   RESULT SET 3
   PAIR CLASSIFICATION

   - exact pair exists anywhere
   - enrollee exists, policy exists, but not together
   - enrollee only
   - policy only
   - neither
   ============================================================ */

SELECT

    CASE

        WHEN EXISTS (
            SELECT 1
            FROM #automation_all a
            WHERE a.automation_enrollee_id = f.ffm_enrollee_id
              AND a.automation_policy_id   = f.ffm_policy_id
        )
        THEN 'EXACT PAIR FOUND ANYWHERE'

        WHEN EXISTS (
            SELECT 1
            FROM #automation_all a
            WHERE a.automation_enrollee_id = f.ffm_enrollee_id
        )
        AND EXISTS (
            SELECT 1
            FROM #automation_all a
            WHERE a.automation_policy_id = f.ffm_policy_id
        )
        THEN 'ENROLLEE + POLICY BOTH EXIST, BUT NOT AS SAME PAIR'

        WHEN EXISTS (
            SELECT 1
            FROM #automation_all a
            WHERE a.automation_enrollee_id = f.ffm_enrollee_id
        )
        THEN 'ENROLLEE FOUND, POLICY NOT FOUND'

        WHEN EXISTS (
            SELECT 1
            FROM #automation_all a
            WHERE a.automation_policy_id = f.ffm_policy_id
        )
        THEN 'POLICY FOUND, ENROLLEE NOT FOUND'

        ELSE 'NEITHER FOUND'

    END AS Match_Category,

    COUNT(
        DISTINCT CONCAT(
            f.ffm_enrollee_id,
            '|',
            f.ffm_policy_id
        )
    ) AS Distinct_Enrollee_Policy_Pairs,

    COUNT(DISTINCT f.ffm_enrollee_id)
        AS Distinct_Enrollees,

    COUNT(DISTINCT f.ffm_policy_id)
        AS Distinct_Policies

FROM #ffm_pairs f

GROUP BY

    CASE

        WHEN EXISTS (
            SELECT 1
            FROM #automation_all a
            WHERE a.automation_enrollee_id = f.ffm_enrollee_id
              AND a.automation_policy_id   = f.ffm_policy_id
        )
        THEN 'EXACT PAIR FOUND ANYWHERE'

        WHEN EXISTS (
            SELECT 1
            FROM #automation_all a
            WHERE a.automation_enrollee_id = f.ffm_enrollee_id
        )
        AND EXISTS (
            SELECT 1
            FROM #automation_all a
            WHERE a.automation_policy_id = f.ffm_policy_id
        )
        THEN 'ENROLLEE + POLICY BOTH EXIST, BUT NOT AS SAME PAIR'

        WHEN EXISTS (
            SELECT 1
            FROM #automation_all a
            WHERE a.automation_enrollee_id = f.ffm_enrollee_id
        )
        THEN 'ENROLLEE FOUND, POLICY NOT FOUND'

        WHEN EXISTS (
            SELECT 1
            FROM #automation_all a
            WHERE a.automation_policy_id = f.ffm_policy_id
        )
        THEN 'POLICY FOUND, ENROLLEE NOT FOUND'

        ELSE 'NEITHER FOUND'

    END

ORDER BY
    Match_Category;


/* ============================================================
   RESULT SET 4
   FOR NON-EXACT FFM PAIRS:
   WHERE DOES THE SAME ENROLLEE ACTUALLY APPEAR?

   This shows other issuer / policy / status lifecycle
   ============================================================ */

SELECT DISTINCT

    f.ffm_enrollee_id,

    f.ffm_policy_id
        AS Expected_37301_Policy,

    f.enrollee_first_name,
    f.enrollee_last_name,

    f.ffm_coverage_year,

    f.enrollment_status_description
        AS FFM_Status,

    a.automation_policy_id
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
    ON a.automation_enrollee_id = f.ffm_enrollee_id

WHERE NOT EXISTS (

    SELECT 1
    FROM #automation_all x

    WHERE x.automation_enrollee_id = f.ffm_enrollee_id
      AND x.automation_policy_id   = f.ffm_policy_id

)

ORDER BY

    f.ffm_enrollee_id,

    a.folder_year,

    a.folder_month,

    a.issuer,

    a.automation_policy_id;
