WITH ffm_applicants AS (
    SELECT DISTINCT
        applicant_guid,
        ssn
    FROM dbo.PY242526_Applicants_test
    WHERE applicant_guid IS NOT NULL
)

SELECT DISTINCT
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
FROM ffm_applicants A
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
