
DECLARE @file_hash VARCHAR(64) =
'791be3df3f97305ddff98879b2d9778bafebc80b8e52baf402a8c45983e19924';

DECLARE @failed_run UNIQUEIDENTIFIER =
'c0e9161f-9de9-40d1-a3b4-642d6630dbca';

SELECT COUNT(*) AS Raw_Rows
FROM dbo.rcni_raw
WHERE file_hash = @file_hash;

SELECT COUNT(*) AS Stage_Rows
FROM dbo.rcni_stage
WHERE load_run_id = @failed_run
  AND file_hash = @file_hash;
