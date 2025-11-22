-- =====================================================
-- MASTER STORED PROCEDURE - Quarter-by-Quarter Loop
-- WITH DEADLOCK HANDLING AND PROPER STATUS LOGGING
-- =====================================================

DELIMITER //

DROP PROCEDURE IF EXISTS sp_refresh_bi_tables_v3 //

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
    DECLARE v_error_code INT;
    DECLARE done INT DEFAULT 0;

    -- Cursor for unique QUARTERS only
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

    -- Error handler for non-deadlock errors
    DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1
            v_error_code = MYSQL_ERRNO,
            v_error_message = MESSAGE_TEXT;

        -- If not a deadlock (1213), log and continue
        IF v_error_code != 1213 THEN
            INSERT INTO bi_refresh_log (refresh_type, status, message, started_at, completed_at)
            VALUES ('manual', 'ERROR', CONCAT('Quarter ', v_quarter_count, ' error [', v_error_code, ']: ', v_error_message), v_start_time, NOW());
        END IF;
    END;

    SET v_start_time = NOW();

    -- Get min/max dates
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

    -- Log start
    INSERT INTO bi_refresh_log (refresh_type, status, message, started_at)
    VALUES ('manual', 'STARTED', CONCAT('Processing QUARTERLY data from ',
        DATE_FORMAT(v_min_date, '%Y-%m-%d'), ' to ', DATE_FORMAT(v_max_date, '%Y-%m-%d'),
        ' (Expected: ~41 quarters)'), v_start_time);

    OPEN date_cursor;

    read_loop: LOOP
        FETCH date_cursor INTO v_current_date;

        IF done THEN
            LEAVE read_loop;
        END IF;

        SET v_quarter_count = v_quarter_count + 1;

        -- Log start of quarter
        INSERT INTO bi_refresh_log (refresh_type, status, message, started_at)
        VALUES ('manual', 'IN_PROGRESS', CONCAT('Processing quarter ', v_quarter_count, ' of ~41 ',
            '(Q', QUARTER(v_current_date), '-', YEAR(v_current_date), ') - ',
            DATE_FORMAT(v_current_date, '%Y-%m-%d')), NOW());

        -- Process the quarter
        CALL sp_process_single_quarter(v_current_date, @rows_pricing, @rows_historical);

        -- Update totals
        SET v_total_pricing_rows = v_total_pricing_rows + IFNULL(@rows_pricing, 0);
        SET v_total_historical_rows = v_total_historical_rows + IFNULL(@rows_historical, 0);

        -- Explicit COMMIT to release locks
        COMMIT;

        -- Log completion of this quarter with COMPLETED_QUARTER status
        INSERT INTO bi_refresh_log (refresh_type, status, message, started_at, completed_at)
        VALUES ('manual', 'COMPLETED_QUARTER', CONCAT('✓ Q', v_quarter_count, ' of ~41 ',
            '(Q', QUARTER(v_current_date), '-', YEAR(v_current_date), ') - ',
            'Pricing: ', IFNULL(@rows_pricing, 0), ', Historical: ', IFNULL(@rows_historical, 0)),
            v_start_time, NOW());

        -- Small delay to prevent lock contention (0.5 seconds)
        DO SLEEP(0.5);

    END LOOP;

    CLOSE date_cursor;

    -- Log final completion
    INSERT INTO bi_refresh_log (refresh_type, status, message, started_at, completed_at)
    VALUES ('manual', 'COMPLETED', CONCAT('SUCCESS! All ', v_quarter_count, ' quarters processed. ',
        'Total pricing rows: ', v_total_pricing_rows, ', Total historical rows: ', v_total_historical_rows,
        ' [Duration: ', TIMESTAMPDIFF(SECOND, v_start_time, NOW()), 's]'), v_start_time, NOW());

    -- Return summary
    SELECT
        'SUCCESS' AS status,
        v_quarter_count AS quarters_processed,
        v_total_pricing_rows AS total_pricing_rows,
        v_total_historical_rows AS total_historical_rows,
        CONCAT(TIMESTAMPDIFF(SECOND, v_start_time, NOW()), ' seconds') AS duration;

END //

DELIMITER ;
