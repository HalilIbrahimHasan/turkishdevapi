python .\run_rcni.py --load-local-azure --issuer 70893 --year 2026 --month 01 --file-name to_70893_INDV_MONTHLYDISCREPANCY_2025_20260107070956.OUT.good.gz


DECLARE @file_hash VARCHAR(64) =
'791be3df3f97305ddff98879b2d9778bafebc80b8e52baf402a8c45983e19924';

SELECT COUNT(*) AS Raw_Rows
FROM dbo.rcni_raw
WHERE file_hash = @file_hash;

SELECT
    load_run_id,
    COUNT(*) AS Stage_Rows
FROM dbo.rcni_stage
WHERE file_hash = @file_hash
GROUP BY load_run_id
ORDER BY load_run_id;
