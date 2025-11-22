# Daily Automation Guide for BI Tables

## Overview
You need to refresh the BI tables daily to reflect changes in `cms_drug_pricing`. Here are several options, ranked by recommendation.

---

## Option 1: MySQL Event Scheduler (RECOMMENDED)

**Best for:** Automated, hands-off daily updates directly in MySQL

### Advantages:
- ✅ Runs automatically inside MySQL
- ✅ No external dependencies
- ✅ Guaranteed to run even if server restarts
- ✅ Easy to monitor and modify
- ✅ No additional infrastructure needed

### Implementation:

#### Step 1: Enable Event Scheduler (if not already enabled)

```sql
-- Check if event scheduler is enabled
SHOW VARIABLES LIKE 'event_scheduler';

-- Enable it (add to my.cnf for permanent)
SET GLOBAL event_scheduler = ON;
```

To make it permanent, add to your MySQL config file (my.cnf or my.ini):
```ini
[mysqld]
event_scheduler = ON
```

#### Step 2: Create the Event

```sql
-- Drop existing event if it exists
DROP EVENT IF EXISTS refresh_bi_tables_daily;

-- Create the event to run daily at 2 AM
DELIMITER //

CREATE EVENT refresh_bi_tables_daily
ON SCHEDULE EVERY 1 DAY
STARTS CURRENT_DATE + INTERVAL 1 DAY + INTERVAL 2 HOUR  -- Next day at 2 AM
DO
BEGIN
    -- Log start time
    INSERT INTO bi_refresh_log (refresh_type, status, message, started_at)
    VALUES ('daily_refresh', 'STARTED', 'Daily refresh initiated', NOW());
    
    SET @log_id = LAST_INSERT_ID();
    
    -- Drop and recreate bi_consolidated_drug_data
    DROP TABLE IF EXISTS bi_consolidated_drug_data;
    
    -- [PASTE THE ENTIRE CREATE TABLE STATEMENT HERE]
    -- (The full query from create_powerbi_consolidated_table.sql)
    
    -- Update log with success
    UPDATE bi_refresh_log 
    SET status = 'COMPLETED', 
        message = 'All BI tables refreshed successfully',
        completed_at = NOW()
    WHERE id = @log_id;
    
END //

DELIMITER ;
```

#### Step 3: Create Logging Table (Optional but Recommended)

```sql
CREATE TABLE IF NOT EXISTS bi_refresh_log (
    id INT AUTO_INCREMENT PRIMARY KEY,
    refresh_type VARCHAR(50),
    status VARCHAR(20),
    message TEXT,
    started_at DATETIME,
    completed_at DATETIME,
    rows_affected INT,
    INDEX idx_started_at (started_at)
);
```

#### Step 4: Monitor the Event

```sql
-- Check if event exists and is enabled
SHOW EVENTS WHERE Name = 'refresh_bi_tables_daily';

-- View refresh history
SELECT * FROM bi_refresh_log ORDER BY started_at DESC LIMIT 10;

-- Disable event temporarily
ALTER EVENT refresh_bi_tables_daily DISABLE;

-- Re-enable event
ALTER EVENT refresh_bi_tables_daily ENABLE;

-- Change schedule (e.g., to 3 AM)
ALTER EVENT refresh_bi_tables_daily
ON SCHEDULE EVERY 1 DAY
STARTS CURRENT_DATE + INTERVAL 1 DAY + INTERVAL 3 HOUR;
```

---

## Option 2: Stored Procedure + Cron Job

**Best for:** More control, can add complex logic and error handling

### Step 1: Create Stored Procedure

```sql
DELIMITER //

CREATE PROCEDURE refresh_bi_tables()
BEGIN
    DECLARE exit handler FOR SQLEXCEPTION
    BEGIN
        -- Rollback and log error
        ROLLBACK;
        INSERT INTO bi_refresh_log (refresh_type, status, message, started_at, completed_at)
        VALUES ('manual_refresh', 'FAILED', 'Error during refresh', NOW(), NOW());
    END;
    
    START TRANSACTION;
    
    -- Log start
    INSERT INTO bi_refresh_log (refresh_type, status, message, started_at)
    VALUES ('manual_refresh', 'STARTED', 'Refresh initiated', NOW());
    SET @log_id = LAST_INSERT_ID();
    
    -- Drop and recreate main table
    DROP TABLE IF EXISTS bi_consolidated_drug_data;
    -- [PASTE CREATE TABLE STATEMENT]
    
    -- Drop and recreate historical tables
    DROP TABLE IF EXISTS bi_historical_asp;
    -- [PASTE CREATE TABLE STATEMENT]
    
    DROP TABLE IF EXISTS bi_historical_wac;
    -- [PASTE CREATE TABLE STATEMENT]
    
    DROP TABLE IF EXISTS bi_historical_awp;
    -- [PASTE CREATE TABLE STATEMENT]
    
    -- Update log
    UPDATE bi_refresh_log 
    SET status = 'COMPLETED', 
        message = 'All BI tables refreshed successfully',
        completed_at = NOW(),
        rows_affected = (SELECT COUNT(*) FROM bi_consolidated_drug_data)
    WHERE id = @log_id;
    
    COMMIT;
END //

DELIMITER ;
```

### Step 2: Create Bash Script

```bash
#!/bin/bash
# File: /home/yourusername/refresh_bi_tables.sh

# Configuration
DB_HOST="localhost"
DB_NAME="buyandbi_cms_aug_30"
DB_USER="your_username"
DB_PASS="your_password"
LOG_FILE="/var/log/bi_refresh.log"

# Run the stored procedure
echo "[$(date)] Starting BI table refresh..." >> $LOG_FILE

mysql -h $DB_HOST -u $DB_USER -p$DB_PASS $DB_NAME -e "CALL refresh_bi_tables();" 2>&1 >> $LOG_FILE

if [ $? -eq 0 ]; then
    echo "[$(date)] BI table refresh completed successfully" >> $LOG_FILE
else
    echo "[$(date)] ERROR: BI table refresh failed" >> $LOG_FILE
    # Optional: Send email notification
    # mail -s "BI Refresh Failed" admin@example.com < $LOG_FILE
fi
```

### Step 3: Make Script Executable

```bash
chmod +x /home/yourusername/refresh_bi_tables.sh
```

### Step 4: Add to Crontab

```bash
# Edit crontab
crontab -e

# Add this line to run daily at 2 AM
0 2 * * * /home/yourusername/refresh_bi_tables.sh
```

---

## Option 3: Power BI Gateway Scheduled Refresh

**Best for:** If you're already using Power BI Gateway

### Configuration:
1. Set up Power BI Gateway connection to MySQL
2. In Power BI Service:
   - Go to Dataset Settings
   - Configure "Scheduled refresh"
   - Set frequency: Daily at 3 AM (after MySQL refresh at 2 AM)
3. Power BI will automatically pull fresh data from the BI tables

**Note:** This refreshes Power BI's cache, not the MySQL tables. You still need Option 1 or 2 to refresh the MySQL tables first.

---

## Option 4: Application-Level Refresh (Python Script)

**Best for:** Complex ETL logic, data validation, or integration with other systems

### Create Python Script

```python
#!/usr/bin/env python3
# File: refresh_bi_tables.py

import mysql.connector
from datetime import datetime
import sys

# Configuration
DB_CONFIG = {
    'host': 'localhost',
    'user': 'your_username',
    'password': 'your_password',
    'database': 'buyandbi_cms_aug_30'
}

def log_message(message):
    print(f"[{datetime.now()}] {message}")

def refresh_bi_tables():
    try:
        log_message("Connecting to database...")
        conn = mysql.connector.connect(**DB_CONFIG)
        cursor = conn.cursor()
        
        log_message("Starting BI table refresh...")
        
        # Read SQL file
        with open('/path/to/create_powerbi_consolidated_table.sql', 'r') as f:
            sql_script = f.read()
        
        # Execute each statement
        for statement in sql_script.split(';'):
            if statement.strip():
                cursor.execute(statement)
        
        conn.commit()
        
        # Get row count
        cursor.execute("SELECT COUNT(*) FROM bi_consolidated_drug_data")
        row_count = cursor.fetchone()[0]
        
        log_message(f"Refresh completed. {row_count} rows in bi_consolidated_drug_data")
        
        cursor.close()
        conn.close()
        return True
        
    except Exception as e:
        log_message(f"ERROR: {str(e)}")
        return False

if __name__ == "__main__":
    success = refresh_bi_tables()
    sys.exit(0 if success else 1)
```

### Add to Crontab

```bash
0 2 * * * /usr/bin/python3 /path/to/refresh_bi_tables.py >> /var/log/bi_refresh.log 2>&1
```

---

## Recommended Schedule

```
1:00 AM - Backup existing BI tables (optional)
2:00 AM - Run refresh script (MySQL Event or Cron)
2:30 AM - Verify data quality (optional validation)
3:00 AM - Power BI scheduled refresh (if using)
```

---

## Monitoring & Maintenance

### Check Event Status

```sql
-- View event details
SELECT * FROM information_schema.events 
WHERE event_schema = 'buyandbi_cms_aug_30';

-- Check last execution
SELECT * FROM bi_refresh_log ORDER BY started_at DESC LIMIT 5;

-- View table row counts
SELECT 
    'bi_consolidated_drug_data' AS table_name, 
    COUNT(*) AS rows,
    MAX(data_refresh_timestamp) AS last_refresh
FROM bi_consolidated_drug_data
UNION ALL
SELECT 'bi_historical_asp', COUNT(*), MAX(Date) FROM bi_historical_asp
UNION ALL
SELECT 'bi_historical_wac', COUNT(*), MAX(Date) FROM bi_historical_wac
UNION ALL
SELECT 'bi_historical_awp', COUNT(*), MAX(Date) FROM bi_historical_awp;
```

### Manual Refresh

```sql
-- If using Event Scheduler, trigger manually
CALL refresh_bi_tables();  -- If using stored procedure

-- OR run the full script manually
-- [paste entire SQL script]
```

### Email Notifications (Optional)

If you want email alerts on failures, you can:

1. **MySQL Event + Email (requires MySQL 5.7.8+):**
```sql
-- Install mail functionality (Linux)
-- Then use sys_exec or external script
```

2. **Bash Script with Mail:**
```bash
# In your bash script
if [ $? -ne 0 ]; then
    echo "BI refresh failed at $(date)" | mail -s "BI Refresh Alert" admin@example.com
fi
```

3. **Python Script with SMTP:**
```python
import smtplib
from email.mime.text import MIMEText

def send_alert(message):
    msg = MIMEText(message)
    msg['Subject'] = 'BI Refresh Alert'
    msg['From'] = 'alerts@yourdomain.com'
    msg['To'] = 'admin@yourdomain.com'
    
    s = smtplib.SMTP('smtp.gmail.com', 587)
    s.starttls()
    s.login('your_email', 'your_password')
    s.send_message(msg)
    s.quit()
```

---

## Troubleshooting

### Event Not Running

```sql
-- Check event scheduler status
SHOW VARIABLES LIKE 'event_scheduler';

-- View event errors
SHOW EVENTS;

-- Check MySQL error log
-- Location varies: /var/log/mysql/error.log or similar
```

### Long Running Queries

```sql
-- Check currently running queries
SHOW PROCESSLIST;

-- Kill long-running query if needed
KILL QUERY [process_id];
```

### Disk Space Issues

```bash
# Check disk usage
df -h

# Check MySQL data directory size
du -sh /var/lib/mysql/buyandbi_cms_aug_30/
```

---

## Performance Optimization

### For Large Tables (>1 million rows):

1. **Use TRUNCATE instead of DROP:**
```sql
TRUNCATE TABLE bi_consolidated_drug_data;
INSERT INTO bi_consolidated_drug_data SELECT ...;
```

2. **Add indexes after data load:**
```sql
-- Create table without indexes first
-- Load data
-- Then add indexes
ALTER TABLE bi_consolidated_drug_data ADD INDEX idx_hcpcs_code(HCPCS_Code);
```

3. **Consider incremental updates:**
```sql
-- Only update changed rows
DELETE FROM bi_consolidated_drug_data 
WHERE HCPCS_Code IN (SELECT DISTINCT HCPCS_Code FROM cms_drug_pricing WHERE updatedDate >= CURDATE());

INSERT INTO bi_consolidated_drug_data 
SELECT ... FROM cms_drug_pricing WHERE updatedDate >= CURDATE();
```

---

## My Recommendation

**Start with Option 1 (MySQL Event Scheduler)** because:
- ✅ Simplest to set up and maintain
- ✅ No external dependencies
- ✅ Built-in to MySQL
- ✅ Runs even if you're not logged in
- ✅ Easy to monitor and debug

Then add:
- Logging table for monitoring
- Email alerts for failures (optional)
- Power BI Gateway scheduled refresh after MySQL refresh

This gives you a robust, automated solution with minimal complexity!
