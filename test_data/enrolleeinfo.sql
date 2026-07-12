DECLARE @folder_year INT = 2026;

SELECT
    issuer,
    COUNT(DISTINCT CASE
        WHEN enrolleeStatus = 'CONFIRM' AND member_id IS NOT NULL THEN member_id
    END) AS enrollee_count_confirm,
    COUNT(DISTINCT CASE
        WHEN enrolleeStatus = 'CANCEL' AND member_id IS NOT NULL THEN member_id
    END) AS enrollee_count_cancel,
    COUNT(DISTINCT CASE
        WHEN enrolleeStatus = 'TERM' AND member_id IS NOT NULL THEN member_id
    END) AS enrollee_count_term,
    COUNT(*) AS total_raw_rows
FROM dbo.inbound_automation
WHERE folder_year = @folder_year
GROUP BY issuer
ORDER BY issuer;

========================
