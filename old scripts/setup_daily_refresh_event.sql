-- =====================================================
-- Setup Daily Automated Refresh for BI Tables
-- Run this once to set up automatic daily updates
-- =====================================================

-- Step 1: Create logging table
CREATE TABLE IF NOT EXISTS bi_refresh_log (
    id INT AUTO_INCREMENT PRIMARY KEY,
    refresh_type VARCHAR(50),
    status VARCHAR(20),
    message TEXT,
    started_at DATETIME,
    completed_at DATETIME,
    rows_consolidated INT,
    rows_asp INT,
    rows_wac INT,
    rows_awp INT,
    INDEX idx_started_at (started_at),
    INDEX idx_status (status)
);

-- Step 2: Enable event scheduler (if not already enabled)
SET GLOBAL event_scheduler = ON;

-- Step 3: Drop existing event if it exists
DROP EVENT IF EXISTS refresh_bi_tables_daily;

-- Step 4: Create the daily refresh event
-- This will run every day at 2:00 AM server time
DELIMITER //

CREATE EVENT refresh_bi_tables_daily
ON SCHEDULE EVERY 1 DAY
STARTS (CURRENT_DATE + INTERVAL 1 DAY + INTERVAL 2 HOUR)
ON COMPLETION PRESERVE
ENABLE
COMMENT 'Refresh BI tables daily at 2 AM'
DO
BEGIN
    DECLARE v_rows_consolidated INT DEFAULT 0;
    DECLARE v_rows_asp INT DEFAULT 0;
    DECLARE v_rows_wac INT DEFAULT 0;
    DECLARE v_rows_awp INT DEFAULT 0;
    DECLARE v_log_id INT;
    
    DECLARE exit handler FOR SQLEXCEPTION
    BEGIN
        -- Log error
        UPDATE bi_refresh_log 
        SET status = 'FAILED', 
            message = 'Error during refresh - check MySQL error log',
            completed_at = NOW()
        WHERE id = v_log_id;
    END;
    
    -- Log start
    INSERT INTO bi_refresh_log (refresh_type, status, message, started_at)
    VALUES ('daily_auto', 'STARTED', 'Automated daily refresh started', NOW());
    
    SET v_log_id = LAST_INSERT_ID();
    
    -- Execute the full refresh script
    -- NOTE: You need to paste your complete SQL here from create_powerbi_consolidated_table.sql
    -- For now, we'll call a stored procedure (create it separately)
    
    CALL sp_refresh_bi_tables();
    
    -- Get row counts
    SELECT COUNT(*) INTO v_rows_consolidated FROM bi_consolidated_drug_data;
    SELECT COUNT(*) INTO v_rows_asp FROM bi_historical_asp;
    SELECT COUNT(*) INTO v_rows_wac FROM bi_historical_wac;
    SELECT COUNT(*) INTO v_rows_awp FROM bi_historical_awp;
    
    -- Log completion
    UPDATE bi_refresh_log 
    SET status = 'COMPLETED', 
        message = 'All BI tables refreshed successfully',
        completed_at = NOW(),
        rows_consolidated = v_rows_consolidated,
        rows_asp = v_rows_asp,
        rows_wac = v_rows_wac,
        rows_awp = v_rows_awp
    WHERE id = v_log_id;
    
END //

DELIMITER ;

-- =====================================================
-- Verification and Monitoring Queries
-- =====================================================

-- Check if event was created
SHOW EVENTS WHERE Name = 'refresh_bi_tables_daily';

-- View event scheduler status
SHOW VARIABLES LIKE 'event_scheduler';

-- View refresh log
SELECT * FROM bi_refresh_log ORDER BY started_at DESC LIMIT 10;

-- =====================================================
-- Management Commands
-- =====================================================

-- Disable event temporarily
-- ALTER EVENT refresh_bi_tables_daily DISABLE;

-- Enable event
-- ALTER EVENT refresh_bi_tables_daily ENABLE;

-- Change schedule to 3 AM
-- ALTER EVENT refresh_bi_tables_daily
-- ON SCHEDULE EVERY 1 DAY
-- STARTS (CURRENT_DATE + INTERVAL 1 DAY + INTERVAL 3 HOUR);

-- Run manually (requires stored procedure)
-- CALL sp_refresh_bi_tables();

-- Delete event
-- DROP EVENT IF EXISTS refresh_bi_tables_daily;
