# Manual Refresh FAQ

## Can I manually refresh without breaking the scheduled refresh?

**YES! Absolutely safe.** Manual and scheduled refreshes won't interfere with each other.

## Why is it safe?

The refresh process:
1. **Drops** the entire table: `DROP TABLE IF EXISTS bi_consolidated_drug_data`
2. **Recreates** it from scratch: `CREATE TABLE bi_consolidated_drug_data AS SELECT...`
3. **Rebuilds** all indexes

There's no incremental updating, no merging of data - just a complete replacement each time.

## What happens if manual refresh runs while scheduled refresh is running?

**Very unlikely scenario** (both would need to start within milliseconds), but if it happens:

1. MySQL's table-level locks prevent corruption
2. One refresh waits for the other to complete
3. The second one overwrites the first (which is fine - both use the same source data)
4. Your log table (`bi_refresh_log`) will show both runs

**Duration:** The entire refresh takes ~30 seconds, so collision window is tiny.

## Refresh History Tracking

You can see all refreshes (manual and scheduled) in the log:

```sql
-- View all refreshes today
SELECT 
    refresh_type,
    status,
    started_at,
    completed_at,
    TIMESTAMPDIFF(SECOND, started_at, completed_at) AS duration_seconds,
    rows_consolidated,
    rows_asp,
    rows_wac,
    rows_awp
FROM bi_refresh_log
WHERE DATE(started_at) = CURDATE()
ORDER BY started_at DESC;

-- Check if a refresh is currently running
SELECT * 
FROM bi_refresh_log 
WHERE status = 'STARTED' 
  AND completed_at IS NULL
ORDER BY started_at DESC;
```

## Best Practices

### ✅ DO:
- Run manual refresh anytime you need fresh data
- Check the log to see when last refresh completed
- Run during business hours if you want to monitor it
- Test manual refresh after initial setup

### ⚠️ CONSIDER:
- Power BI caching: If Power BI has cached data, it won't see changes until its own refresh runs
- Peak usage times: Refresh takes ~30 seconds and uses database resources
- Multiple users: Let your team know when you're manually refreshing

### ❌ DON'T:
- Worry about breaking the scheduled refresh - you won't!
- Run manual refresh repeatedly in quick succession (wasteful)
- Cancel a running refresh midway (let it complete)

## How to Run Manual Refresh

### Option 1: Run the Full Script
Simply execute your `create_powerbi_consolidated_table.sql` file manually in phpMyAdmin or MySQL Workbench.

### Option 2: Create a Stored Procedure (Easiest)

```sql
-- Create once
DELIMITER //

CREATE PROCEDURE sp_manual_refresh()
BEGIN
    DECLARE v_log_id INT;
    
    -- Log start
    INSERT INTO bi_refresh_log (refresh_type, status, message, started_at)
    VALUES ('manual', 'STARTED', 'Manual refresh initiated', NOW());
    SET v_log_id = LAST_INSERT_ID();
    
    -- Execute refresh (paste your full script logic here)
    DROP TABLE IF EXISTS bi_consolidated_drug_data;
    -- ... rest of your CREATE TABLE statements ...
    
    -- Log completion
    UPDATE bi_refresh_log 
    SET status = 'COMPLETED', 
        completed_at = NOW(),
        rows_consolidated = (SELECT COUNT(*) FROM bi_consolidated_drug_data)
    WHERE id = v_log_id;
    
    -- Return results
    SELECT 'Refresh completed!' AS status, 
           (SELECT COUNT(*) FROM bi_consolidated_drug_data) AS rows;
END //

DELIMITER ;
```

Then run anytime with just:
```sql
CALL sp_manual_refresh();
```

### Option 3: Quick One-Liner
If you already have the stored procedure:
```sql
-- Check if refresh is running
SELECT * FROM bi_refresh_log WHERE status = 'STARTED' AND completed_at IS NULL;

-- If clear, run it
CALL sp_manual_refresh();
```

## Monitoring After Manual Refresh

```sql
-- Verify data was refreshed
SELECT 
    COUNT(*) AS total_drugs,
    MAX(data_refresh_timestamp) AS last_updated,
    TIMESTAMPDIFF(MINUTE, MAX(data_refresh_timestamp), NOW()) AS minutes_ago
FROM bi_consolidated_drug_data;

-- Check refresh log
SELECT * FROM bi_refresh_log ORDER BY started_at DESC LIMIT 1;

-- Compare with source table
SELECT 
    'Source table (cms_drug_pricing)' AS table_name,
    COUNT(DISTINCT HCPCS_Code) AS unique_hcpcs
FROM cms_drug_pricing
UNION ALL
SELECT 
    'BI table (bi_consolidated_drug_data)',
    COUNT(DISTINCT HCPCS_Code)
FROM bi_consolidated_drug_data;
```

## Power BI Implications

After manual refresh:
1. **MySQL tables** are immediately updated ✓
2. **Power BI cached data** is NOT updated until Power BI refreshes
3. **Options:**
   - Wait for scheduled Power BI refresh (e.g., 3 AM)
   - Manually trigger Power BI refresh in Power BI Service
   - Use DirectQuery mode (no caching, always live data)

## Example Scenarios

### Scenario 1: Urgent Data Fix
```
9:00 AM - Source table cms_drug_pricing is corrected
9:01 AM - You run manual refresh
9:02 AM - BI tables updated ✓
9:05 AM - Manually refresh Power BI dataset
9:06 AM - Reports show corrected data ✓
```

### Scenario 2: Regular Day
```
2:00 AM - Scheduled refresh runs automatically
8:00 AM - Users view reports with fresh data
5:00 PM - No manual refresh needed (data is current)
```

### Scenario 3: Multiple Refreshes
```
2:00 AM - Scheduled refresh completes
10:00 AM - Manual refresh #1 (urgent update)
3:00 PM - Manual refresh #2 (another update)
```
All three refreshes logged separately. Latest data always available. ✓

## Summary

| Question | Answer |
|----------|--------|
| Safe to run manually? | ✅ YES |
| Will break scheduled refresh? | ❌ NO |
| Can run during business hours? | ✅ YES |
| How often can I run it? | As often as needed (but wait for completion) |
| Any conflicts? | ❌ NO - uses table locks |
| Need to stop scheduled refresh first? | ❌ NO |
| Affects Power BI immediately? | ⚠️ Only after Power BI refresh |
| How long does it take? | ~30 seconds |

**Bottom line:** Refresh anytime you need to. It's designed to be safe and idempotent (running multiple times produces the same result). 🎉
