# Production Deployment Guide - Drug Pricing BI Tables

## Overview
This deployment fixes the bi_hcpcs_drug_pricing table to maintain only the **latest quarter** of data instead of accumulating all historical quarters.

## Files to Deploy (in order)

### 1. `sp_process_single_quarter.sql`
**Purpose**: Core stored procedure that processes one quarter at a time
**Changes**:
- Added cleanup logic (lines 319-336) to delete old quarters and keep only the latest
- Fixed date parsing to handle dot separator in month_year field (e.g., "July.2024")

**Deploy**: Run this file to update the stored procedure

### 2. `sp_refresh_bi_tables_v4.sql`
**Purpose**: Master procedure that orchestrates the quarter-by-quarter processing
**Status**: No changes - already correct
**Deploy**: Verify this procedure exists (should already be deployed)

### 3. `rebuild_pricing_table.sql`
**Purpose**: ONE-TIME script to fix the current corrupted data
**Deploy**: Run this ONCE after deploying the stored procedures above

This will:
- Truncate bi_hcpcs_drug_pricing (remove bad data)
- Call sp_refresh_bi_tables_v3() to rebuild from scratch
- Result: Table will have only Q4 2024 data (~3,300 rows)

### 4. `cleanup_log_table.sql`
**Purpose**: Utility to clean up the bi_refresh_log table
**Status**: Optional - use as needed

---

## Expected Results After Deployment

### Before Fix:
- bi_hcpcs_drug_pricing: **87,517 rows** (41 quarters from 2015-2024)
- bi_historical_pricing: **29,249 rows** (all historical quarters) ✓ Correct

### After Fix:
- bi_hcpcs_drug_pricing: **~3,300 rows** (Q4 2024 only - Oct/Nov/Dec)
- bi_historical_pricing: **~30,000 rows** (all historical quarters including Q4 2024) ✓ Correct

---

## Table Purposes (Clarified)

### `bi_hcpcs_drug_pricing`
- **Granularity**: Monthly (month_year field)
- **Scope**: **CURRENT QUARTER ONLY** (latest 3 months)
- **Purpose**: Current pricing data for active reporting
- **Primary Key**: (HCPCS_Code, month_year)
- **Updates**: Automatically cleaned on each quarter processing

### `bi_historical_pricing`
- **Granularity**: Quarterly (Quarter field)
- **Scope**: **ALL HISTORICAL QUARTERS**
- **Purpose**: Historical trend analysis
- **Primary Key**: (HCPCS_Code, Quarter)
- **Updates**: Accumulates all quarters (never deletes old data)

---

## Deployment Steps

```sql
-- Step 1: Deploy the updated stored procedure
SOURCE sp_process_single_quarter.sql;

-- Step 2: Verify it was created
SHOW PROCEDURE STATUS WHERE Name = 'sp_process_single_quarter';

-- Step 3: Rebuild the table (ONE TIME ONLY)
SOURCE rebuild_pricing_table.sql;

-- Step 4: Verify the results
SELECT
    COUNT(*) as total_rows,
    COUNT(DISTINCT HCPCS_Code) as unique_drugs,
    COUNT(DISTINCT month_year) as months,
    MIN(month_year) as earliest,
    MAX(month_year) as latest
FROM bi_hcpcs_drug_pricing;
-- Expected: ~3300 rows, ~1115 drugs, 3 months (Oct/Nov/Dec 2024)
```

---

## Future Behavior

Going forward, when `sp_refresh_bi_tables_v3()` runs:
1. It processes all quarters sequentially
2. For each quarter, it adds data to bi_hcpcs_drug_pricing
3. The cleanup logic **automatically deletes old quarters** and keeps only the latest
4. bi_historical_pricing continues to accumulate all quarters

**Result**: bi_hcpcs_drug_pricing will always have only the most recent quarter's data.

---

## Rollback Plan

If issues occur:
```sql
-- Stop any running procedures
KILL QUERY <process_id>;

-- Restore from backup or:
-- Re-run rebuild_pricing_table.sql to rebuild from source data
```

---

## Files NOT for Production (moved to old_scripts/)
- check_month_year_formats.sql (diagnostic)
- check_quarter_distribution.sql (diagnostic)
- check_source_data.sql (diagnostic)
- diagnostic_row_count_analysis.sql (diagnostic)
- verify_cleanup_result.sql (diagnostic)
- simple_delete.sql (one-time cleanup)
- EXECUTE_cleanup_now.sql (one-time cleanup)
- cleanup_drug_pricing_table.sql (diagnostic/cleanup)

---

## Questions?
Contact: [Your team contact info]
Date: November 24, 2024
