


/* ============================================================
   SAME TRANSACTION / DIFFERENT POLICY RECONCILIATION
   FFM: dbo.Enrollments_TEST
   Inbound: dbo.inbound_automation

   Scope:
      FFM issuer = 37301
      ALL coverage years
      ALL inbound issuers
      ALL inbound years

   Matching strategy:
      Enrollee first
      Policy is comparison/ranking criteria
   ============================================================ */

DROP TABLE IF EXISTS #final_results;

DECLARE @ffm_issuer VARCHAR(20) = '37301';


;WITH ffm AS
(
    SELECT

        CAST(e.enrollee_id AS VARCHAR(100))
            AS FFM_Enrollee_ID,

        CAST(e.enrollment_id AS VARCHAR(100))
            AS FFM_Policy_ID,

        CAST(e.hios_issuer_id AS VARCHAR(20))
            AS FFM_Issuer,

        e.coverage_year
            AS FFM_Coverage_Year,

        e.enrollment_status_description
            AS FFM_Enrollment_Status_Raw,

        e.enrollee_status_description
            AS FFM_Enrollee_Status_Raw,


        /* ====================================================
           FFM RAW STATUS
           Prefer enrollee status, otherwise enrollment status
           ==================================================== */

        COALESCE(
            e.enrollee_status_description,
            e.enrollment_status_description
        ) AS FFM_Status_Raw,


        /* ====================================================
           FFM NORMALIZED STATUS
           ==================================================== */

        CASE

            WHEN UPPER(
                LTRIM(RTRIM(
                    COALESCE(
                        e.enrollee_status_description,
                        e.enrollment_status_description
                    )
                ))
            ) = 'ENROLLED'
                THEN 'CONFIRM'


            WHEN UPPER(
                LTRIM(RTRIM(
                    COALESCE(
                        e.enrollee_status_description,
                        e.enrollment_status_description
                    )
                ))
            ) IN ('CANCELLED', 'CANCELED')
                THEN 'CANCEL'


            WHEN UPPER(
                LTRIM(RTRIM(
                    COALESCE(
                        e.enrollee_status_description,
                        e.enrollment_status_description
                    )
                ))
            ) = 'TERMINATED'
                THEN 'TERM'


            ELSE 'STATUS_MAPPING_REVIEW'

        END AS FFM_Status_Norm,


        /* ====================================================
           FFM DATES
           ==================================================== */

        e.benefit_effective_date,
        e.benefit_end_date,
        e.enrollment_create_date,
        e.enrollment_last_update_date,


        /* ====================================================
           BEST AVAILABLE FFM BUSINESS EVENT DATE

           Cursor analysis found:
           enrollment_last_update_date
           was the strongest date correlate.
           ==================================================== */

        COALESCE(

            e.enrollment_last_update_date,

            CASE
                WHEN UPPER(
                    LTRIM(RTRIM(
                        COALESCE(
                            e.enrollee_status_description,
                            e.enrollment_status_description
                        )
                    ))
                ) IN (
                    'CANCELLED',
                    'CANCELED',
                    'TERMINATED'
                )
                THEN e.benefit_end_date
            END,

            e.enrollment_create_date,

            e.benefit_effective_date

        ) AS FFM_Event_Date,


        /* ====================================================
           HOUSEHOLD / RELATIONSHIP
           ==================================================== */

        e.household_id,
        e.person_type,
        e.relationship_type,

        e.source AS FFM_Source

    FROM dbo.Enrollments_TEST e

    WHERE CAST(e.hios_issuer_id AS VARCHAR(20))
          = @ffm_issuer
),


/* ============================================================
   INBOUND POPULATION
   ALL ISSUERS / ALL YEARS

   IMPORTANT FIX:
   Check THREE possible enrollee identifiers.
   ============================================================ */

inbound AS
(
    SELECT

        /* ====================================================
           ENROLLEE IDENTIFIER
           ==================================================== */

        CAST(
            COALESCE(

                NULLIF(
                    LTRIM(RTRIM(
                        CAST(ia.member_id AS VARCHAR(200))
                    )),
                    ''
                ),

                NULLIF(
                    LTRIM(RTRIM(
                        CAST(ia.issuer_indiv_identifier AS VARCHAR(200))
                    )),
                    ''
                ),

                NULLIF(
                    LTRIM(RTRIM(
                        CAST(ia.exchg_assigned_enrollee_id AS VARCHAR(200))
                    )),
                    ''
                )

            )
            AS VARCHAR(100)
        ) AS Inbound_Enrollee_ID,


        /* ====================================================
           POLICY IDENTIFIER
           ==================================================== */

        CAST(
            COALESCE(

                NULLIF(
                    LTRIM(RTRIM(
                        CAST(ia.policy_id AS VARCHAR(200))
                    )),
                    ''
                ),

                NULLIF(
                    LTRIM(RTRIM(
                        CAST(ia.health_coverage_policy_no AS VARCHAR(200))
                    )),
                    ''
                )

            )
            AS VARCHAR(100)
        ) AS Inbound_Policy_ID,


        CAST(ia.issuer AS VARCHAR(20))
            AS Inbound_Issuer,

        ia.coverage_year
            AS Inbound_Coverage_Year,

        ia.enrolleeStatus
            AS Inbound_Status_Raw,


        /* ====================================================
           INBOUND NORMALIZED STATUS
           ==================================================== */

        CASE

            WHEN UPPER(
                LTRIM(RTRIM(ia.enrolleeStatus))
            ) = 'CONFIRM'
                THEN 'CONFIRM'

            WHEN UPPER(
                LTRIM(RTRIM(ia.enrolleeStatus))
            ) = 'CANCEL'
                THEN 'CANCEL'

            WHEN UPPER(
                LTRIM(RTRIM(ia.enrolleeStatus))
            ) = 'TERM'
                THEN 'TERM'

            ELSE 'STATUS_MAPPING_REVIEW'

        END AS Inbound_Status_Norm,


        /* ====================================================
           RAW INBOUND DATES
           ==================================================== */

        ia.member_maint_effective_date,

        ia.benefit_effective_date
            AS Inbound_Benefit_Effective_Date,

        ia.benefit_end_date
            AS Inbound_Benefit_End_Date,


        /* ====================================================
           FILE DATE

           Extract YYYYMMDD from source filename where available.
           ==================================================== */

        CASE

            WHEN PATINDEX(
                '%[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]%',
                ia.source_file
            ) > 0

            THEN TRY_CONVERT(
                DATE,

                SUBSTRING(
                    ia.source_file,

                    PATINDEX(
                        '%[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]%',
                        ia.source_file
                    ),

                    8
                ),

                112
            )

        END AS Inbound_File_Date,


        /* ====================================================
           BEST AVAILABLE INBOUND BUSINESS EVENT DATE

           loaded_at is intentionally NOT used as business date.
           ==================================================== */

        COALESCE(

            ia.member_maint_effective_date,

            CASE

                WHEN PATINDEX(
                    '%[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]%',
                    ia.source_file
                ) > 0

                THEN TRY_CONVERT(
                    DATE,

                    SUBSTRING(
                        ia.source_file,

                        PATINDEX(
                            '%[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]%',
                            ia.source_file
                        ),

                        8
                    ),

                    112
                )

            END,

            ia.benefit_effective_date

        ) AS Inbound_Event_Date,


        ia.folder_year
            AS Folder_Year,

        ia.folder_month
            AS Folder_Month,

        ia.source_file
            AS Source_File,

        ia.household_or_employee_case_id,

        ia.relationship,

        ia.loaded_at,

        ia.id
            AS inbound_row_id

    FROM dbo.inbound_automation ia

    WHERE

        COALESCE(

            NULLIF(
                LTRIM(RTRIM(
                    CAST(ia.member_id AS VARCHAR(200))
                )),
                ''
            ),

            NULLIF(
                LTRIM(RTRIM(
                    CAST(ia.issuer_indiv_identifier AS VARCHAR(200))
                )),
                ''
            ),

            NULLIF(
                LTRIM(RTRIM(
                    CAST(ia.exchg_assigned_enrollee_id AS VARCHAR(200))
                )),
                ''
            )

        ) IS NOT NULL
),


/* ============================================================
   CANDIDATE MATCHES

   JOIN IS ENROLLEE-FIRST.

   Policy ID is NOT required to join.
   ============================================================ */

candidates AS
(
    SELECT

        /* --------------------
           FFM
           -------------------- */

        f.FFM_Enrollee_ID,
        f.FFM_Policy_ID,
        f.FFM_Issuer,
        f.FFM_Coverage_Year,

        f.FFM_Enrollment_Status_Raw,
        f.FFM_Enrollee_Status_Raw,

        f.FFM_Status_Raw,
        f.FFM_Status_Norm,

        f.FFM_Event_Date,

        f.benefit_effective_date
            AS FFM_Benefit_Effective_Date,

        f.benefit_end_date
            AS FFM_Benefit_End_Date,

        f.enrollment_create_date
            AS FFM_Create_Date,

        f.enrollment_last_update_date
            AS FFM_Last_Update_Date,

        f.household_id,

        f.person_type,

        f.relationship_type,


        /* --------------------
           INBOUND
           -------------------- */

        i.Inbound_Enrollee_ID,
        i.Inbound_Policy_ID,
        i.Inbound_Issuer,
        i.Inbound_Coverage_Year,

        i.Inbound_Status_Raw,
        i.Inbound_Status_Norm,

        i.Inbound_Event_Date,

        i.member_maint_effective_date,

        i.Inbound_File_Date,

        i.Folder_Year,
        i.Folder_Month,

        i.Source_File,

        i.household_or_employee_case_id,

        i.relationship
            AS Inbound_Relationship,


        /* ====================================================
           MATCH FLAGS
           ==================================================== */

        CASE
            WHEN f.FFM_Policy_ID = i.Inbound_Policy_ID
                THEN 'YES'
            ELSE 'NO'
        END AS Policy_Match_Flag,


        CASE
            WHEN f.FFM_Issuer = i.Inbound_Issuer
                THEN 'YES'
            ELSE 'NO'
        END AS Issuer_Match_Flag,


        CASE

            WHEN f.FFM_Status_Norm = i.Inbound_Status_Norm
             AND f.FFM_Status_Norm <> 'STATUS_MAPPING_REVIEW'

                THEN 'YES'

            ELSE 'NO'

        END AS Status_Match_Flag,


        /* ====================================================
           DATE DIFFERENCE
           ==================================================== */

        CASE

            WHEN f.FFM_Event_Date IS NOT NULL
             AND i.Inbound_Event_Date IS NOT NULL

            THEN ABS(
                DATEDIFF(
                    DAY,
                    f.FFM_Event_Date,
                    i.Inbound_Event_Date
                )
            )

        END AS Date_Difference_Days,


        /* ====================================================
           MATCH RANK

           LOWER = BETTER
           ==================================================== */

        CASE

            /* Exact enrollee + policy */
            WHEN f.FFM_Policy_ID = i.Inbound_Policy_ID
                THEN 1


            /* Same issuer/status/exact date */
            WHEN f.FFM_Issuer = i.Inbound_Issuer
             AND f.FFM_Status_Norm = i.Inbound_Status_Norm
             AND f.FFM_Status_Norm <> 'STATUS_MAPPING_REVIEW'
             AND f.FFM_Event_Date IS NOT NULL
             AND i.Inbound_Event_Date IS NOT NULL
             AND ABS(
                    DATEDIFF(
                        DAY,
                        f.FFM_Event_Date,
                        i.Inbound_Event_Date
                    )
                 ) = 0

                THEN 2


            /* Same issuer/status within 7 days */
            WHEN f.FFM_Issuer = i.Inbound_Issuer
             AND f.FFM_Status_Norm = i.Inbound_Status_Norm
             AND f.FFM_Status_Norm <> 'STATUS_MAPPING_REVIEW'
             AND f.FFM_Event_Date IS NOT NULL
             AND i.Inbound_Event_Date IS NOT NULL
             AND ABS(
                    DATEDIFF(
                        DAY,
                        f.FFM_Event_Date,
                        i.Inbound_Event_Date
                    )
                 ) <= 7

                THEN 3


            /* Same issuer + same status */
            WHEN f.FFM_Issuer = i.Inbound_Issuer
             AND f.FFM_Status_Norm = i.Inbound_Status_Norm
             AND f.FFM_Status_Norm <> 'STATUS_MAPPING_REVIEW'

                THEN 4


            /* Same issuer */
            WHEN f.FFM_Issuer = i.Inbound_Issuer
                THEN 5


            /* Cross issuer + same status + within 30 days */
            WHEN f.FFM_Status_Norm = i.Inbound_Status_Norm
             AND f.FFM_Status_Norm <> 'STATUS_MAPPING_REVIEW'
             AND f.FFM_Event_Date IS NOT NULL
             AND i.Inbound_Event_Date IS NOT NULL
             AND ABS(
                    DATEDIFF(
                        DAY,
                        f.FFM_Event_Date,
                        i.Inbound_Event_Date
                    )
                 ) <= 30

                THEN 6


            /* Cross issuer + same status */
            WHEN f.FFM_Status_Norm = i.Inbound_Status_Norm
             AND f.FFM_Status_Norm <> 'STATUS_MAPPING_REVIEW'

                THEN 7


            /* Same enrollee only */
            ELSE 8

        END AS rank_priority,


        i.inbound_row_id

    FROM ffm f

    INNER JOIN inbound i

        ON f.FFM_Enrollee_ID
         = i.Inbound_Enrollee_ID
),


/* ============================================================
   RANK BEST INBOUND CANDIDATE
   PER FFM ENROLLEE + POLICY
   ============================================================ */

ranked AS
(
    SELECT

        c.*,

        ROW_NUMBER() OVER
        (
            PARTITION BY
                c.FFM_Enrollee_ID,
                c.FFM_Policy_ID

            ORDER BY

                c.rank_priority ASC,

                CASE
                    WHEN c.Date_Difference_Days IS NULL
                        THEN 999999
                    ELSE c.Date_Difference_Days
                END ASC,

                c.inbound_row_id DESC
        ) AS rn

    FROM candidates c
),


best AS
(
    SELECT *
    FROM ranked
    WHERE rn = 1
),


/* ============================================================
   FINAL CLASSIFICATION
   ============================================================ */

final AS
(
    SELECT

        f.FFM_Enrollee_ID,
        f.FFM_Policy_ID,
        f.FFM_Issuer,
        f.FFM_Coverage_Year,

        f.FFM_Status_Raw,
        f.FFM_Status_Norm,

        f.FFM_Event_Date,

        f.household_id,
        f.person_type,
        f.relationship_type,


        b.Inbound_Enrollee_ID,
        b.Inbound_Policy_ID,
        b.Inbound_Issuer,
        b.Inbound_Coverage_Year,

        b.Inbound_Status_Raw,
        b.Inbound_Status_Norm,

        b.Inbound_Event_Date,

        b.member_maint_effective_date,

        b.Inbound_File_Date,

        b.Folder_Year,
        b.Folder_Month,

        b.Source_File,


        COALESCE(
            b.Policy_Match_Flag,
            'NO'
        ) AS Policy_Match_Flag,


        COALESCE(
            b.Issuer_Match_Flag,
            'NO'
        ) AS Issuer_Match_Flag,


        COALESCE(
            b.Status_Match_Flag,
            'NO'
        ) AS Status_Match_Flag,


        b.Date_Difference_Days,


        /* ====================================================
           MATCH LEVEL
           ==================================================== */

        CASE

            WHEN b.Inbound_Enrollee_ID IS NULL

                THEN 'NO_INBOUND_ENROLLEE_EVIDENCE'


            WHEN b.Policy_Match_Flag = 'YES'

                THEN 'EXACT_ENROLLEE_POLICY_MATCH'


            WHEN b.Issuer_Match_Flag = 'YES'
             AND b.Status_Match_Flag = 'YES'
             AND b.Date_Difference_Days IS NOT NULL
             AND b.Date_Difference_Days <= 7

                THEN 'SAME_TRANSACTION_DIFFERENT_POLICY'


            WHEN b.Issuer_Match_Flag = 'YES'
             AND b.Status_Match_Flag = 'YES'

                THEN 'SAME_LIFECYCLE_DIFFERENT_POLICY'


            WHEN b.Issuer_Match_Flag = 'NO'
             AND b.Status_Match_Flag = 'YES'

                THEN 'CROSS_ISSUER_TRANSITION'


            WHEN b.Inbound_Enrollee_ID IS NOT NULL

                THEN 'ENROLLEE_FOUND_DIFFERENT_LIFECYCLE'


            ELSE 'NO_INBOUND_ENROLLEE_EVIDENCE'

        END AS Match_Level,


        /* ====================================================
           MATCH STRENGTH
           ==================================================== */

        CASE

            WHEN b.Inbound_Enrollee_ID IS NULL
                THEN 'NO_MATCH'


            WHEN b.Policy_Match_Flag = 'YES'
                THEN 'VERY_STRONG'


            WHEN b.Issuer_Match_Flag = 'YES'
             AND b.Status_Match_Flag = 'YES'
             AND b.Date_Difference_Days IS NOT NULL
             AND b.Date_Difference_Days <= 7

                THEN 'VERY_STRONG'


            WHEN b.Issuer_Match_Flag = 'YES'
             AND b.Status_Match_Flag = 'YES'
             AND b.Date_Difference_Days IS NOT NULL
             AND b.Date_Difference_Days <= 30

                THEN 'STRONG'


            WHEN b.Issuer_Match_Flag = 'NO'
             AND b.Status_Match_Flag = 'YES'

                THEN 'CROSS_ISSUER'


            WHEN b.Inbound_Enrollee_ID IS NOT NULL

                THEN 'WEAK'


            ELSE 'NO_MATCH'

        END AS Match_Score,


        /* ====================================================
           ROOT CAUSE CATEGORY
           ==================================================== */

        CASE

            WHEN b.Inbound_Enrollee_ID IS NULL

                THEN 'NO_INBOUND_EVIDENCE'


            WHEN b.Policy_Match_Flag = 'YES'

                THEN 'EXACT_POLICY_MATCH'


            WHEN b.Issuer_Match_Flag = 'YES'
             AND b.Status_Match_Flag = 'YES'
             AND b.Date_Difference_Days IS NOT NULL
             AND b.Date_Difference_Days <= 30

                THEN 'POTENTIAL_POLICY_IDENTIFIER_MISMATCH'


            WHEN b.Issuer_Match_Flag = 'YES'
             AND b.Policy_Match_Flag = 'NO'

                THEN 'SAME_ISSUER_DIFFERENT_POLICY'


            WHEN b.Issuer_Match_Flag = 'NO'
             AND b.Status_Match_Flag = 'YES'

                THEN 'CROSS_ISSUER_TRANSITION'


            WHEN b.Inbound_Enrollee_ID IS NOT NULL

                THEN 'DIFFERENT_LIFECYCLE'


            ELSE 'NO_INBOUND_EVIDENCE'

        END AS Root_Cause_Category

    FROM ffm f

    LEFT JOIN best b

        ON f.FFM_Enrollee_ID
         = b.FFM_Enrollee_ID

       AND f.FFM_Policy_ID
         = b.FFM_Policy_ID
)


/* ============================================================
   SAVE FINAL RESULTS
   Allows multiple result sets from one execution
   ============================================================ */

SELECT *
INTO #final_results
FROM final;


/* ============================================================
   RESULT SET 1
   FULL DETAIL
   ============================================================ */

SELECT *

FROM #final_results

ORDER BY

    CASE Root_Cause_Category

        WHEN 'EXACT_POLICY_MATCH'
            THEN 1

        WHEN 'POTENTIAL_POLICY_IDENTIFIER_MISMATCH'
            THEN 2

        WHEN 'SAME_ISSUER_DIFFERENT_POLICY'
            THEN 3

        WHEN 'CROSS_ISSUER_TRANSITION'
            THEN 4

        WHEN 'DIFFERENT_LIFECYCLE'
            THEN 5

        ELSE 6

    END,

    FFM_Enrollee_ID,
    FFM_Policy_ID;


/* ============================================================
   RESULT SET 2
   MATCH LEVEL SUMMARY
   ============================================================ */

SELECT

    Match_Level,

    COUNT(
        DISTINCT CONCAT(
            FFM_Enrollee_ID,
            '|',
            FFM_Policy_ID
        )
    ) AS Distinct_FFM_Pairs,

    COUNT(DISTINCT FFM_Enrollee_ID)
        AS Distinct_Enrollees,

    COUNT(DISTINCT FFM_Policy_ID)
        AS Distinct_FFM_Policies,

    CAST(
        100.0
        *
        COUNT(
            DISTINCT CONCAT(
                FFM_Enrollee_ID,
                '|',
                FFM_Policy_ID
            )
        )
        /
        NULLIF(
            (
                SELECT COUNT(
                    DISTINCT CONCAT(
                        FFM_Enrollee_ID,
                        '|',
                        FFM_Policy_ID
                    )
                )
                FROM #final_results
            ),
            0
        )
        AS DECIMAL(8,2)
    ) AS Percentage

FROM #final_results

GROUP BY
    Match_Level

ORDER BY
    Distinct_FFM_Pairs DESC;


/* ============================================================
   RESULT SET 3
   ROOT CAUSE SUMMARY
   ============================================================ */

SELECT

    Root_Cause_Category,

    COUNT(
        DISTINCT CONCAT(
            FFM_Enrollee_ID,
            '|',
            FFM_Policy_ID
        )
    ) AS Distinct_FFM_Pairs,

    COUNT(DISTINCT FFM_Enrollee_ID)
        AS Distinct_Enrollees,

    COUNT(DISTINCT FFM_Policy_ID)
        AS Distinct_FFM_Policies,

    COUNT(DISTINCT Inbound_Policy_ID)
        AS Distinct_Inbound_Policies,

    CAST(
        100.0
        *
        COUNT(
            DISTINCT CONCAT(
                FFM_Enrollee_ID,
                '|',
                FFM_Policy_ID
            )
        )
        /
        NULLIF(
            (
                SELECT COUNT(
                    DISTINCT CONCAT(
                        FFM_Enrollee_ID,
                        '|',
                        FFM_Policy_ID
                    )
                )
                FROM #final_results
            ),
            0
        )
        AS DECIMAL(8,2)
    ) AS Percentage

FROM #final_results

GROUP BY
    Root_Cause_Category

ORDER BY
    Distinct_FFM_Pairs DESC;


/* ============================================================
   RESULT SET 4
   POTENTIAL POLICY IDENTIFIER MISMATCH

   Same enrollee
   Same issuer
   Compatible status
   Near event date
   Different policy
   ============================================================ */

SELECT

    COUNT(
        DISTINCT CONCAT(
            FFM_Enrollee_ID,
            '|',
            FFM_Policy_ID
        )
    ) AS Matched_Transaction_Relationships,

    COUNT(DISTINCT FFM_Enrollee_ID)
        AS Distinct_Enrollees,

    COUNT(DISTINCT FFM_Policy_ID)
        AS Distinct_FFM_Policies,

    COUNT(DISTINCT Inbound_Policy_ID)
        AS Distinct_Inbound_Policies

FROM #final_results

WHERE Root_Cause_Category =
      'POTENTIAL_POLICY_IDENTIFIER_MISMATCH';
