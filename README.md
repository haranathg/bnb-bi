# BI Tables Quarterly Processing - V4

## Current Active Files

### 1. Main Procedures
- **[sp_process_single_quarter.sql](sp_process_single_quarter.sql)** - Processes one quarter at a time (proven 35-second execution)
- **[sp_refresh_bi_tables_v4.sql](sp_refresh_bi_tables_v4.sql)** - Main loop controller with deadlock handling

### 2. Documentation
- **[PHPMYADMIN_INSTRUCTIONS.md](PHPMYADMIN_INSTRUCTIONS.md)** - Step-by-step setup guide for phpMyAdmin
- **[README.md](README.md)** - This file

### 3. Other Files
- **[bi_historical_pricing_mapping.md](bi_historical_pricing_mapping.md)** - Data mapping documentation
- **[ToDo-migrate to prod.md](ToDo-migrate to prod.md)** - Production migration notes
- **[backup_old_versions/](backup_old_versions/)** - Old versions and unused files

---

## Quick Start

### Setup (One-time)

**In phpMyAdmin** (https://nwpro5.fcomet.com:2083/cpsess5066824156/3rdparty/phpMyAdmin/):

1. **Create sp_process_single_quarter**:
   - Copy entire contents of `sp_process_single_quarter.sql`
   - Paste in SQL tab → Execute

2. **Create sp_refresh_bi_tables_v4**:
   - Copy entire contents of `sp_refresh_bi_tables_v4.sql`
   - Paste in SQL tab → Execute

### Run

```sql
CALL sp_refresh_bi_tables_v3();
```

**Note**: Despite the procedure name being v4, it's called as v3 for backwards compatibility.

---

## What It Does

### Processing Strategy
- Processes **41 quarters** (not 120+ months!)
- Each quarter: 35 seconds to 2 minutes
- Total runtime: ~25-80 minutes
- Uses UPSERT to prevent duplicates

### Quarterly Dates Processed
- 2015-01-01 (Q1 2015)
- 2015-04-01 (Q2 2015)
- 2015-07-01 (Q3 2015)
- 2015-10-01 (Q4 2015)
- 2016-01-01 (Q1 2016)
- ... (continues for all quarters)

### Output Tables
1. **bi_hcpcs_drug_pricing** - Monthly pricing data with median calculations
2. **bi_historical_pricing** - Quarterly summary data

---

## V4 Features (Latest)

✅ **Deadlock Handling**: Logs errors but continues processing
✅ **COMMIT After Each Quarter**: Releases table locks immediately
✅ **0.5 Second Delay**: Prevents lock contention between quarters
✅ **Clear Status Tracking**:
  - `IN_PROGRESS` - Currently processing
  - `COMPLETED_QUARTER` - Quarter finished successfully
  - `COMPLETED` - All quarters finished
  - `ERROR` - Non-fatal error occurred
✅ **Proper Median Calculations**: Uses ROW_NUMBER() window function

---

## Monitoring Progress

```sql
-- Check recent log entries
SELECT * FROM bi_refresh_log
ORDER BY started_at DESC
LIMIT 20;

-- Count quarters processed
SELECT COUNT(*) as quarters_done
FROM bi_refresh_log
WHERE status = 'COMPLETED_QUARTER';

-- Check for errors
SELECT * FROM bi_refresh_log
WHERE status IN ('ERROR', 'FAILED')
ORDER BY started_at DESC;
```

---

## Expected Log Output

```
STARTED          | Processing QUARTERLY data from 2015-01-01 to 2024-10-01 (Expected: ~41 quarters)
IN_PROGRESS      | Processing quarter 1 of ~41 (Q1-2015) - 2015-01-01
COMPLETED_QUARTER| ✓ Q1 of ~41 (Q1-2015) - Pricing: 4126, Historical: 520
IN_PROGRESS      | Processing quarter 2 of ~41 (Q2-2015) - 2015-04-01
COMPLETED_QUARTER| ✓ Q2 of ~41 (Q2-2015) - Pricing: 4170, Historical: 525
...
COMPLETED        | SUCCESS! All 41 quarters processed. Total pricing rows: 168000, Total historical rows: 21000 [Duration: 1800s]
```

---

## Troubleshooting

### Issue: Still seeing monthly dates (2015-02-01, 2015-03-01)
**Solution**: The v4 procedure wasn't recreated. Re-run step 2 of setup.

### Issue: Deadlock errors
**Solution**: V4 handles these automatically with COMMIT + delay. Check logs for ERROR status.

### Issue: Process seems stuck
**Solution**:
```sql
-- Check if still running
SHOW PROCESSLIST;

-- Check last log entry
SELECT * FROM bi_refresh_log ORDER BY started_at DESC LIMIT 1;
```

### Issue: Want to restart
**Solution**: Safe to re-run - UPSERT prevents duplicates:
```sql
CALL sp_refresh_bi_tables_v3();
```

---

## Verification After Completion

```sql
-- Check final status
SELECT * FROM bi_refresh_log
WHERE status = 'COMPLETED'
ORDER BY completed_at DESC
LIMIT 1;

-- Verify data
SELECT COUNT(DISTINCT Quarter) as total_quarters
FROM bi_historical_pricing;
-- Should return: ~41

SELECT COUNT(DISTINCT month_year) as total_months
FROM bi_hcpcs_drug_pricing;
-- Should return: ~120

-- Sample data
SELECT * FROM bi_hcpcs_drug_pricing
ORDER BY Updated_date DESC
LIMIT 10;

SELECT * FROM bi_historical_pricing
ORDER BY Quarter DESC
LIMIT 10;
```

---

## File History

- **V1**: Original full-history processor (failed - disk space)
- **V2**: Attempted optimization (still failed)
- **V3**: Quarter-by-quarter loop (worked but had deadlocks)
- **V4**: Current - V3 + deadlock handling + proper status tracking

All old versions moved to `backup_old_versions/` folder.

---

**Last Updated**: 2025-11-21
**Status**: Ready for Production
**Database**: buyandbi_cms_aug_30
**Expected Runtime**: 25-80 minutes for 41 quarters
