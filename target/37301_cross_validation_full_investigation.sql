/*
===============================================================================
37301 CROSS-VALIDATION INVESTIGATION
Raw Inbound 834 vs Enrollments_TEST vs Applicant Migration Evidence
===============================================================================

Purpose
-------
This script documents the read-only investigation performed for issuer 37301,
with emphasis on Coverage Year 2026.

Primary objectives
------------------
1. Validate the total raw 2026 population.
2. Compare Enrollments_TEST and inbound_automation at row, policy, and enrollee level.
3. Identify enrollee and policy overlap.
4. Identify business-only and raw-only populations.
5. Analyze Enrollments_TEST source values.
6. Investigate highlighted migrated households.
7. Classify records as:
      - Both policy and enrollee found
      - Policy found, enrollee missing
      - Enrollee found, policy missing
      - Neither found in inbound
8. Verify the targeted evidence for:
      enrollee_id = 1000162542
      policy_id   = 211121283

Important context
-----------------
- dbo.inbound_automation represents the SFTP-derived inbound 834 raw layer.
- The automation reads inbound "from_..." files.
- dbo.Enrollments_TEST is a broader business-level dataset.
- A record present in Enrollments_TEST or UI but absent from inbound_automation
  cannot be created by the raw automation unless it existed in an inbound 834 file.

No INSERT, UPDATE, DELETE, MERGE, DROP, ALTER, or CREATE TABLE statements are used.
===============================================================================
*/

/* 01. VALIDATE TOTAL 2026 RAW POPULATION
   Expected validated total: 1,029,577. */
SELECT COUNT_BIG(*) AS Total_2026_Raw_Rows
FROM dbo.inbound_automation
WHERE folder_year = 2026;

/* 02. COMPARE ROWS, POLICIES, AND ENROLLEES BY YEAR */
WITH swathi_summary AS (
    SELECT
        coverage_year,
        COUNT_BIG(*) AS Total_Rows,
        COUNT(DISTINCT NULLIF(LTRIM(RTRIM(CAST(enrollment_id AS VARCHAR(200)))), '')) AS Total_Policies,
        COUNT(DISTINCT NULLIF(LTRIM(RTRIM(CAST(enrollee_id AS VARCHAR(200)))), '')) AS Total_Enrollees
    FROM dbo.Enrollments_TEST
    WHERE hios_issuer_id = 37301
      AND coverage_year IN (2025, 2026)
    GROUP BY coverage_year
),
raw_summary AS (
    SELECT
        coverage_year,
        COUNT_BIG(*) AS Total_Rows,
        COUNT(DISTINCT COALESCE(
            NULLIF(LTRIM(RTRIM(CAST(policy_id AS VARCHAR(200)))), ''),
            NULLIF(LTRIM(RTRIM(CAST(health_coverage_policy_no AS VARCHAR(200)))), '')
        )) AS Total_Policies,
        COUNT(DISTINCT COALESCE(
            NULLIF(LTRIM(RTRIM(CAST(member_id AS VARCHAR(200)))), ''),
            NULLIF(LTRIM(RTRIM(CAST(issuer_indiv_identifier AS VARCHAR(200)))), ''),
            NULLIF(LTRIM(RTRIM(CAST(exchg_assigned_enrollee_id AS VARCHAR(200)))), '')
        )) AS Total_Enrollees
    FROM dbo.inbound_automation
    WHERE issuer = '37301'
      AND coverage_year IN (2025, 2026)
    GROUP BY coverage_year
)
SELECT
    COALESCE(s.coverage_year, r.coverage_year) AS Coverage_Year,
    s.Total_Rows AS Enrollments_TEST_Total_Rows,
    s.Total_Policies AS Enrollments_TEST_Total_Policies,
    s.Total_Enrollees AS Enrollments_TEST_Total_Enrollees,
    r.Total_Rows AS Raw_834_Total_Rows,
    r.Total_Policies AS Raw_834_Total_Policies,
    r.Total_Enrollees AS Raw_834_Total_Enrollees
FROM swathi_summary s
FULL OUTER JOIN raw_summary r
    ON s.coverage_year = r.coverage_year
ORDER BY Coverage_Year;

/* 03. ENROLLMENTS_TEST SOURCE BREAKDOWN */
SELECT
    source,
    COUNT_BIG(*) AS Total_Rows,
    COUNT(DISTINCT enrollment_id) AS Distinct_Enrollments,
    COUNT(DISTINCT enrollee_id) AS Distinct_Enrollees
FROM dbo.Enrollments_TEST
WHERE hios_issuer_id = 37301
  AND coverage_year = 2026
GROUP BY source
ORDER BY Distinct_Enrollees DESC;

/* 04. ENROLLEES UNDER MULTIPLE SOURCES */
SELECT
    enrollee_id,
    COUNT(DISTINCT source) AS Source_Count
FROM dbo.Enrollments_TEST
WHERE hios_issuer_id = 37301
  AND coverage_year = 2026
  AND enrollee_id IS NOT NULL
GROUP BY enrollee_id
HAVING COUNT(DISTINCT source) > 1
ORDER BY Source_Count DESC, enrollee_id;

/* 05. MATCH RAW ENROLLEES TO ENROLLMENTS_TEST BY SOURCE */
WITH raw_members AS (
    SELECT DISTINCT LTRIM(RTRIM(CAST(member_id AS VARCHAR(200)))) AS member_id
    FROM dbo.inbound_automation
    WHERE issuer = '37301'
      AND coverage_year = 2026
      AND NULLIF(LTRIM(RTRIM(CAST(member_id AS VARCHAR(200)))), '') IS NOT NULL
)
SELECT
    e.source,
    COUNT(DISTINCT e.enrollee_id) AS Business_Enrollees,
    COUNT(DISTINCT CASE WHEN r.member_id IS NOT NULL THEN e.enrollee_id END) AS Found_In_Raw
FROM dbo.Enrollments_TEST e
LEFT JOIN raw_members r
    ON LTRIM(RTRIM(CAST(e.enrollee_id AS VARCHAR(200)))) = r.member_id
WHERE e.hios_issuer_id = 37301
  AND e.coverage_year = 2026
GROUP BY e.source
ORDER BY Business_Enrollees DESC;

/* 06. OVERALL ENROLLEE POPULATION COMPARISON
   Previously validated: Raw 1453, Business 5450, Matched 1118,
   Business Only 4332, Raw Only 335. */
WITH raw_members AS (
    SELECT DISTINCT LTRIM(RTRIM(CAST(member_id AS VARCHAR(200)))) AS enrollee_id
    FROM dbo.inbound_automation
    WHERE issuer = '37301'
      AND coverage_year = 2026
      AND NULLIF(LTRIM(RTRIM(CAST(member_id AS VARCHAR(200)))), '') IS NOT NULL
),
business_members AS (
    SELECT DISTINCT LTRIM(RTRIM(CAST(enrollee_id AS VARCHAR(200)))) AS enrollee_id
    FROM dbo.Enrollments_TEST
    WHERE hios_issuer_id = 37301
      AND coverage_year = 2026
      AND NULLIF(LTRIM(RTRIM(CAST(enrollee_id AS VARCHAR(200)))), '') IS NOT NULL
)
SELECT
    (SELECT COUNT(*) FROM raw_members) AS Raw_Enrollees,
    (SELECT COUNT(*) FROM business_members) AS Business_Enrollees,
    (SELECT COUNT(*) FROM raw_members r INNER JOIN business_members b ON r.enrollee_id = b.enrollee_id) AS Matched_Enrollees,
    (SELECT COUNT(*) FROM business_members b LEFT JOIN raw_members r ON b.enrollee_id = r.enrollee_id WHERE r.enrollee_id IS NULL) AS Business_Only_Enrollees,
    (SELECT COUNT(*) FROM raw_members r LEFT JOIN business_members b ON r.enrollee_id = b.enrollee_id WHERE b.enrollee_id IS NULL) AS Raw_Only_Enrollees;

/* 07. OVERALL POLICY POPULATION COMPARISON
   Previously validated: Raw 1452, Business 3900, Matching 1069,
   Business Only 2831, Raw Only 383. */
WITH raw_policies AS (
    SELECT DISTINCT LTRIM(RTRIM(CAST(COALESCE(NULLIF(policy_id, ''), NULLIF(health_coverage_policy_no, '')) AS VARCHAR(200)))) AS policy_id
    FROM dbo.inbound_automation
    WHERE issuer = '37301'
      AND coverage_year = 2026
      AND COALESCE(NULLIF(policy_id, ''), NULLIF(health_coverage_policy_no, '')) IS NOT NULL
),
business_policies AS (
    SELECT DISTINCT LTRIM(RTRIM(CAST(enrollment_id AS VARCHAR(200)))) AS policy_id
    FROM dbo.Enrollments_TEST
    WHERE hios_issuer_id = 37301
      AND coverage_year = 2026
      AND enrollment_id IS NOT NULL
)
SELECT
    (SELECT COUNT(*) FROM raw_policies) AS Raw_Policies,
    (SELECT COUNT(*) FROM business_policies) AS Business_Policies,
    (SELECT COUNT(*) FROM raw_policies r INNER JOIN business_policies b ON r.policy_id = b.policy_id) AS Matching_Policies,
    (SELECT COUNT(*) FROM business_policies b LEFT JOIN raw_policies r ON r.policy_id = b.policy_id WHERE r.policy_id IS NULL) AS Business_Only_Policies,
    (SELECT COUNT(*) FROM raw_policies r LEFT JOIN business_policies b ON r.policy_id = b.policy_id WHERE b.policy_id IS NULL) AS Raw_Only_Policies;

/* 08. TEST WHETHER BUSINESS ENROLLEE_ID ALSO CONTAINS RAW POLICY IDS */
WITH raw_ids AS (
    SELECT DISTINCT LTRIM(RTRIM(CAST(member_id AS VARCHAR(200)))) AS id
    FROM dbo.inbound_automation
    WHERE issuer = '37301' AND coverage_year = 2026 AND member_id IS NOT NULL
    UNION
    SELECT DISTINCT LTRIM(RTRIM(CAST(COALESCE(NULLIF(policy_id, ''), NULLIF(health_coverage_policy_no, '')) AS VARCHAR(200)))) AS id
    FROM dbo.inbound_automation
    WHERE issuer = '37301' AND coverage_year = 2026
      AND COALESCE(NULLIF(policy_id, ''), NULLIF(health_coverage_policy_no, '')) IS NOT NULL
),
business_enrollees AS (
    SELECT DISTINCT LTRIM(RTRIM(CAST(enrollee_id AS VARCHAR(200)))) AS enrollee_id
    FROM dbo.Enrollments_TEST
    WHERE hios_issuer_id = 37301 AND coverage_year = 2026 AND enrollee_id IS NOT NULL
)
SELECT
    (SELECT COUNT(*) FROM raw_ids) AS Raw_Combined_IDs,
    (SELECT COUNT(*) FROM business_enrollees) AS Business_Enrollees,
    (SELECT COUNT(*) FROM raw_ids r INNER JOIN business_enrollees b ON r.id = b.enrollee_id) AS Matching_IDs,
    (SELECT COUNT(*) FROM business_enrollees b LEFT JOIN raw_ids r ON r.id = b.enrollee_id WHERE r.id IS NULL) AS Business_Only,
    (SELECT COUNT(*) FROM raw_ids r LEFT JOIN business_enrollees b ON r.id = b.enrollee_id WHERE b.enrollee_id IS NULL) AS Raw_Only;

/* 09. BUSINESS-ONLY ENROLLEE IDS */
WITH raw_enrollees AS (
    SELECT DISTINCT LTRIM(RTRIM(CAST(member_id AS VARCHAR(200)))) AS enrollee_id
    FROM dbo.inbound_automation
    WHERE issuer = '37301' AND coverage_year = 2026
      AND NULLIF(LTRIM(RTRIM(CAST(member_id AS VARCHAR(200)))), '') IS NOT NULL
),
business_enrollees AS (
    SELECT DISTINCT LTRIM(RTRIM(CAST(enrollee_id AS VARCHAR(200)))) AS enrollee_id
    FROM dbo.Enrollments_TEST
    WHERE hios_issuer_id = 37301 AND coverage_year = 2026 AND enrollee_id IS NOT NULL
)
SELECT b.enrollee_id
FROM business_enrollees b
LEFT JOIN raw_enrollees r ON b.enrollee_id = r.enrollee_id
WHERE r.enrollee_id IS NULL
ORDER BY b.enrollee_id;

/* 10. RAW-ONLY ENROLLEE IDS */
WITH raw_enrollees AS (
    SELECT DISTINCT LTRIM(RTRIM(CAST(member_id AS VARCHAR(200)))) AS enrollee_id
    FROM dbo.inbound_automation
    WHERE issuer = '37301' AND coverage_year = 2026
      AND NULLIF(LTRIM(RTRIM(CAST(member_id AS VARCHAR(200)))), '') IS NOT NULL
),
business_enrollees AS (
    SELECT DISTINCT LTRIM(RTRIM(CAST(enrollee_id AS VARCHAR(200)))) AS enrollee_id
    FROM dbo.Enrollments_TEST
    WHERE hios_issuer_id = 37301 AND coverage_year = 2026 AND enrollee_id IS NOT NULL
)
SELECT r.enrollee_id
FROM raw_enrollees r
LEFT JOIN business_enrollees b ON r.enrollee_id = b.enrollee_id
WHERE b.enrollee_id IS NULL
ORDER BY r.enrollee_id;

/* 11. DETAILED BUSINESS-ONLY RECORDS */
WITH raw_enrollees AS (
    SELECT DISTINCT LTRIM(RTRIM(CAST(member_id AS VARCHAR(200)))) AS enrollee_id
    FROM dbo.inbound_automation
    WHERE issuer = '37301' AND coverage_year = 2026
      AND NULLIF(LTRIM(RTRIM(CAST(member_id AS VARCHAR(200)))), '') IS NOT NULL
)
SELECT e.*
FROM dbo.Enrollments_TEST e
LEFT JOIN raw_enrollees r
    ON LTRIM(RTRIM(CAST(e.enrollee_id AS VARCHAR(200)))) = r.enrollee_id
WHERE e.hios_issuer_id = 37301
  AND e.coverage_year = 2026
  AND r.enrollee_id IS NULL
ORDER BY e.enrollee_id, e.enrollment_id;

/* 12. APPLICANT CONTINUITY FOR HIGHLIGHTED HOUSEHOLDS */
SELECT
    coverage_year,
    household_id,
    applicant_guid,
    first_name,
    last_name
FROM dbo.PY242526_Applicants_test
WHERE household_id IN (97970, 98174, 3966)
ORDER BY household_id, applicant_guid, coverage_year;

/* 13. FULL BUSINESS TIMELINE FOR HIGHLIGHTED HOUSEHOLDS */
SELECT
    e.coverage_year,
    e.household_id,
    e.enrollee_id,
    e.enrollment_id,
    e.source,
    e.application_status,
    e.Insurance_Type,
    e.hios_issuer_id,
    e.enrollment_status_description,
    e.enrollee_status_description,
    e.benefit_effective_date,
    e.benefit_end_date,
    e.enrollment_confirmation_date,
    e.enrollment_create_date,
    e.enrollment_last_update_date,
    e.enrollee_create_date,
    e.enrollee_last_update_date
FROM dbo.Enrollments_TEST e
WHERE e.household_id IN (97970, 98174, 3966)
ORDER BY e.household_id, e.enrollee_id, e.coverage_year, e.enrollment_create_date, e.enrollment_id;

/* 14. CLASSIFY HIGHLIGHTED BUSINESS RECORDS AGAINST ALL RAW INBOUND DATA */
WITH business_records AS (
    SELECT DISTINCT
        e.coverage_year,
        e.household_id,
        LTRIM(RTRIM(CAST(e.enrollment_id AS VARCHAR(200)))) AS enrollment_id,
        LTRIM(RTRIM(CAST(e.enrollee_id AS VARCHAR(200)))) AS enrollee_id,
        e.source,
        e.hios_issuer_id,
        e.enrollment_status_description,
        e.enrollee_status_description
    FROM dbo.Enrollments_TEST e
    WHERE e.household_id IN (97970, 98174, 3966)
),
raw_policies AS (
    SELECT DISTINCT LTRIM(RTRIM(CAST(COALESCE(NULLIF(policy_id, ''), NULLIF(health_coverage_policy_no, '')) AS VARCHAR(200)))) AS enrollment_id
    FROM dbo.inbound_automation
    WHERE COALESCE(NULLIF(policy_id, ''), NULLIF(health_coverage_policy_no, '')) IS NOT NULL
),
raw_enrollees AS (
    SELECT DISTINCT LTRIM(RTRIM(CAST(member_id AS VARCHAR(200)))) AS enrollee_id
    FROM dbo.inbound_automation
    WHERE member_id IS NOT NULL
)
SELECT
    b.*,
    CASE WHEN rp.enrollment_id IS NOT NULL THEN 'Y' ELSE 'N' END AS policy_found_in_inbound,
    CASE WHEN re.enrollee_id IS NOT NULL THEN 'Y' ELSE 'N' END AS enrollee_found_in_inbound,
    CASE
        WHEN rp.enrollment_id IS NOT NULL AND re.enrollee_id IS NOT NULL THEN 'Both policy and enrollee found'
        WHEN rp.enrollment_id IS NOT NULL AND re.enrollee_id IS NULL THEN 'Policy found, enrollee missing'
        WHEN rp.enrollment_id IS NULL AND re.enrollee_id IS NOT NULL THEN 'Enrollee found, policy missing'
        ELSE 'Neither found in inbound'
    END AS inbound_classification
FROM business_records b
LEFT JOIN raw_policies rp ON rp.enrollment_id = b.enrollment_id
LEFT JOIN raw_enrollees re ON re.enrollee_id = b.enrollee_id
ORDER BY b.household_id, b.enrollee_id, b.coverage_year, b.enrollment_id;

/* 15. TARGETED ENROLLEE HISTORY FOR 1000162542 */
SELECT
    issuer,
    coverage_year,
    folder_year,
    folder_month,
    COALESCE(NULLIF(policy_id, ''), NULLIF(health_coverage_policy_no, '')) AS inbound_policy,
    member_id AS inbound_enrollee,
    enrolleeStatus,
    member_maint_effective_date,
    loaded_at,
    source_file
FROM dbo.inbound_automation
WHERE member_id = '1000162542'
ORDER BY member_maint_effective_date, loaded_at, issuer;

/* 16. TARGETED 37301 ENROLLEE LOOKUP FOR 1000162542
   Previously validated result: 0 rows. */
SELECT
    issuer,
    coverage_year,
    folder_year,
    folder_month,
    policy_id,
    health_coverage_policy_no,
    member_id,
    issuer_indiv_identifier,
    exchg_assigned_enrollee_id,
    enrolleeStatus,
    source_file,
    member_maint_effective_date
FROM dbo.inbound_automation
WHERE issuer = '37301'
  AND (
        member_id = '1000162542'
        OR issuer_indiv_identifier = '1000162542'
        OR exchg_assigned_enrollee_id = '1000162542'
      )
ORDER BY member_maint_effective_date;

/* 17. TARGETED POLICY LOOKUP FOR 211121283
   Previously validated result: 0 rows. */
SELECT *
FROM dbo.inbound_automation
WHERE policy_id = '211121283'
   OR health_coverage_policy_no = '211121283';

/*
===============================================================================
FINAL EVIDENCE INTERPRETATION
===============================================================================
1. Enrollee 1000162542 was successfully received from issuers 60224 and 89942.
2. No raw inbound record was found for that enrollee under issuer 37301.
3. No raw inbound record was found for policy 211121283.
4. The 37301 business enrollment exists in Enrollments_TEST/UI, but no matching
   inbound 834 record was available in the SFTP-derived raw automation data.
5. This targeted example does not indicate parser or loader loss.
6. Remaining investigation areas:
   - outbound "to_..." records,
   - inbound rejects,
   - FFM migration / annual redetermination,
   - additional Enrollments_TEST sources,
   - meaning of CN, ON, RR, EDE, RF,
   - UI/business records created without an inbound 834.
===============================================================================
*/
