DECLARE @Year INT = 2025;   -- Change to 2026 for the next run

DROP TABLE IF EXISTS #base;
DROP TABLE IF EXISTS #latest_enrollment;
DROP TABLE IF EXISTS #latest_enrollee;

/* =========================================================
   1. Create a narrow working population for one coverage year
   ========================================================= */
SELECT
    issuer,

    CASE
        WHEN UPPER(insurance_type) IN ('HEALTH', 'HLT')
            THEN 'Health'
        WHEN UPPER(insurance_type) IN ('DENTAL', 'DEN')
            THEN 'Dental'
        ELSE insurance_type
    END AS insurance_type,

    coverage_year,

    COALESCE(
        NULLIF(policy_id, ''),
        NULLIF(health_coverage_policy_no, '')
    ) AS enrollment_key,

    COALESCE(
        NULLIF(member_id, ''),
        NULLIF(issuer_indiv_identifier, ''),
        NULLIF(exchg_assigned_enrollee_id, '')
    ) AS enrollee_key,

    UPPER(COALESCE(NULLIF(enrolleeStatus, ''), 'UNMAPPED'))
        AS latest_status,

    COALESCE(
        TRY_CONVERT(DATETIME2, member_maint_effective_date),
        TRY_CONVERT(DATETIME2, benefit_effective_date),
        loaded_at
    ) AS business_event_datetime,

    loaded_at,
    file_hash,
    row_number_in_file

INTO #base
FROM dbo.inbound_automation
WHERE folder_year = @Year
  AND coverage_year = @Year
  AND insurance_type IN ('Health', 'Dental')
  AND issuer IS NOT NULL;
