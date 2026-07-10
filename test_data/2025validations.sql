1. Total records and unique files by folder year

Description: Shows the total raw rows and unique loaded files for each physical folder year.

SELECT
    folder_year,
    COUNT(*) AS total_rows,
    COUNT(DISTINCT file_hash) AS total_files
FROM dbo.inbound_automation
GROUP BY folder_year
ORDER BY folder_year;
2. Overall database totals

Description: Shows the complete row, file, issuer, policy, and member totals currently stored in the raw table.

SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT file_hash) AS total_files,
    COUNT(DISTINCT issuer) AS total_issuers,
    COUNT(DISTINCT policy_id) AS distinct_policies,
    COUNT(DISTINCT member_id) AS distinct_members
FROM dbo.inbound_automation;
3. Total rows and files for 2025

Description: Returns the complete raw row and file totals loaded from the 2025 folder partition.

SELECT
    COUNT(*) AS total_2025_rows,
    COUNT(DISTINCT file_hash) AS total_2025_files
FROM dbo.inbound_automation
WHERE folder_year = 2025;
4. Total rows and files for 2026

Description: Returns the complete raw row and file totals loaded from the 2026 folder partition.

SELECT
    COUNT(*) AS total_2026_rows,
    COUNT(DISTINCT file_hash) AS total_2026_files
FROM dbo.inbound_automation
WHERE folder_year = 2026;
5. Issuer-level raw inventory

Description: Summarizes raw rows, files, policies, and members for every issuer.

SELECT
    issuer,
    COUNT(*) AS raw_rows,
    COUNT(DISTINCT file_hash) AS files,
    COUNT(DISTINCT policy_id) AS distinct_policies,
    COUNT(DISTINCT member_id) AS distinct_members
FROM dbo.inbound_automation
GROUP BY issuer
ORDER BY raw_rows DESC;
6. Issuer totals by year

Description: Compares each issuer’s file and row volumes between 2025 and 2026.

SELECT
    issuer,
    folder_year,
    COUNT(*) AS raw_rows,
    COUNT(DISTINCT file_hash) AS files,
    COUNT(DISTINCT policy_id) AS distinct_policies,
    COUNT(DISTINCT member_id) AS distinct_members
FROM dbo.inbound_automation
GROUP BY
    issuer,
    folder_year
ORDER BY
    issuer,
    folder_year;
7. Monthly row and file distribution

Description: Displays total files and raw records for every loaded year and month.

SELECT
    folder_year,
    folder_month,
    COUNT(DISTINCT file_hash) AS files,
    COUNT(*) AS rows
FROM dbo.inbound_automation
GROUP BY
    folder_year,
    folder_month
ORDER BY
    folder_year,
    folder_month;
8. Issuer-by-month inventory

Description: Shows monthly raw row and file totals separately for each issuer.

SELECT
    issuer,
    folder_year,
    folder_month,
    COUNT(DISTINCT file_hash) AS files,
    COUNT(*) AS rows
FROM dbo.inbound_automation
GROUP BY
    issuer,
    folder_year,
    folder_month
ORDER BY
    issuer,
    folder_year,
    folder_month;
9. Status distribution

Description: Shows the total number of raw rows for each derived enrollee status.

SELECT
    enrolleeStatus,
    COUNT(*) AS rows
FROM dbo.inbound_automation
GROUP BY enrolleeStatus
ORDER BY rows DESC;
10. Status distribution by year

Description: Compares CONFIRM, CANCEL, TERM, and UNMAPPED row volumes by folder year.

SELECT
    folder_year,
    enrolleeStatus,
    COUNT(*) AS rows
FROM dbo.inbound_automation
GROUP BY
    folder_year,
    enrolleeStatus
ORDER BY
    folder_year,
    enrolleeStatus;
11. Status distribution by issuer

Description: Identifies how enrollee statuses are distributed across issuers.

SELECT
    issuer,
    enrolleeStatus,
    COUNT(*) AS rows
FROM dbo.inbound_automation
GROUP BY
    issuer,
    enrolleeStatus
ORDER BY
    issuer,
    enrolleeStatus;
12. Insurance-type distribution

Description: Shows the total Health and Dental records in the raw ingestion table.

SELECT
    insurance_type,
    COUNT(*) AS rows
FROM dbo.inbound_automation
GROUP BY insurance_type
ORDER BY rows DESC;
13. Insurance type by issuer and year

Description: Shows Health and Dental record volumes by issuer and folder year.

SELECT
    issuer,
    folder_year,
    insurance_type,
    COUNT(*) AS rows
FROM dbo.inbound_automation
GROUP BY
    issuer,
    folder_year,
    insurance_type
ORDER BY
    issuer,
    folder_year,
    insurance_type;
14. Files whose filename year differs from folder year

Description: Identifies cross-year files where the filename timestamp does not match the physical folder partition.

SELECT
    folder_year,
    filename_file_year,
    COUNT(DISTINCT file_hash) AS file_count,
    COUNT(*) AS row_count
FROM dbo.inbound_automation
WHERE filename_file_year IS NOT NULL
  AND folder_year <> filename_file_year
GROUP BY
    folder_year,
    filename_file_year
ORDER BY
    folder_year,
    filename_file_year;
15. 2025-dated files stored under the 2026 folder

Description: Confirms that files with 2025 filename timestamps stored under the 2026 partition were loaded.

SELECT
    COUNT(DISTINCT file_hash) AS files,
    COUNT(*) AS rows
FROM dbo.inbound_automation
WHERE folder_year = 2026
  AND filename_file_year = 2025;
16. Detailed list of cross-year 2026-folder files

Description: Lists every 2025-dated file loaded from the 2026 folder, including issuer, months, and row counts.

SELECT
    issuer,
    folder_year,
    folder_month,
    filename_file_year,
    filename_file_month,
    source_file,
    file_hash,
    COUNT(*) AS rows
FROM dbo.inbound_automation
WHERE folder_year = 2026
  AND filename_file_year = 2025
GROUP BY
    issuer,
    folder_year,
    folder_month,
    filename_file_year,
    filename_file_month,
    source_file,
    file_hash
ORDER BY rows DESC;
17. Folder year versus effective year

Description: Compares the physical folder year with the benefit effective year stored in each record.

SELECT
    folder_year,
    YEAR(benefit_effective_date) AS effective_year,
    COUNT(*) AS rows
FROM dbo.inbound_automation
WHERE benefit_effective_date IS NOT NULL
GROUP BY
    folder_year,
    YEAR(benefit_effective_date)
ORDER BY
    folder_year,
    effective_year;
18. Records effective in 2025 but stored under 2026

Description: Counts records with a 2025 benefit effective date that were loaded from the 2026 folder partition.

SELECT
    COUNT(*) AS rows,
    COUNT(DISTINCT file_hash) AS files
FROM dbo.inbound_automation
WHERE folder_year = 2026
  AND YEAR(benefit_effective_date) = 2025;
19. Records effective in 2026 but stored under 2025

Description: Counts records with a 2026 benefit effective date that were loaded from the 2025 folder partition.

SELECT
    COUNT(*) AS rows,
    COUNT(DISTINCT file_hash) AS files
FROM dbo.inbound_automation
WHERE folder_year = 2025
  AND YEAR(benefit_effective_date) = 2026;
20. Coverage-year source distribution

Description: Shows how the coverage year was assigned, including CLI, filename, folder, or benefit-date fallback.

SELECT
    coverage_year_source,
    COUNT(*) AS rows
FROM dbo.inbound_automation
GROUP BY coverage_year_source
ORDER BY rows DESC;
21. Coverage year versus folder year

Description: Identifies records where the derived coverage year differs from the physical folder year.

SELECT
    folder_year,
    coverage_year,
    coverage_year_source,
    COUNT(*) AS rows
FROM dbo.inbound_automation
WHERE coverage_year <> folder_year
GROUP BY
    folder_year,
    coverage_year,
    coverage_year_source
ORDER BY
    folder_year,
    coverage_year;
22. Top 25 largest source files

Description: Lists the largest XML files by number of raw records loaded.

SELECT TOP (25)
    issuer,
    folder_year,
    folder_month,
    source_file,
    file_hash,
    COUNT(*) AS rows
FROM dbo.inbound_automation
GROUP BY
    issuer,
    folder_year,
    folder_month,
    source_file,
    file_hash
ORDER BY rows DESC;
23. Small files with only one record

Description: Identifies XML files that generated exactly one raw record.

SELECT
    issuer,
    folder_year,
    folder_month,
    source_file,
    file_hash,
    COUNT(*) AS rows
FROM dbo.inbound_automation
GROUP BY
    issuer,
    folder_year,
    folder_month,
    source_file,
    file_hash
HAVING COUNT(*) = 1
ORDER BY
    issuer,
    folder_year,
    folder_month;
24. Duplicate file-hash check

Description: Verifies that no file hash appears more than once in the file-log table.

SELECT
    file_hash,
    COUNT(*) AS hash_count
FROM dbo.inbound_automation_file_log
GROUP BY file_hash
HAVING COUNT(*) > 1;

Expected result:

0 rows
25. Duplicate raw-record hash check

Description: Identifies identical parsed records that appear more than once in the raw table.

SELECT TOP (100)
    raw_record_hash,
    COUNT(*) AS occurrence_count
FROM dbo.inbound_automation
GROUP BY raw_record_hash
HAVING COUNT(*) > 1
ORDER BY occurrence_count DESC;

This does not automatically mean an error; repeated raw transactions may legitimately exist across files.

26. File-log status summary

Description: Shows how many files are loaded, failed, or recorded under another parse status.

SELECT
    parse_status,
    COUNT(*) AS files,
    SUM(row_count) AS rows
FROM dbo.inbound_automation_file_log
GROUP BY parse_status
ORDER BY parse_status;
27. Remaining failed files

Description: Lists every file still marked as failed, including its last error and run identifier.

SELECT
    issuer,
    folder_year,
    folder_month,
    source_file,
    file_hash,
    row_count,
    load_run_id,
    error_message
FROM dbo.inbound_automation_file_log
WHERE parse_status = 'failed'
ORDER BY
    folder_year,
    folder_month,
    issuer,
    source_file;

Expected result:

0 rows
28. Recent load-run history

Description: Shows the most recent automation runs with file, row, failure, and duplicate metrics.

SELECT TOP (20)
    load_run_id,
    run_mode,
    status,
    year_filter,
    issuer_filter,
    month_filter,
    started_at,
    completed_at,
    files_discovered,
    files_loaded,
    files_skipped_duplicate,
    files_failed,
    rows_parsed,
    rows_inserted,
    total_warning_count
FROM dbo.inbound_automation_run_log
ORDER BY started_at DESC;
29. Run-level reconciliation

Description: Checks whether loaded, skipped, and failed files reconcile to discovered files for every run.

SELECT
    load_run_id,
    files_discovered,
    files_loaded,
    files_skipped_duplicate,
    files_failed,
    files_loaded
        + files_skipped_duplicate
        + files_failed AS accounted_files,
    files_discovered
        - (
            files_loaded
            + files_skipped_duplicate
            + files_failed
          ) AS file_difference,
    rows_parsed,
    rows_inserted,
    rows_parsed - rows_inserted AS row_difference
FROM dbo.inbound_automation_run_log
ORDER BY started_at DESC;

Expected:

file_difference = 0
row_difference  = 0
30. Main table versus file-log row reconciliation

Description: Compares actual raw-table rows with the file-log row totals for every loaded file hash.

WITH main_counts AS (
    SELECT
        file_hash,
        COUNT(*) AS actual_rows
    FROM dbo.inbound_automation
    GROUP BY file_hash
),
log_counts AS (
    SELECT
        file_hash,
        source_file,
        issuer,
        folder_year,
        folder_month,
        row_count AS logged_rows
    FROM dbo.inbound_automation_file_log
    WHERE parse_status = 'loaded'
)
SELECT
    l.issuer,
    l.folder_year,
    l.folder_month,
    l.source_file,
    l.file_hash,
    l.logged_rows,
    COALESCE(m.actual_rows, 0) AS actual_rows,
    COALESCE(m.actual_rows, 0) - l.logged_rows AS row_difference
FROM log_counts l
LEFT JOIN main_counts m
    ON l.file_hash = m.file_hash
WHERE COALESCE(m.actual_rows, 0) <> l.logged_rows
ORDER BY
    ABS(COALESCE(m.actual_rows, 0) - l.logged_rows) DESC;

Expected result:

0 rows
31. Warning-row summary

Description: Shows the issuer, year, and month distribution of rows carrying parser or filename warnings.

SELECT
    issuer,
    folder_year,
    folder_month,
    COUNT(DISTINCT file_hash) AS warning_files,
    COUNT(*) AS warning_rows,
    SUM(warning_count) AS total_warning_count
FROM dbo.inbound_automation
WHERE warning_count > 0
GROUP BY
    issuer,
    folder_year,
    folder_month
ORDER BY total_warning_count DESC;
32. Warning-file detail

Description: Lists every file that produced warnings and shows the number of affected rows.

SELECT
    issuer,
    folder_year,
    folder_month,
    source_file,
    file_hash,
    COUNT(*) AS rows,
    SUM(warning_count) AS warning_count
FROM dbo.inbound_automation
WHERE warning_count > 0
GROUP BY
    issuer,
    folder_year,
    folder_month,
    source_file,
    file_hash
ORDER BY warning_count DESC;
33. NULL member-ID validation

Description: Checks whether any loaded raw records are missing a member identifier.

SELECT
    issuer,
    folder_year,
    COUNT(*) AS null_member_rows
FROM dbo.inbound_automation
WHERE member_id IS NULL
GROUP BY
    issuer,
    folder_year
ORDER BY null_member_rows DESC;

Expected result:

0 rows
34. NULL policy-ID validation

Description: Shows which issuers contain records without an Exchange-assigned policy identifier.

SELECT
    issuer,
    folder_year,
    COUNT(*) AS null_policy_rows
FROM dbo.inbound_automation
WHERE policy_id IS NULL
GROUP BY
    issuer,
    folder_year
ORDER BY null_policy_rows DESC;
35. Policy-ID fallback analysis

Description: Determines whether records missing policy_id still contain a health-coverage policy number.

SELECT
    issuer,
    folder_year,
    COUNT(*) AS null_policy_rows,
    SUM(
        CASE
            WHEN health_coverage_policy_no IS NOT NULL THEN 1
            ELSE 0
        END
    ) AS rows_with_health_policy_no,
    SUM(
        CASE
            WHEN health_coverage_policy_no IS NULL THEN 1
            ELSE 0
        END
    ) AS rows_without_any_policy_value
FROM dbo.inbound_automation
WHERE policy_id IS NULL
GROUP BY
    issuer,
    folder_year
ORDER BY null_policy_rows DESC;
36. UNMAPPED status investigation

Description: Shows the raw event, action, and maintenance-code combinations responsible for UNMAPPED statuses.

SELECT
    issuer,
    folder_year,
    folder_month,
    enrollee_event_type_code,
    enrollee_event_reason_code,
    action_code,
    action_code_description,
    maintenance_type_code,
    additional_maint_reason_code,
    COUNT(*) AS rows
FROM dbo.inbound_automation
WHERE enrolleeStatus = 'UNMAPPED'
GROUP BY
    issuer,
    folder_year,
    folder_month,
    enrollee_event_type_code,
    enrollee_event_reason_code,
    action_code,
    action_code_description,
    maintenance_type_code,
    additional_maint_reason_code
ORDER BY rows DESC;
37. Missing-month detection by issuer

Description: Shows which year-month combinations are absent for each issuer.

WITH months AS (
    SELECT 1 AS month_number
    UNION ALL SELECT 2
    UNION ALL SELECT 3
    UNION ALL SELECT 4
    UNION ALL SELECT 5
    UNION ALL SELECT 6
    UNION ALL SELECT 7
    UNION ALL SELECT 8
    UNION ALL SELECT 9
    UNION ALL SELECT 10
    UNION ALL SELECT 11
    UNION ALL SELECT 12
),
issuers_years AS (
    SELECT DISTINCT
        issuer,
        folder_year
    FROM dbo.inbound_automation
)
SELECT
    iy.issuer,
    iy.folder_year,
    m.month_number AS missing_month
FROM issuers_years iy
CROSS JOIN months m
LEFT JOIN dbo.inbound_automation ia
    ON ia.issuer = iy.issuer
   AND ia.folder_year = iy.folder_year
   AND ia.folder_month = m.month_number
WHERE ia.issuer IS NULL
ORDER BY
    iy.issuer,
    iy.folder_year,
    m.month_number;

For partial-year 2026 data, later months may be expected to be absent.

38. Files with the same filename but different hashes

Description: Identifies filenames appearing in multiple physical locations or with different file contents.

SELECT
    source_file,
    COUNT(DISTINCT file_hash) AS distinct_hashes,
    COUNT(DISTINCT source_file_path) AS distinct_paths,
    COUNT(*) AS rows
FROM dbo.inbound_automation
GROUP BY source_file
HAVING COUNT(DISTINCT file_hash) > 1
ORDER BY distinct_hashes DESC;
39. Detailed same-filename/different-hash records

Description: Shows the issuer, folder, path, and hash details for filenames representing different physical files.

SELECT DISTINCT
    source_file,
    issuer,
    folder_year,
    folder_month,
    source_file_path,
    file_hash
FROM dbo.inbound_automation
WHERE source_file IN (
    SELECT source_file
    FROM dbo.inbound_automation
    GROUP BY source_file
    HAVING COUNT(DISTINCT file_hash) > 1
)
ORDER BY
    source_file,
    folder_year,
    folder_month,
    file_hash;
40. Final ingestion health check

Description: Provides a compact final validation summary covering raw rows, files, failures, NULL members, warnings, and duplicate hashes.

SELECT
    (SELECT COUNT(*)
     FROM dbo.inbound_automation) AS total_rows,

    (SELECT COUNT(DISTINCT file_hash)
     FROM dbo.inbound_automation) AS total_loaded_files,

    (SELECT COUNT(*)
     FROM dbo.inbound_automation_file_log
     WHERE parse_status = 'failed') AS failed_files,

    (SELECT COUNT(*)
     FROM dbo.inbound_automation
     WHERE member_id IS NULL) AS null_member_rows,

    (SELECT COUNT(*)
     FROM dbo.inbound_automation
     WHERE warning_count > 0) AS warning_rows,

    (
        SELECT COUNT(*)
        FROM (
            SELECT file_hash
            FROM dbo.inbound_automation_file_log
            GROUP BY file_hash
            HAVING COUNT(*) > 1
        ) duplicate_hashes
    ) AS duplicate_file_hashes;


=========================
SELECT
    COUNT(*) AS Total2026Rows,
    SUM(CASE WHEN filename_file_year = 2025 THEN 1 ELSE 0 END) AS RowsFrom2025Files,
    SUM(CASE WHEN filename_file_year = 2026 THEN 1 ELSE 0 END) AS RowsFrom2026Files,
    SUM(CASE WHEN filename_file_year IS NULL THEN 1 ELSE 0 END) AS UnknownYear
FROM dbo.inbound_automation
WHERE folder_year = 2026;

====================

SELECT
    folder_year,
    filename_file_year,
    COUNT(DISTINCT file_hash) AS file_count,
    COUNT(*) AS row_count
FROM dbo.inbound_automation
WHERE folder_year <> filename_file_year
GROUP BY
    folder_year,
    filename_file_year
ORDER BY
    folder_year,
    filename_file_year;


SELECT
    COUNT(DISTINCT file_hash) AS Files,
    COUNT(*) AS Rows
FROM dbo.inbound_automation
WHERE folder_year = 2026
  AND filename_file_year = 2025;


SELECT TOP (100)
    issuer,
    folder_year,
    folder_month,
    filename_file_year,
    filename_file_month,
    source_file,
    COUNT(*) AS Rows
FROM dbo.inbound_automation
WHERE folder_year = 2026
  AND filename_file_year = 2025
GROUP BY
    issuer,
    folder_year,
    folder_month,
    filename_file_year,
    filename_file_month,
    source_file
ORDER BY Rows DESC;

=============================

python run_xml_structural_audit.py --source-root "C:\Users\SelmaKazanci\Downloads\project\gaaccess-develop8\834_issuer_etl\source_data"


SELECT
    COUNT(*) AS Total_2026_Rows,
    COUNT(DISTINCT file_hash) AS Total_2026_Files
FROM dbo.inbound_automation
WHERE folder_year = 2026;

SELECT
    source_file,
    COUNT(*) AS Rows_Loaded
FROM dbo.inbound_automation
WHERE source_file IN (
    'from_68806_GA_834_INDV_2026-02-08T05344500.P.xml',
    'from_70893_GA_834_INDV_20260305204226.xml'
)
GROUP BY source_file
ORDER BY source_file;


SELECT
    source_file,
    parse_status,
    row_count,
    error_message,
    load_run_id
FROM dbo.inbound_automation_file_log
WHERE source_file IN (
    'from_68806_GA_834_INDV_2026-02-08T05344500.P.xml',
    'from_70893_GA_834_INDV_20260305204226.xml'
)
ORDER BY source_file;


SELECT
    COUNT(*) AS Failed_File_Count
FROM dbo.inbound_automation_file_log
WHERE parse_status = 'failed';


SELECT
    file_hash,
    COUNT(*) AS Hash_Count
FROM dbo.inbound_automation_file_log
GROUP BY file_hash
HAVING COUNT(*) > 1;


SELECT
    file_hash,
    COUNT(*) AS Hash_Count
FROM dbo.inbound_automation_file_log
GROUP BY file_hash
HAVING COUNT(*) > 1;


SELECT TOP (10)
    load_run_id,
    status,
    files_discovered,
    files_loaded,
    files_skipped_duplicate,
    files_failed,
    rows_parsed,
    rows_inserted,
    started_at,
    completed_at
FROM dbo.inbound_automation_run_log
WHERE year_filter = '2026'
ORDER BY started_at DESC;


SELECT
    folder_year,
    COUNT(*) AS Total_Rows,
    COUNT(DISTINCT file_hash) AS Total_Files
FROM dbo.inbound_automation
WHERE folder_year IN (2025, 2026)
GROUP BY folder_year
ORDER BY folder_year;

SELECT
    COUNT(*) AS Total_All_Rows,
    COUNT(DISTINCT file_hash) AS Total_All_Files
FROM dbo.inbound_automation;




=============================     ===========
SELECT TOP 20
policy_id,
health_coverage_policy_no
FROM dbo.inbound_automation
WHERE issuer='45334';

SELECT TOP 100
source_file,
member_id,
policy_id,
raw_json
FROM dbo.inbound_automation
WHERE issuer='60224'
AND policy_id IS NULL;

SELECT
issuer,
COUNT(*) AS NullPolicy
FROM dbo.inbound_automation
WHERE policy_id IS NULL
GROUP BY issuer
ORDER BY NullPolicy DESC;


SELECT
issuer,
COUNT(*) AS NullMember
FROM dbo.inbound_automation
WHERE member_id IS NULL
GROUP BY issuer
ORDER BY NullMember DESC;


SELECT
file_hash,
COUNT(*)
FROM dbo.inbound_automation_file_log
GROUP BY file_hash
HAVING COUNT(*)>1;


===============

SELECT TOP 20
source_file,
COUNT(*) AS Rows
FROM dbo.inbound_automation
GROUP BY source_file
ORDER BY Rows DESC;

SELECT
issuer,
COUNT(*) Rows
FROM dbo.inbound_automation
GROUP BY issuer
ORDER BY Rows DESC;


SELECT
folder_year,
folder_month,
COUNT(*) Rows
FROM dbo.inbound_automation
GROUP BY
folder_year,
folder_month
ORDER BY
folder_year,
folder_month;



SELECT
enrolleeStatus,
COUNT(*) Rows
FROM dbo.inbound_automation
GROUP BY enrolleeStatus;


=====================
Sadece 2026 toplam row ve file count
SELECT
    COUNT(*) AS Total_2026_Rows,
    COUNT(DISTINCT source_file) AS Total_2026_Files
FROM dbo.inbound_automation
WHERE folder_year = 2026;



2026 issuer bazında

    
SELECT
    issuer,
    COUNT(*) AS RawRows,
    COUNT(DISTINCT source_file) AS Files,
    COUNT(DISTINCT policy_id) AS Policies,
    COUNT(DISTINCT member_id) AS Members
FROM dbo.inbound_automation
WHERE folder_year = 2026
GROUP BY issuer
ORDER BY issuer;


2026 issuer + month bazında


    
SELECT
    issuer,
    folder_month,
    COUNT(*) AS RawRows,
    COUNT(DISTINCT source_file) AS Files,
    COUNT(DISTINCT policy_id) AS Policies,
    COUNT(DISTINCT member_id) AS Members
FROM dbo.inbound_automation
WHERE folder_year = 2026
GROUP BY
    issuer,
    folder_month
ORDER BY
    issuer,
    folder_month;


2025 ve 2026 toplamlarını yan yana görmek için

    
SELECT
    folder_year,
    COUNT(*) AS RawRows,
    COUNT(DISTINCT source_file) AS Files,
    COUNT(DISTINCT policy_id) AS Policies,
    COUNT(DISTINCT member_id) AS Members
FROM dbo.inbound_automation
WHERE folder_year IN (2025, 2026)
GROUP BY folder_year
ORDER BY folder_year;


Tüm table toplamı

    
SELECT
    COUNT(*) AS Total_Rows,
    COUNT(DISTINCT source_file) AS Total_Files,
    COUNT(DISTINCT issuer) AS Total_Issuers,
    COUNT(DISTINCT policy_id) AS Total_Policies,
    COUNT(DISTINCT member_id) AS Total_Members
FROM dbo.inbound_automation;


En son 2026 load run’ını kontrol etmek için

    
SELECT TOP (5)
    load_run_id,
    run_mode,
    status,
    started_at,
    completed_at,
    year_filter,
    files_discovered,
    files_loaded,
    files_skipped_duplicate,
    files_failed,
    rows_parsed,
    rows_inserted,
    total_warning_count
FROM dbo.inbound_automation_run_log
WHERE year_filter = '2026'
ORDER BY started_at DESC;


=========================
SELECT COUNT(*) AS TotalRows
FROM dbo.inbound_automation;


SELECT
    SUM(row_count) AS LoggedRows
FROM dbo.inbound_automation_file_log
WHERE parse_status = 'loaded';



SELECT
    source_file,
    COUNT(*) AS RowsLoaded
FROM dbo.inbound_automation
WHERE issuer = '64357'
GROUP BY source_file
ORDER BY source_file;


============================


Ben olsam şu sırayla giderdim
Phase 1 — Duplicate Files ⭐⭐⭐⭐⭐ (ilk)

Bu 55 duplicate benim ilk bakacağım şey.

Çünkü bunlar hata olmayabilir.

Muhtemelen:

pilot run
aynı file tekrar yüklenmiş
aynı hash

Öğrenmek istediğimiz:

aynı issuer mı?
aynı month mı?
gerçekten aynı file mı?

Şu query:

SELECT
    issuer,
    folder_year,
    folder_month,
    COUNT(*) AS duplicate_files,
    SUM(row_count) AS duplicate_rows
FROM dbo.inbound_automation_file_log
WHERE parse_status='skipped_duplicate'
GROUP BY
    issuer,
    folder_year,
    folder_month
ORDER BY duplicate_rows DESC;
Phase 2 — Warnings ⭐⭐⭐⭐⭐

448 warning artık çok az.

Ben bunların tamamını görmek isterim.

Muhtemelen:

64357

dosyaları.

Şu query:

SELECT
    issuer,
    source_file,
    row_count,
    warning_count
FROM dbo.inbound_automation_file_log
WHERE warning_count>0
ORDER BY
    warning_count DESC;

Büyük ihtimalle 3 tane bozuk filename göreceğiz.

Phase 3 — Issuer Summary ⭐⭐⭐⭐⭐

Artık en güzel rapor geliyor.

SELECT

issuer,

COUNT(*) RawRows,

COUNT(DISTINCT source_file) Files,

COUNT(DISTINCT policy_id) Policies,

COUNT(DISTINCT member_id) Members

FROM dbo.inbound_automation

GROUP BY issuer

ORDER BY issuer;
ORDER BY duplicate_rows DESC;
