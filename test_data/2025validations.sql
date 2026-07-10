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
