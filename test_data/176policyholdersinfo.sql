/* Subscriber-only policy holders:
   subscriber_id appears on rows, but never as member_id */

WITH base AS (
    SELECT *
    FROM dbo.inbound_automation
    -- optional filters:
    -- WHERE folder_year = 2026
),
members AS (
    SELECT DISTINCT member_id
    FROM base
    WHERE member_id IS NOT NULL
),
subscriber_only AS (
    SELECT DISTINCT b.subscriber_id
    FROM base b
    WHERE b.subscriber_id IS NOT NULL
      AND b.subscriber_id NOT IN (SELECT member_id FROM members)
),
rows_for_subscriber AS (
    SELECT
        b.subscriber_id,
        b.issuer,                              -- HIOS issuer id
        b.policy_id,
        b.health_coverage_policy_no,
        b.household_or_employee_case_id,
        b.issuer_subscriber_identifier,
        b.subscriber_flag,                       -- on dependent rows, usually N
        b.relationship,                          -- dependent relationship on that row
        b.member_id          AS dependent_member_id,
        b.exchg_assigned_enrollee_id AS dependent_enrollee_id,
        b.issuer_indiv_identifier AS dependent_issuer_indiv_id,
        b.member_first_name  AS dependent_first_name,
        b.member_last_name   AS dependent_last_name,
        b.folder_year,
        b.folder_month,
        b.source_file,
        b.file_hash,
        b.benefit_effective_date,
        b.benefit_end_date,
        b.enrolleeStatus,
        b.insurance_type,
        b.insurance_type_code
    FROM base b
    INNER JOIN subscriber_only s
        ON s.subscriber_id = b.subscriber_id
)
SELECT
    subscriber_id,
    COUNT(*) AS dependent_enrollee_rows,         -- how many raw rows reference this subscriber
    COUNT(DISTINCT issuer) AS issuer_count,
    STRING_AGG(DISTINCT issuer, ', ') WITHIN GROUP (ORDER BY issuer) AS hios_issuer_ids,
    COUNT(DISTINCT policy_id) AS distinct_policy_id,
    COUNT(DISTINCT health_coverage_policy_no) AS distinct_health_policy_no,
    STRING_AGG(DISTINCT policy_id, ', ') WITHIN GROUP (ORDER BY policy_id) AS policy_ids,
    STRING_AGG(DISTINCT health_coverage_policy_no, ', ') WITHIN GROUP (ORDER BY health_coverage_policy_no) AS health_policy_nos,
    STRING_AGG(DISTINCT household_or_employee_case_id, ', ') WITHIN GROUP (ORDER BY household_or_employee_case_id) AS household_case_ids,
    STRING_AGG(DISTINCT issuer_subscriber_identifier, ', ') WITHIN GROUP (ORDER BY issuer_subscriber_identifier) AS issuer_subscriber_identifiers,
    COUNT(DISTINCT dependent_member_id) AS distinct_dependents,
    STRING_AGG(DISTINCT dependent_member_id, ', ') WITHIN GROUP (ORDER BY dependent_member_id) AS dependent_member_ids,
    STRING_AGG(DISTINCT dependent_first_name + ' ' + dependent_last_name, '; ') AS dependent_names,
    MIN(folder_year) AS min_folder_year,
    MAX(folder_year) AS max_folder_year,
    MIN(benefit_effective_date) AS earliest_benefit_effective_date,
    MAX(benefit_end_date) AS latest_benefit_end_date,
    STRING_AGG(DISTINCT enrolleeStatus, ', ') WITHIN GROUP (ORDER BY enrolleeStatus) AS dependent_statuses,
    STRING_AGG(DISTINCT insurance_type, ', ') WITHIN GROUP (ORDER BY insurance_type) AS insurance_types
FROM rows_for_subscriber
GROUP BY subscriber_id
ORDER BY dependent_enrollee_rows DESC, subscriber_id;


===========

WITH base AS (
    SELECT *
    FROM dbo.inbound_automation
),
members AS (
    SELECT DISTINCT member_id
    FROM base
    WHERE member_id IS NOT NULL
),
subscriber_only AS (
    SELECT DISTINCT subscriber_id
    FROM base
    WHERE subscriber_id IS NOT NULL
      AND subscriber_id NOT IN (SELECT member_id FROM members)
)
SELECT
    b.subscriber_id,
    b.issuer AS hios_issuer_id,
    b.policy_id,
    b.health_coverage_policy_no,
    b.household_or_employee_case_id,
    b.issuer_subscriber_identifier,
    b.member_id AS dependent_member_id,
    b.exchg_assigned_enrollee_id AS dependent_enrollee_id,
    b.issuer_indiv_identifier AS dependent_issuer_indiv_id,
    b.member_first_name AS dependent_first_name,
    b.member_last_name AS dependent_last_name,
    b.relationship,
    b.subscriber_flag,
    b.folder_year,
    b.folder_month,
    b.source_file,
    b.benefit_effective_date,
    b.benefit_end_date,
    b.enrolleeStatus,
    b.insurance_type,
    b.maintenance_type_code,
    b.action_code,
    b.action_code_description
FROM dbo.inbound_automation b
INNER JOIN subscriber_only s
    ON s.subscriber_id = b.subscriber_id
ORDER BY b.subscriber_id, b.source_file, b.row_number_in_file;
