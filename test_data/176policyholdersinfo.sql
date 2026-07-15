/* Sisense-style Effectuated Enrollments by Issuer
   Source: dbo.inbound_automation
   Read-only query */

SET NOCOUNT ON;

WITH normalized AS (
    SELECT
        ia.issuer,
        ia.folder_year AS coverage_year,

        CASE
            WHEN UPPER(LTRIM(RTRIM(ISNULL(ia.insurance_type, ''))))
                 IN ('HEALTH', 'MEDICAL') THEN 'Health'
            WHEN UPPER(LTRIM(RTRIM(ISNULL(ia.insurance_type, ''))))
                 = 'DENTAL' THEN 'Dental'
            WHEN UPPER(LTRIM(RTRIM(ISNULL(ia.insurance_type, ''))))
                 = 'VISION' THEN 'Vision'
            WHEN UPPER(LTRIM(RTRIM(ISNULL(ia.insurance_type_code, ''))))
                 IN ('HLT', 'HEALTH', 'MEDICAL') THEN 'Health'
            WHEN UPPER(LTRIM(RTRIM(ISNULL(ia.insurance_type_code, ''))))
                 IN ('DEN', 'DENTAL') THEN 'Dental'
            WHEN UPPER(LTRIM(RTRIM(ISNULL(ia.insurance_type_code, ''))))
                 IN ('VIS', 'VISION') THEN 'Vision'
            ELSE COALESCE(
                NULLIF(LTRIM(RTRIM(ia.insurance_type)), ''),
                NULLIF(LTRIM(RTRIM(ia.insurance_type_code)), ''),
                'Unknown'
            )
        END AS insurance_type,

        COALESCE(
            NULLIF(LTRIM(RTRIM(ia.policy_id)), ''),
            NULLIF(LTRIM(RTRIM(ia.health_coverage_policy_no)), '')
        ) AS policy_key,

        NULLIF(LTRIM(RTRIM(ia.member_id)), '') AS member_key,

        CASE
            WHEN UPPER(LTRIM(RTRIM(ISNULL(ia.enrolleeStatus, ''))))
                 IN (
                    'CONFIRM',
                    'CONFIRMED',
                    'EFFECTUATED',
                    'ACTIVE',
                    'ENROLLED',
                    'REINSTATE',
                    'REINSTATED'
                 )
            THEN 1
            ELSE 0
        END AS is_effectuated

    FROM dbo.inbound_automation ia
    WHERE ia.folder_year IN (2025, 2026)
),
counts AS (
    SELECT
        issuer,
        insurance_type,
        coverage_year,

        COUNT(DISTINCT policy_key)
            AS enrollments_total,

        COUNT(DISTINCT member_key)
            AS enrollees_total,

        COUNT(DISTINCT CASE
            WHEN is_effectuated = 1 THEN policy_key
        END) AS enrollments_effectuated,

        COUNT(DISTINCT CASE
            WHEN is_effectuated = 1 THEN member_key
        END) AS enrollees_effectuated

    FROM normalized
    GROUP BY
        issuer,
        insurance_type,
        coverage_year
)
SELECT
    CASE issuer
        WHEN '82824' THEN 'Aetna Health Inc. (a GA corp.)'
        WHEN '83761' THEN 'Alliant Health Plans, Inc.'
        WHEN '70893' THEN 'Ambetter from Peach State Health Plan'
        WHEN '45334' THEN 'Anthem Blue Cross and Blue Shield'
        WHEN '83502' THEN 'BEST Life and Health Insurance Company'
        WHEN '60224' THEN 'CareSource Georgia Co.'
        WHEN '15105' THEN 'Cigna HealthCare of Georgia, Inc.'
        WHEN '86637' THEN 'Delta Dental Insurance Company'
        WHEN '68806' THEN
            'DentaQuest National Insurance Company, Inc.'
        WHEN '64357' THEN 'Dominion Dental Services, Inc.'
        WHEN '37301' THEN
            'Educators Health Plans Life, Accident and Health, Inc.'
        WHEN '37001' THEN 'Humana Insurance Company'
        WHEN '89942' THEN
            'Kaiser Foundation Health Plan of Georgia, Inc.'
        WHEN '58081' THEN 'Oscar Health Plan of Georgia'
        WHEN '13535' THEN 'UnitedHealthcare Insurance Company'
        WHEN '43802' THEN 'UnitedHealthcare of Georgia Inc.'
        ELSE 'Issuer ' + issuer
    END AS issuer_name,

    issuer AS hios_issuer_id,
    insurance_type,
    coverage_year,

    enrollments_total,
    enrollees_total,
    enrollments_effectuated,
    enrollees_effectuated,

    enrollments_total - enrollments_effectuated
        AS enrollments_pending_effectuation,

    enrollees_total - enrollees_effectuated
        AS enrollees_pending_effectuation

FROM counts
ORDER BY
    issuer_name,
    hios_issuer_id,
    insurance_type,
    coverage_year;


==================

SELECT
    COUNT(*) AS all_raw_rows,
    SUM(CASE WHEN folder_year = 2025 THEN 1 ELSE 0 END) AS folder_2025_rows,
    SUM(CASE WHEN folder_year = 2026 THEN 1 ELSE 0 END) AS folder_2026_rows,
    SUM(CASE WHEN folder_year IN (2025, 2026) THEN 1 ELSE 0 END)
        AS folder_2025_2026_rows
FROM dbo.inbound_automation;
/* ================================================================
   Sisense-style Effectuated Enrollments by Issuer
   Source: dbo.inbound_automation
   Years: 2025 and 2026

   Definitions:
     Enrollment = distinct policy identifier
     Enrollee   = distinct member_id
     Effectuated = entity has at least one CONFIRM transaction
     Pending     = total entity count minus effectuated entity count

   REINSTATE is included as effectuated for safety, although inbound
   enrichment normally maps REINSTATE to CONFIRM.
   ================================================================ */

SET NOCOUNT ON;

DROP TABLE IF EXISTS #base;
DROP TABLE IF EXISTS #policies;
DROP TABLE IF EXISTS #enrollees;

/* Step 1: Normalize raw records once */
SELECT
    ia.issuer,

    /* Closest raw-data equivalent to Sisense coverage year.
       Prefer the actual benefit effective year. */
    COALESCE(
        YEAR(ia.benefit_effective_date),
        ia.coverage_year,
        ia.folder_year
    ) AS coverage_year,

    CASE
        WHEN UPPER(LTRIM(RTRIM(ISNULL(ia.insurance_type, ''))))
             IN ('HEALTH', 'MEDICAL') THEN 'Health'
        WHEN UPPER(LTRIM(RTRIM(ISNULL(ia.insurance_type, ''))))
             IN ('DENTAL') THEN 'Dental'
        WHEN UPPER(LTRIM(RTRIM(ISNULL(ia.insurance_type, ''))))
             IN ('VISION') THEN 'Vision'
        WHEN UPPER(LTRIM(RTRIM(ISNULL(ia.insurance_type_code, ''))))
             IN ('HLT', 'HEALTH', 'MEDICAL') THEN 'Health'
        WHEN UPPER(LTRIM(RTRIM(ISNULL(ia.insurance_type_code, ''))))
             IN ('DEN', 'DENTAL') THEN 'Dental'
        WHEN UPPER(LTRIM(RTRIM(ISNULL(ia.insurance_type_code, ''))))
             IN ('VIS', 'VISION') THEN 'Vision'
        ELSE COALESCE(
            NULLIF(LTRIM(RTRIM(ia.insurance_type)), ''),
            NULLIF(LTRIM(RTRIM(ia.insurance_type_code)), ''),
            'Unknown'
        )
    END AS insurance_type,

    /* Policy fallback used because some issuers do not populate policy_id */
    COALESCE(
        NULLIF(LTRIM(RTRIM(ia.policy_id)), ''),
        NULLIF(LTRIM(RTRIM(ia.health_coverage_policy_no)), '')
    ) AS policy_key,

    NULLIF(LTRIM(RTRIM(ia.member_id)), '') AS member_key,

    CASE
        WHEN UPPER(LTRIM(RTRIM(ISNULL(ia.enrolleeStatus, ''))))
             IN ('CONFIRM', 'CONFIRMED', 'EFFECTUATED',
                 'ACTIVE', 'ENROLLED', 'REINSTATE', 'REINSTATED')
        THEN 1
        ELSE 0
    END AS is_effectuated
INTO #base
FROM dbo.inbound_automation ia
WHERE COALESCE(
          YEAR(ia.benefit_effective_date),
          ia.coverage_year,
          ia.folder_year
      ) IN (2025, 2026);


/* Helpful indexes for the following aggregations */
CREATE CLUSTERED INDEX IX_base_policy
ON #base (coverage_year, issuer, insurance_type, policy_key);

CREATE NONCLUSTERED INDEX IX_base_member
ON #base (coverage_year, issuer, insurance_type, member_key)
INCLUDE (is_effectuated);


/* Step 2: One record per policy.
   MAX(is_effectuated) means a policy is effectuated if it has
   at least one CONFIRM/effectuation transaction. */
SELECT
    issuer,
    coverage_year,
    insurance_type,
    policy_key,
    MAX(is_effectuated) AS is_effectuated
INTO #policies
FROM #base
WHERE policy_key IS NOT NULL
GROUP BY
    issuer,
    coverage_year,
    insurance_type,
    policy_key;

CREATE CLUSTERED INDEX IX_policies
ON #policies (coverage_year, issuer, insurance_type);


/* Step 3: One record per enrollee/member */
SELECT
    issuer,
    coverage_year,
    insurance_type,
    member_key,
    MAX(is_effectuated) AS is_effectuated
INTO #enrollees
FROM #base
WHERE member_key IS NOT NULL
GROUP BY
    issuer,
    coverage_year,
    insurance_type,
    member_key;

CREATE CLUSTERED INDEX IX_enrollees
ON #enrollees (coverage_year, issuer, insurance_type);


/* Step 4: Produce the Sisense report structure */
WITH policy_counts AS (
    SELECT
        issuer,
        coverage_year,
        insurance_type,
        COUNT(*) AS enrollments_total,
        SUM(is_effectuated) AS enrollments_effectuated,
        COUNT(*) - SUM(is_effectuated)
            AS enrollments_pending_effectuation
    FROM #policies
    GROUP BY issuer, coverage_year, insurance_type
),
enrollee_counts AS (
    SELECT
        issuer,
        coverage_year,
        insurance_type,
        COUNT(*) AS enrollees_total,
        SUM(is_effectuated) AS enrollees_effectuated,
        COUNT(*) - SUM(is_effectuated)
            AS enrollees_pending_effectuation
    FROM #enrollees
    GROUP BY issuer, coverage_year, insurance_type
),
dimensions AS (
    SELECT issuer, coverage_year, insurance_type FROM policy_counts
    UNION
    SELECT issuer, coverage_year, insurance_type FROM enrollee_counts
)
SELECT
    CASE d.issuer
        WHEN '82824' THEN 'Aetna Health Inc. (a GA corp.)'
        WHEN '83761' THEN 'Alliant Health Plans, Inc.'
        WHEN '70893' THEN 'Ambetter from Peach State Health Plan'
        WHEN '45334' THEN 'Anthem Blue Cross and Blue Shield'
        WHEN '83502' THEN 'BEST Life and Health Insurance Company'
        WHEN '60224' THEN 'CareSource Georgia Co.'
        WHEN '15105' THEN 'Cigna HealthCare of Georgia, Inc.'
        WHEN '86637' THEN 'Delta Dental Insurance Company'
        WHEN '68806' THEN 'DentaQuest National Insurance Company, Inc.'
        WHEN '64357' THEN 'Dominion Dental Services, Inc.'
        WHEN '37301' THEN
            'Educators Health Plans Life, Accident and Health, Inc.'
        WHEN '37001' THEN 'Humana Insurance Company'
        WHEN '89942' THEN
            'Kaiser Foundation Health Plan of Georgia, Inc.'
        WHEN '58081' THEN 'Oscar Health Plan of Georgia'
        WHEN '13535' THEN 'UnitedHealthcare Insurance Company'
        WHEN '43802' THEN 'UnitedHealthcare of Georgia Inc.'
        ELSE 'Issuer ' + d.issuer
    END AS issuer_name,

    d.issuer AS hios_issuer_id,
    d.insurance_type,
    d.coverage_year,

    ISNULL(p.enrollments_total, 0)
        AS enrollments_total,

    ISNULL(e.enrollees_total, 0)
        AS enrollees_total,

    ISNULL(p.enrollments_effectuated, 0)
        AS enrollments_effectuated,

    ISNULL(e.enrollees_effectuated, 0)
        AS enrollees_effectuated,

    ISNULL(p.enrollments_pending_effectuation, 0)
        AS enrollments_pending_effectuation,

    ISNULL(e.enrollees_pending_effectuation, 0)
        AS enrollees_pending_effectuation

FROM dimensions d
LEFT JOIN policy_counts p
    ON p.issuer = d.issuer
   AND p.coverage_year = d.coverage_year
   AND p.insurance_type = d.insurance_type
LEFT JOIN enrollee_counts e
    ON e.issuer = d.issuer
   AND e.coverage_year = d.coverage_year
   AND e.insurance_type = d.insurance_type
ORDER BY
    issuer_name,
    d.issuer,
    d.insurance_type,
    d.coverage_year;


/* Optional cleanup */
DROP TABLE IF EXISTS #enrollees;
DROP TABLE IF EXISTS #policies;
DROP TABLE IF EXISTS #base;
