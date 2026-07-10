
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
