# phpMyAdmin Setup Instructions for V4 Quarterly Loop (With Deadlock Handling)

## Database Connection Info
- **URL**: https://nwpro5.fcomet.com:2083/cpsess5066824156/3rdparty/phpMyAdmin/index.php?route=/database/sql&db=buyandbi_cms_aug_30
- **User**: preset
- **Password**: bnb@preset
- **Database**: buyandbi_cms_aug_30

---

## Quick Setup (2 Steps)

### Step 1: Create sp_process_single_quarter

1. Open file: `sp_process_single_quarter.sql` in a text editor
2. Copy the **ENTIRE** contents
3. Go to phpMyAdmin → Database `buyandbi_cms_aug_30` → SQL tab
4. Paste and click **Go**
5. You should see: "Query OK, 0 rows affected"

### Step 2: Create sp_refresh_bi_tables_v4 (Main Loop)

1. Open file: `sp_refresh_bi_tables_v4.sql` in a text editor
2. Copy the **ENTIRE** contents
3. Go to phpMyAdmin → SQL tab (same database)
4. Paste and click **Go**
5. You should see: "Query OK, 0 rows affected"

**OR** copy this SQL directly:

```sql
DELIMITER //

DROP PROCEDURE IF EXISTS sp_refresh_bi_tables_v3 //  -- Note: still called v3 for compatibility

CREATE PROCEDURE sp_refresh_bi_tables_v3()
BEGIN
    DECLARE v_start_time DATETIME;
    DECLARE v_current_date DATE;
    DECLARE v_min_date DATE;
    DECLARE v_max_date DATE;
    DECLARE v_quarter_count INT DEFAULT 0;
    DECLARE v_total_pricing_rows INT DEFAULT 0;
    DECLARE v_total_historical_rows INT DEFAULT 0;
    DECLARE v_error_message TEXT;
    DECLARE done INT DEFAULT 0;

    -- Cursor for unique QUARTERS only (first day of first month in each quarter)
    DECLARE date_cursor CURSOR FOR
        SELECT DISTINCT DATE(CONCAT(
            YEAR(STR_TO_DATE(CONCAT('01-', REPLACE(REPLACE(month_year, '.', '-'), 'Feburary', 'February')), '%d-%M-%Y')),
            '-',
            LPAD((QUARTER(STR_TO_DATE(CONCAT('01-', REPLACE(REPLACE(month_year, '.', '-'), 'Feburary', 'February')), '%d-%M-%Y')) - 1) * 3 + 1, 2, '0'),
            '-01'
        )) AS quarter_start_date
        FROM cms_drug_pricing
        WHERE HCPCS_Code IS NOT NULL
            AND month_year IS NOT NULL
            AND month_year != 'month_year'
            AND month_year LIKE '%.%'
            AND LENGTH(month_year) >= 8
        ORDER BY quarter_start_date ASC;

    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = 1;

    DECLARE exit handler FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 v_error_message = MESSAGE_TEXT;
        INSERT INTO bi_refresh_log (refresh_type, status, message, started_at, completed_at)
        VALUES ('manual', 'FAILED', CONCAT('Error: ', v_error_message), v_start_time, NOW());
        RESIGNAL;
    END;

    SET v_start_time = NOW();

    SELECT
        MIN(STR_TO_DATE(CONCAT('01-', REPLACE(REPLACE(month_year, '.', '-'), 'Feburary', 'February')), '%d-%M-%Y')),
        MAX(STR_TO_DATE(CONCAT('01-', REPLACE(REPLACE(month_year, '.', '-'), 'Feburary', 'February')), '%d-%M-%Y'))
    INTO v_min_date, v_max_date
    FROM cms_drug_pricing
    WHERE HCPCS_Code IS NOT NULL
        AND month_year IS NOT NULL
        AND month_year != 'month_year'
        AND month_year LIKE '%.%'
        AND LENGTH(month_year) >= 8;

    INSERT INTO bi_refresh_log (refresh_type, status, message, started_at)
    VALUES ('manual', 'STARTED', CONCAT('Processing all QUARTERLY data from ',
        DATE_FORMAT(v_min_date, '%Y-%m-%d'), ' to ', DATE_FORMAT(v_max_date, '%Y-%m-%d'),
        ' (Expected: ~41 quarters)'), v_start_time);

    OPEN date_cursor;

    read_loop: LOOP
        FETCH date_cursor INTO v_current_date;
        IF done THEN LEAVE read_loop; END IF;

        SET v_quarter_count = v_quarter_count + 1;

        INSERT INTO bi_refresh_log (refresh_type, status, message, started_at)
        VALUES ('manual', 'IN_PROGRESS', CONCAT('Processing quarter ', v_quarter_count, ' of ~41',
            ' (Q', QUARTER(v_current_date), '-', YEAR(v_current_date),
            ') - Date: ', DATE_FORMAT(v_current_date, '%Y-%m-%d')), NOW());

        CALL sp_process_single_quarter(v_current_date, @rows_pricing, @rows_historical);

        SET v_total_pricing_rows = v_total_pricing_rows + @rows_pricing;
        SET v_total_historical_rows = v_total_historical_rows + @rows_historical;

        INSERT INTO bi_refresh_log (refresh_type, status, message, started_at, completed_at)
        VALUES ('manual', 'IN_PROGRESS', CONCAT('Completed Q', v_quarter_count, ' of ~41',
            ' (Q', QUARTER(v_current_date), '-', YEAR(v_current_date),
            ') - Pricing: ', @rows_pricing, ', Historical: ', @rows_historical), v_start_time, NOW());
    END LOOP;

    CLOSE date_cursor;

    INSERT INTO bi_refresh_log (refresh_type, status, message, started_at, completed_at)
    VALUES ('manual', 'COMPLETED', CONCAT('SUCCESS! All ', v_quarter_count, ' quarters processed. ',
        'Pricing rows: ', v_total_pricing_rows, ', Historical rows: ', v_total_historical_rows,
        ' [', TIMESTAMPDIFF(SECOND, v_start_time, NOW()), 's]'), v_start_time, NOW());

    SELECT
        'SUCCESS' AS status,
        v_quarter_count AS quarters_processed,
        v_total_pricing_rows AS total_pricing_rows,
        v_total_historical_rows AS total_historical_rows,
        CONCAT(TIMESTAMPDIFF(SECOND, v_start_time, NOW()), ' seconds') AS duration;
END //

DELIMITER ;
```

---

## Step 3: Verify Setup

Run this query to confirm both procedures exist:

```sql
SELECT ROUTINE_NAME, CREATED
FROM INFORMATION_SCHEMA.ROUTINES
WHERE ROUTINE_SCHEMA = 'buyandbi_cms_aug_30'
    AND ROUTINE_NAME IN ('sp_process_single_quarter', 'sp_refresh_bi_tables_v3');
```

You should see both procedures listed.

---

## Step 4: Run the Procedure

```sql
CALL sp_refresh_bi_tables_v3();
```

**Expected behavior:**
- Processes **41 quarters** (not 120+ months!)
- Each quarter takes 35 seconds to 2 minutes
- Total runtime: ~25-80 minutes
- Log entries show: "Processing quarter 1 of ~41 (Q1-2015)", "Processing quarter 2 of ~41 (Q2-2015)", etc.

---

## Monitoring Progress

While it's running, open another SQL tab and run:

```sql
SELECT * FROM bi_refresh_log
ORDER BY started_at DESC
LIMIT 10;
```

You should see entries like:
- "Processing quarter 1 of ~41 (Q1-2015)"
- "Completed Q1 of ~41 (Q1-2015) - Pricing: 4126, Historical: 520"
- "Processing quarter 2 of ~41 (Q2-2015)"
- etc.

---

## Troubleshooting

### If you see month-by-month processing
If log shows "Processing quarter 3 - Date: 2015-03-01" (March instead of April):
- The procedure wasn't updated correctly
- Re-run Step 2 above

### Expected quarterly dates
You should see these dates being processed:
- 2015-01-01 (Q1)
- 2015-04-01 (Q2)
- 2015-07-01 (Q3)
- 2015-10-01 (Q4)
- 2016-01-01 (Q1)
- etc.

**NOT** these:
- 2015-01-01, 2015-02-01, 2015-03-01, 2015-04-01... (every month)

---

## After Completion

Check results:

```sql
-- How many quarters processed?
SELECT COUNT(DISTINCT Quarter) as total_quarters
FROM bi_historical_pricing;

-- How many months processed?
SELECT COUNT(DISTINCT month_year) as total_months
FROM bi_hcpcs_drug_pricing;

-- Final log entry
SELECT * FROM bi_refresh_log
WHERE status = 'COMPLETED'
ORDER BY completed_at DESC
LIMIT 1;
```

---

## Files Reference

- **sp_process_single_quarter.sql** - Single quarter processor (proven 35-second execution)
- **sp_create_bi_tables_v3_loop.sql** - Loop controller (this is what Step 2 creates)
- **PHPMYADMIN_INSTRUCTIONS.md** - This file

---

**Last Updated**: 2025-11-21
**Expected Quarters**: 41
**Expected Runtime**: 25-80 minutes total
