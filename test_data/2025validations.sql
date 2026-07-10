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
