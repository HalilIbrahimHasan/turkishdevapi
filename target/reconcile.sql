SELECT
    coverage_year,
    household_id,
    applicant_guid,
    first_name,
    last_name
FROM dbo.PY242526_Applicants_test
WHERE applicant_guid IN (
    -- missing enrollee IDs here
)
ORDER BY
    household_id,
    applicant_guid;


SELECT
    coverage_year,
    household_id,
    applicant_guid,
    first_name,
    last_name
FROM dbo.PY242526_Applicants_test
WHERE household_id IN (97970, 98174, 3966)
ORDER BY
    household_id,
    applicant_guid;
