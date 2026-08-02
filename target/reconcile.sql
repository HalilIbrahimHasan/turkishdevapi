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
ORDER BY
    e.household_id,
    e.enrollee_id,
    e.coverage_year,
    e.enrollment_create_date,
    e.enrollment_id;


======================================

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
    SELECT DISTINCT
        LTRIM(RTRIM(CAST(
            COALESCE(
                NULLIF(policy_id, ''),
                NULLIF(health_coverage_policy_no, '')
            ) AS VARCHAR(200)
        ))) AS enrollment_id
    FROM dbo.inbound_automation
),
raw_enrollees AS (
    SELECT DISTINCT
        LTRIM(RTRIM(CAST(
            COALESCE(
                NULLIF(member_id, ''),
                NULLIF(issuer_indiv_identifier, ''),
                NULLIF(exchg_assigned_enrollee_id, '')
            ) AS VARCHAR(200)
        ))) AS enrollee_id
    FROM dbo.inbound_automation
)
SELECT
    b.*,

    CASE
        WHEN rp.enrollment_id IS NOT NULL THEN 'Y'
        ELSE 'N'
    END AS policy_found_in_inbound,

    CASE
        WHEN re.enrollee_id IS NOT NULL THEN 'Y'
        ELSE 'N'
    END AS enrollee_found_in_inbound,

    CASE
        WHEN rp.enrollment_id IS NOT NULL
         AND re.enrollee_id IS NOT NULL
            THEN 'Both policy and enrollee found'
        WHEN rp.enrollment_id IS NOT NULL
         AND re.enrollee_id IS NULL
            THEN 'Policy found, enrollee missing'
        WHEN rp.enrollment_id IS NULL
         AND re.enrollee_id IS NOT NULL
            THEN 'Enrollee found, policy missing'
        ELSE 'Neither found in inbound'
    END AS inbound_classification

FROM business_records b
LEFT JOIN raw_policies rp
    ON rp.enrollment_id = b.enrollment_id
LEFT JOIN raw_enrollees re
    ON re.enrollee_id = b.enrollee_id
ORDER BY
    b.household_id,
    b.enrollee_id,
    b.coverage_year,
    b.enrollment_id;

===================================

WITH target_ids AS (
    SELECT DISTINCT
        LTRIM(RTRIM(CAST(enrollment_id AS VARCHAR(200)))) AS enrollment_id,
        LTRIM(RTRIM(CAST(enrollee_id AS VARCHAR(200)))) AS enrollee_id
    FROM dbo.Enrollments_TEST
    WHERE household_id IN (97970, 98174, 3966)
)
SELECT
    ia.issuer,
    ia.coverage_year,
    ia.folder_year,
    ia.folder_month,
    ia.policy_id,
    ia.health_coverage_policy_no,
    ia.member_id,
    ia.issuer_indiv_identifier,
    ia.enrolleeStatus,
    ia.member_maint_effective_date,
    ia.source_file,
    ia.file_hash
FROM dbo.inbound_automation ia
INNER JOIN target_ids t
    ON LTRIM(RTRIM(CAST(
        COALESCE(
            NULLIF(ia.policy_id, ''),
            NULLIF(ia.health_coverage_policy_no, '')
        ) AS VARCHAR(200)
    ))) = t.enrollment_id

    OR LTRIM(RTRIM(CAST(
        COALESCE(
            NULLIF(ia.member_id, ''),
            NULLIF(ia.issuer_indiv_identifier, ''),
            NULLIF(ia.exchg_assigned_enrollee_id, '')
        ) AS VARCHAR(200)
    ))) = t.enrollee_id
ORDER BY
    ia.coverage_year,
    ia.issuer,
    ia.source_file;
