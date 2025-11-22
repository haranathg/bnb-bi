-- =====================================================
-- Clean Up bi_refresh_log Table
-- Remove unused columns that are always NULL in V4
-- =====================================================

-- Check current structure
DESCRIBE bi_refresh_log;

-- Remove unused columns
ALTER TABLE bi_refresh_log
    DROP COLUMN IF EXISTS rows_consolidated,
    DROP COLUMN IF EXISTS rows_asp,
    DROP COLUMN IF EXISTS rows_wac,
    DROP COLUMN IF EXISTS rows_awp;

-- Verify new structure
DESCRIBE bi_refresh_log;

-- The table should now have only these columns:
-- - id (primary key)
-- - refresh_type
-- - status
-- - message (contains all the row counts as text)
-- - started_at
-- - completed_at

-- Sample the cleaned table
SELECT * FROM bi_refresh_log
ORDER BY started_at DESC
LIMIT 10;
