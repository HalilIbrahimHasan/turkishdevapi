


/* ============================================================
   RESULT SET 3
   PAIR CLASSIFICATION - FIXED VERSION
   ============================================================ */

DROP TABLE IF EXISTS #pair_classification;


/* ============================================================
   3A. CLASSIFY EACH UNIQUE FFM ENROLLEE + POLICY PAIR
   ============================================================ */

SELECT DISTINCT

    f.ffm_enrollee_id,
    f.ffm_policy_id,

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

    END AS Match_Category

INTO #pair_classification

FROM #ffm_pairs f;


/* ============================================================
   3B. SUMMARY
   ============================================================ */

SELECT
    Match_Category,

    COUNT(*) AS Distinct_Enrollee_Policy_Pairs,

    COUNT(DISTINCT ffm_enrollee_id)
        AS Distinct_Enrollees,

    COUNT(DISTINCT ffm_policy_id)
        AS Distinct_Policies

FROM #pair_classification

GROUP BY
    Match_Category

ORDER BY
    Match_Category;
