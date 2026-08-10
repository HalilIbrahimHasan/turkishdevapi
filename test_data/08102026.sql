


/* ============================================================
   FULL INBOUND 834 HISTORY
   FOR SWATHI'S COMPLETE FFM ENROLLEE POPULATION

   PURPOSE:
   Pull every inbound transaction we have for these enrollees
   across ALL issuers, policies and available years.
   ============================================================ */

WITH target_enrollees AS
(
    SELECT DISTINCT
        LTRIM(RTRIM(CAST(enrollee_id AS VARCHAR(200)))) AS enrollee_id

    FROM (VALUES

        ('1000923947'),
        ('1001301643'),
        ('1001302403'),
        ('1001302341'),
        ('1001303876'),
        ('1001305545'),
        ('1001305548'),
        ('1002235873')

        -- PASTE ALL REMAINING SWATHI FFM ENROLLEE IDs HERE

    ) v(enrollee_id)
),

/* ============================================================
   MATCH TARGET ENROLLEES AGAINST ALL POSSIBLE
   AUTOMATION ENROLLEE IDENTIFIERS

   IMPORTANT:
   No COALESCE here.
   We test every possible identifier independently.
   ============================================================ */

matched_inbound AS
(
    SELECT DISTINCT

        t.enrollee_id AS FFM_Enrollee_ID,

        /* -----------------------------------------
           RAW AUTOMATION IDENTIFIERS
           ----------------------------------------- */

        LTRIM(RTRIM(CAST(ia.member_id AS VARCHAR(200))))
            AS Automation_Member_ID,

        LTRIM(RTRIM(CAST(ia.issuer_indiv_identifier AS VARCHAR(200))))
            AS Automation_Issuer_Indiv_ID,

        LTRIM(RTRIM(CAST(ia.exchg_assigned_enrollee_id AS VARCHAR(200))))
            AS Automation_Exchange_Enrollee_ID,


        /* -----------------------------------------
           IDENTIFY WHICH FIELD MATCHED
           ----------------------------------------- */

        CASE

            WHEN LTRIM(RTRIM(CAST(
                    ia.member_id AS VARCHAR(200)
                 ))) = t.enrollee_id
                THEN 'member_id'

            WHEN LTRIM(RTRIM(CAST(
                    ia.issuer_indiv_identifier AS VARCHAR(200)
                 ))) = t.enrollee_id
                THEN 'issuer_indiv_identifier'

            WHEN LTRIM(RTRIM(CAST(
                    ia.exchg_assigned_enrollee_id AS VARCHAR(200)
                 ))) = t.enrollee_id
                THEN 'exchg_assigned_enrollee_id'

        END AS Matched_Enrollee_Field,


        /* -----------------------------------------
           POLICY IDENTIFIERS
           ----------------------------------------- */

        LTRIM(RTRIM(CAST(ia.policy_id AS VARCHAR(200))))
            AS Automation_Policy_ID,

        LTRIM(RTRIM(CAST(
            ia.health_coverage_policy_no AS VARCHAR(200)
        )))
            AS Automation_Health_Coverage_Policy_No,


        /* -----------------------------------------
           ISSUER / COVERAGE INFORMATION
           ----------------------------------------- */

        ia.issuer
            AS Automation_Issuer,

        ia.coverage_year
            AS Automation_Coverage_Year,

        ia.folder_year,
        ia.folder_month,


        /* -----------------------------------------
           TRANSACTION INFORMATION
           ----------------------------------------- */

        ia.enrolleeStatus
            AS Automation_Status,

        ia.member_maint_effective_date,

        ia.loaded_at,

        ia.source_file


    FROM target_enrollees t

    INNER JOIN dbo.inbound_automation ia

        ON
        (
            LTRIM(RTRIM(CAST(
                ia.member_id AS VARCHAR(200)
            ))) = t.enrollee_id

            OR

            LTRIM(RTRIM(CAST(
                ia.issuer_indiv_identifier AS VARCHAR(200)
            ))) = t.enrollee_id

            OR

            LTRIM(RTRIM(CAST(
                ia.exchg_assigned_enrollee_id AS VARCHAR(200)
            ))) = t.enrollee_id
        )

    /* ========================================================
       INTENTIONALLY NO:

       issuer filter
       coverage_year filter
       folder_year filter

       We want the COMPLETE lifecycle.
       ======================================================== */
)


/* ============================================================
   FINAL FULL TRANSACTION HISTORY
   ============================================================ */

SELECT *

FROM matched_inbound

ORDER BY

    FFM_Enrollee_ID,

    member_maint_effective_date,

    folder_year,

    folder_month,

    Automation_Issuer,

    Automation_Policy_ID,

    source_file;
