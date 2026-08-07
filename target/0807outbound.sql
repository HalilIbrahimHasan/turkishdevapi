
SELECT DISTINCT
    ia.enrollee_id,
    ia.policy_id,
    ia.issuer,
    ia.coverage_year,
    ia.folder_year,
    ia.folder_month,
    ia.enrolleeStatus,
    ia.member_maint_effective_date,
    ia.source_file
FROM dbo.inbound_automation ia
WHERE ia.enrollee_id IN (

'1000923947',
'1001301643',
'1001302341',
'1001302403',
'1001303876',
'1001305545',
'1001305548',
'1002235873'

)
ORDER BY
ia.enrollee_id,
ia.coverage_year,
ia.folder_year,
ia.folder_month;


================================
WITH ffm_policies AS (
    SELECT DISTINCT policy_id
    FROM (VALUES
        ('142635'),
        ('320279'),
        ('4688103'),
        ('3830094')
        -- Excel'deki unique Policy IDs
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

    WHERE folder_year IN (2025,2026)
      AND issuer='37301'
)

SELECT ...
======================================

SELECT
    A.ssn,
    A.applicant_guid,

    E.household_id,
    E.enrollee_id,
    E.enrollment_id,

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

WHERE E.enrollee_id IN (
    '1000923947',
    '1001301643',
    '1001302403',
    '1001302341',
    '1001303876',
    '1001305545',
    '1001305548',
    '1002235873'
)

AND E.hios_issuer_id = 37301

ORDER BY
    E.enrollee_id,
    E.coverage_year,
    E.enrollment_create_date,
    E.enrollment_id;

