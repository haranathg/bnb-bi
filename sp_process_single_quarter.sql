-- =====================================================
-- SINGLE QUARTER PROCESSOR
-- This is the WORKING version that completed in 35 seconds
-- Processes ONE quarter/month at a time
-- =====================================================

DELIMITER //

DROP PROCEDURE IF EXISTS sp_process_single_quarter //

CREATE PROCEDURE sp_process_single_quarter(
    IN p_target_date DATE,
    OUT p_rows_pricing INT,
    OUT p_rows_historical INT
)
BEGIN
    DECLARE v_start_time DATETIME;
    DECLARE v_error_message TEXT;

    -- Error handler
    DECLARE exit handler FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 v_error_message = MESSAGE_TEXT;
        INSERT INTO bi_refresh_log (refresh_type, status, message, started_at, completed_at)
        VALUES ('manual', 'FAILED', CONCAT('Error processing ', DATE_FORMAT(p_target_date, '%Y-%m-%d'), ': ', v_error_message), v_start_time, NOW());
        RESIGNAL;
    END;

    SET v_start_time = NOW();
    SET p_rows_pricing = 0;
    SET p_rows_historical = 0;

    -- =====================================================
    -- STEP 1: CREATE STAGING TABLE (ALL DATA)
    -- =====================================================

    DROP TEMPORARY TABLE IF EXISTS bi_hcpcs_drug_pricing_stg;

    CREATE TEMPORARY TABLE bi_hcpcs_drug_pricing_stg (
        HCPCS_Code VARCHAR(100),
        Manufacturer VARCHAR(255),
        NDC2 VARCHAR(50),
        Drug_Name VARCHAR(500),
        BILLUNITSPKG DECIMAL(18,4),
        HCPCS_Code_Dosage VARCHAR(100),
        Payment_Limit DECIMAL(18,4),
        Current_WAC_Package_Price DECIMAL(18,4),
        Current_WAC_Effect_Date DATE,
        Current_AWP_Package_Price DECIMAL(18,4),
        Current_AWP_Effect_Date DATE,
        J_Code_Desc VARCHAR(500),
        month_name VARCHAR(20),
        year_name VARCHAR(10),
        month_year VARCHAR(20),
        ASP_Override DECIMAL(18,4),
        WAC_per_unit DECIMAL(18,4),
        AWP_per_unit DECIMAL(18,4),
        ASP DECIMAL(18,4),
        period_date DATE,
        Quarter VARCHAR(20),
        INDEX idx_stg_quarter (Quarter, HCPCS_Code),
        INDEX idx_stg_period_date (period_date),
        INDEX idx_stg_hcpcs_quarter (HCPCS_Code, Quarter),
        INDEX idx_stg_hcpcs (HCPCS_Code)
    );

    INSERT INTO bi_hcpcs_drug_pricing_stg
    SELECT
        CAST(HCPCS_Code AS CHAR(100)) AS HCPCS_Code,
        CAST(LABELER_NAME AS CHAR(255)) AS Manufacturer,
        CAST(NDC2 AS CHAR(50)) AS NDC2,
        CAST(Drug_Name AS CHAR(500)) AS Drug_Name,
        CAST(BILLUNITSPKG AS DECIMAL(18,4)) AS BILLUNITSPKG,
        CAST(HCPCS_Code_Dosage AS CHAR(100)) AS HCPCS_Code_Dosage,
        CAST(Payment_Limit AS DECIMAL(18,4)) AS Payment_Limit,
        CAST(Current_WAC_Package_Price AS DECIMAL(18,4)) AS Current_WAC_Package_Price,
        STR_TO_DATE(Current_WAC_Effect_Date, '%c/%e/%y') AS Current_WAC_Effect_Date,
        CAST(Current_AWP_Package_Price AS DECIMAL(18,4)) AS Current_AWP_Package_Price,
        STR_TO_DATE(Current_AWP_Effect_Date, '%c/%e/%y') AS Current_AWP_Effect_Date,
        CAST(J_Code_Desc AS CHAR(500)) AS J_Code_Desc,
        CAST(month_name AS CHAR(20)) AS month_name,
        CAST(year_name AS CHAR(10)) AS year_name,
        CAST(month_year AS CHAR(20)) AS month_year,
        CAST(ASP_Override AS DECIMAL(18,4)) AS ASP_Override,
        CASE
            WHEN CAST(BILLUNITSPKG AS DECIMAL(18,4)) IS NOT NULL
                 AND CAST(BILLUNITSPKG AS DECIMAL(18,4)) != 0
                 AND CAST(Current_WAC_Package_Price AS DECIMAL(18,4)) IS NOT NULL
            THEN CAST(Current_WAC_Package_Price AS DECIMAL(18,4)) / CAST(BILLUNITSPKG AS DECIMAL(18,4))
            ELSE NULL
        END AS WAC_per_unit,
        CASE
            WHEN CAST(BILLUNITSPKG AS DECIMAL(18,4)) IS NOT NULL
                 AND CAST(BILLUNITSPKG AS DECIMAL(18,4)) != 0
                 AND CAST(Current_AWP_Package_Price AS DECIMAL(18,4)) IS NOT NULL
            THEN CAST(Current_AWP_Package_Price AS DECIMAL(18,4)) / CAST(BILLUNITSPKG AS DECIMAL(18,4))
            ELSE NULL
        END AS AWP_per_unit,
        CASE
            WHEN CAST(ASP_Override AS DECIMAL(18,4)) IS NOT NULL
                 AND CAST(ASP_Override AS DECIMAL(18,4)) != 0
            THEN CAST(ASP_Override AS DECIMAL(18,4))
            WHEN CAST(Payment_Limit AS DECIMAL(18,4)) IS NOT NULL
                 AND CAST(Payment_Limit AS DECIMAL(18,4)) != 0
            THEN CAST(Payment_Limit AS DECIMAL(18,4)) / 1.06
            ELSE NULL
        END AS ASP,
        STR_TO_DATE(
            CONCAT('01-', REPLACE(REPLACE(month_year, '.', '-'), 'Feburary', 'February')),
            '%d-%M-%Y'
        ) AS period_date,
        CONCAT(
            'Q',
            QUARTER(STR_TO_DATE(CONCAT('01-', REPLACE(REPLACE(month_year, '.', '-'), 'Feburary', 'February')), '%d-%M-%Y')),
            YEAR(STR_TO_DATE(CONCAT('01-', REPLACE(REPLACE(month_year, '.', '-'), 'Feburary', 'February')), '%d-%M-%Y'))
        ) AS Quarter
    FROM cms_drug_pricing
    WHERE HCPCS_Code IS NOT NULL
        AND month_year IS NOT NULL
        AND month_year != 'month_year'
        AND month_year LIKE '%.%'
        AND LENGTH(month_year) >= 8;

    -- =====================================================
    -- STEP 2: PROCESS bi_hcpcs_drug_pricing (TARGET DATE ONLY)
    -- =====================================================

    CREATE TABLE IF NOT EXISTS bi_hcpcs_drug_pricing (
        HCPCS_Code VARCHAR(100) NOT NULL,
        Manufacturer VARCHAR(255),
        Drug_Name VARCHAR(500),
        BILLUNITSPKG DECIMAL(18,4),
        HCPCS_Code_Dosage VARCHAR(100),
        Payment_Limit DECIMAL(18,4),
        Current_WAC_Effect_Date DATE,
        Current_AWP_Effect_Date DATE,
        J_Code_Desc VARCHAR(500),
        month_name VARCHAR(20),
        year_name VARCHAR(10),
        month_year VARCHAR(20) NOT NULL,
        ASP_Override DECIMAL(18,4),
        ASP_current_quarter DECIMAL(18,4),
        ASP_prev_quarter DECIMAL(18,4),
        ASP_Quarterly_Change_Pct DECIMAL(10,4),
        Median_WAC DECIMAL(18,4),
        Median_AWP DECIMAL(18,4),
        ASP_by_WAC_ratio DECIMAL(10,4),
        ASP_by_AWP_ratio DECIMAL(10,4),
        Updated_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (HCPCS_Code, month_year),
        INDEX idx_hcpcs (HCPCS_Code),
        INDEX idx_month_year (month_year),
        INDEX idx_manufacturer (Manufacturer)
    );

    DROP TEMPORARY TABLE IF EXISTS temp_distinct_hcpcs_month;
    DROP TEMPORARY TABLE IF EXISTS temp_wac_ranked;
    DROP TEMPORARY TABLE IF EXISTS temp_awp_ranked;
    DROP TEMPORARY TABLE IF EXISTS temp_median_calcs;
    DROP TEMPORARY TABLE IF EXISTS temp_quarter_data;
    DROP TEMPORARY TABLE IF EXISTS temp_pricing_upsert;

    -- Get distinct HCPCS-month_year combinations (TARGET DATE ONLY)
    CREATE TEMPORARY TABLE temp_distinct_hcpcs_month AS
    SELECT DISTINCT HCPCS_Code, month_year
    FROM bi_hcpcs_drug_pricing_stg
    WHERE HCPCS_Code IS NOT NULL
        AND month_year IS NOT NULL
        AND period_date = p_target_date;

    -- Create ranked WAC data (TARGET DATE ONLY)
    CREATE TEMPORARY TABLE temp_wac_ranked AS
    SELECT
        HCPCS_Code,
        month_year,
        WAC_per_unit,
        ROW_NUMBER() OVER (PARTITION BY HCPCS_Code, month_year ORDER BY WAC_per_unit) AS row_num,
        COUNT(*) OVER (PARTITION BY HCPCS_Code, month_year) AS total_count
    FROM bi_hcpcs_drug_pricing_stg
    WHERE WAC_per_unit IS NOT NULL
        AND period_date = p_target_date;

    -- Create ranked AWP data (TARGET DATE ONLY)
    CREATE TEMPORARY TABLE temp_awp_ranked AS
    SELECT
        HCPCS_Code,
        month_year,
        AWP_per_unit,
        ROW_NUMBER() OVER (PARTITION BY HCPCS_Code, month_year ORDER BY AWP_per_unit) AS row_num,
        COUNT(*) OVER (PARTITION BY HCPCS_Code, month_year) AS total_count
    FROM bi_hcpcs_drug_pricing_stg
    WHERE AWP_per_unit IS NOT NULL
        AND period_date = p_target_date;

    -- Calculate medians
    CREATE TEMPORARY TABLE temp_median_calcs AS
    SELECT
        t1.HCPCS_Code,
        t1.month_year,
        AVG(wac_ranked.WAC_per_unit) AS Median_WAC,
        AVG(awp_ranked.AWP_per_unit) AS Median_AWP
    FROM temp_distinct_hcpcs_month t1
    LEFT JOIN temp_wac_ranked wac_ranked
        ON t1.HCPCS_Code = wac_ranked.HCPCS_Code
        AND t1.month_year = wac_ranked.month_year
        AND (
            wac_ranked.row_num = FLOOR((wac_ranked.total_count + 1) / 2)
            OR wac_ranked.row_num = FLOOR((wac_ranked.total_count + 2) / 2)
        )
    LEFT JOIN temp_awp_ranked awp_ranked
        ON t1.HCPCS_Code = awp_ranked.HCPCS_Code
        AND t1.month_year = awp_ranked.month_year
        AND (
            awp_ranked.row_num = FLOOR((awp_ranked.total_count + 1) / 2)
            OR awp_ranked.row_num = FLOOR((awp_ranked.total_count + 2) / 2)
        )
    GROUP BY t1.HCPCS_Code, t1.month_year;

    -- Create quarter data with LAG for previous quarter (TARGET DATE ONLY)
    -- NOTE: We look up ASP_prev_quarter from bi_historical_pricing since
    -- bi_hcpcs_drug_pricing only keeps the latest quarter's data
    -- IMPORTANT: Quarter strings (e.g., Q12026) don't sort chronologically,
    -- so we convert to a sortable format: YYYYQ (e.g., 20261 for Q1 2026)
    CREATE TEMPORARY TABLE temp_quarter_data AS
    SELECT
        s.HCPCS_Code,
        s.month_year,
        s.Quarter,
        s.ASP,
        (
            SELECT CAST(prev.ASP AS DECIMAL(18,4))
            FROM bi_historical_pricing prev
            WHERE prev.HCPCS_Code = s.HCPCS_Code
                AND CONCAT(SUBSTRING(prev.Quarter, 3), SUBSTRING(prev.Quarter, 2, 1)) <
                    CONCAT(SUBSTRING(s.Quarter, 3), SUBSTRING(s.Quarter, 2, 1))
                AND prev.ASP != 'NA'
            ORDER BY CONCAT(SUBSTRING(prev.Quarter, 3), SUBSTRING(prev.Quarter, 2, 1)) DESC
            LIMIT 1
        ) AS ASP_prev_quarter,
        s.period_date
    FROM bi_hcpcs_drug_pricing_stg s
    WHERE s.ASP IS NOT NULL
        AND s.period_date = p_target_date;

    -- Create temporary table with calculated data
    CREATE TEMPORARY TABLE temp_pricing_upsert AS
    SELECT
        bd.HCPCS_Code,
        bd.Manufacturer,
        bd.Drug_Name,
        bd.BILLUNITSPKG,
        bd.HCPCS_Code_Dosage,
        bd.Payment_Limit,
        bd.Current_WAC_Effect_Date,
        bd.Current_AWP_Effect_Date,
        bd.J_Code_Desc,
        bd.month_name,
        bd.year_name,
        bd.month_year,
        bd.ASP_Override,
        bd.ASP AS ASP_current_quarter,
        qd.ASP_prev_quarter,
        CASE
            WHEN qd.ASP_prev_quarter IS NOT NULL
                 AND qd.ASP_prev_quarter != 0
                 AND bd.ASP IS NOT NULL
            THEN ((bd.ASP - qd.ASP_prev_quarter) / qd.ASP_prev_quarter) * 100
            ELSE NULL
        END AS ASP_Quarterly_Change_Pct,
        mc.Median_WAC,
        mc.Median_AWP,
        CASE
            WHEN mc.Median_WAC IS NOT NULL AND mc.Median_WAC != 0
                 AND bd.ASP IS NOT NULL
            THEN bd.ASP / mc.Median_WAC
            ELSE NULL
        END AS ASP_by_WAC_ratio,
        CASE
            WHEN mc.Median_AWP IS NOT NULL AND mc.Median_AWP != 0
                 AND bd.ASP IS NOT NULL
            THEN bd.ASP / mc.Median_AWP
            ELSE NULL
        END AS ASP_by_AWP_ratio
    FROM (
        SELECT DISTINCT
            s.HCPCS_Code,
            s.Manufacturer,
            s.Drug_Name,
            s.BILLUNITSPKG,
            s.HCPCS_Code_Dosage,
            s.Payment_Limit,
            s.Current_WAC_Effect_Date,
            s.Current_AWP_Effect_Date,
            s.J_Code_Desc,
            s.month_name,
            s.year_name,
            s.month_year,
            s.ASP_Override,
            s.ASP,
            s.Quarter,
            s.period_date
        FROM bi_hcpcs_drug_pricing_stg s
        WHERE s.period_date = p_target_date
    ) bd
    LEFT JOIN temp_median_calcs mc
        ON bd.HCPCS_Code = mc.HCPCS_Code
        AND bd.month_year = mc.month_year
    LEFT JOIN temp_quarter_data qd
        ON bd.HCPCS_Code = qd.HCPCS_Code
        AND bd.month_year = qd.month_year;

    -- =====================================================
    -- CLEANUP: Delete old data to keep only latest quarter
    -- bi_hcpcs_drug_pricing should ONLY have the most recent quarter
    -- =====================================================

    -- Find the maximum quarter date being processed
    SET @max_quarter_date = (
        SELECT MAX(STR_TO_DATE(CONCAT('01-', REPLACE(REPLACE(month_year, '.', '-'), 'Feburary', 'February')), '%d-%M-%Y'))
        FROM bi_hcpcs_drug_pricing
    );

    -- Delete all data that's NOT from the most recent quarter
    -- Keep only data from the same quarter as the max date
    DELETE FROM bi_hcpcs_drug_pricing
    WHERE CONCAT('Q',
                 QUARTER(STR_TO_DATE(CONCAT('01-', REPLACE(REPLACE(month_year, '.', '-'), 'Feburary', 'February')), '%d-%M-%Y')),
                 YEAR(STR_TO_DATE(CONCAT('01-', REPLACE(REPLACE(month_year, '.', '-'), 'Feburary', 'February')), '%d-%M-%Y'))
          ) != CONCAT('Q', QUARTER(@max_quarter_date), YEAR(@max_quarter_date));

    -- UPSERT into bi_hcpcs_drug_pricing
    INSERT INTO bi_hcpcs_drug_pricing (
        HCPCS_Code, Manufacturer, Drug_Name, BILLUNITSPKG, HCPCS_Code_Dosage,
        Payment_Limit, Current_WAC_Effect_Date, Current_AWP_Effect_Date,
        J_Code_Desc, month_name, year_name, month_year, ASP_Override,
        ASP_current_quarter, ASP_prev_quarter, ASP_Quarterly_Change_Pct,
        Median_WAC, Median_AWP, ASP_by_WAC_ratio, ASP_by_AWP_ratio,
        Updated_date
    )
    SELECT
        HCPCS_Code, Manufacturer, Drug_Name, BILLUNITSPKG, HCPCS_Code_Dosage,
        Payment_Limit, Current_WAC_Effect_Date, Current_AWP_Effect_Date,
        J_Code_Desc, month_name, year_name, month_year, ASP_Override,
        ASP_current_quarter, ASP_prev_quarter, ASP_Quarterly_Change_Pct,
        Median_WAC, Median_AWP, ASP_by_WAC_ratio, ASP_by_AWP_ratio,
        CURRENT_TIMESTAMP
    FROM temp_pricing_upsert
    ON DUPLICATE KEY UPDATE
        Manufacturer = VALUES(Manufacturer),
        Drug_Name = VALUES(Drug_Name),
        BILLUNITSPKG = VALUES(BILLUNITSPKG),
        HCPCS_Code_Dosage = VALUES(HCPCS_Code_Dosage),
        Payment_Limit = VALUES(Payment_Limit),
        Current_WAC_Effect_Date = VALUES(Current_WAC_Effect_Date),
        Current_AWP_Effect_Date = VALUES(Current_AWP_Effect_Date),
        J_Code_Desc = VALUES(J_Code_Desc),
        month_name = VALUES(month_name),
        year_name = VALUES(year_name),
        ASP_Override = VALUES(ASP_Override),
        ASP_current_quarter = VALUES(ASP_current_quarter),
        ASP_prev_quarter = VALUES(ASP_prev_quarter),
        ASP_Quarterly_Change_Pct = VALUES(ASP_Quarterly_Change_Pct),
        Median_WAC = VALUES(Median_WAC),
        Median_AWP = VALUES(Median_AWP),
        ASP_by_WAC_ratio = VALUES(ASP_by_WAC_ratio),
        ASP_by_AWP_ratio = VALUES(ASP_by_AWP_ratio),
        Updated_date = CURRENT_TIMESTAMP;

    SELECT ROW_COUNT() INTO p_rows_pricing;

    -- =====================================================
    -- STEP 3: PROCESS bi_historical_pricing (TARGET QUARTER ONLY)
    -- =====================================================

    CREATE TABLE IF NOT EXISTS bi_historical_pricing (
        HCPCS_Code VARCHAR(100) NOT NULL,
        Quarter VARCHAR(10) NOT NULL,
        ASP VARCHAR(20),
        Median_WAC VARCHAR(20),
        Median_AWP VARCHAR(20),
        Updated_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (HCPCS_Code, Quarter),
        INDEX idx_hist_hcpcs (HCPCS_Code),
        INDEX idx_hist_quarter (Quarter)
    );

    DROP TEMPORARY TABLE IF EXISTS temp_hist_distinct_hcpcs_qtr;
    DROP TEMPORARY TABLE IF EXISTS temp_hist_first_period;
    DROP TEMPORARY TABLE IF EXISTS temp_hist_first_month;
    DROP TEMPORARY TABLE IF EXISTS temp_hist_wac_ranked;
    DROP TEMPORARY TABLE IF EXISTS temp_hist_awp_ranked;
    DROP TEMPORARY TABLE IF EXISTS temp_hist_median_calcs;
    DROP TEMPORARY TABLE IF EXISTS temp_historical_upsert;

    -- Get distinct HCPCS-Quarter combinations (TARGET QUARTER ONLY)
    CREATE TEMPORARY TABLE temp_hist_distinct_hcpcs_qtr AS
    SELECT DISTINCT HCPCS_Code, Quarter
    FROM bi_hcpcs_drug_pricing_stg
    WHERE HCPCS_Code IS NOT NULL
        AND Quarter IS NOT NULL
        AND Quarter = CONCAT('Q', QUARTER(p_target_date), YEAR(p_target_date));

    -- Get first period date for each HCPCS-Quarter (TARGET QUARTER ONLY)
    CREATE TEMPORARY TABLE temp_hist_first_period AS
    SELECT
        HCPCS_Code,
        Quarter,
        MIN(period_date) AS first_period_date
    FROM bi_hcpcs_drug_pricing_stg
    WHERE Quarter IS NOT NULL
        AND Quarter = CONCAT('Q', QUARTER(p_target_date), YEAR(p_target_date))
    GROUP BY HCPCS_Code, Quarter;

    -- Get first month data for each HCPCS-Quarter
    CREATE TEMPORARY TABLE temp_hist_first_month AS
    SELECT
        s.HCPCS_Code,
        s.Quarter,
        s.ASP,
        s.period_date,
        s.month_year,
        MONTH(s.period_date) AS first_month
    FROM bi_hcpcs_drug_pricing_stg s
    INNER JOIN temp_hist_first_period fm
        ON s.HCPCS_Code = fm.HCPCS_Code
        AND s.Quarter = fm.Quarter
        AND s.period_date = fm.first_period_date;

    -- Create ranked WAC data (TARGET QUARTER - first month only)
    CREATE TEMPORARY TABLE temp_hist_wac_ranked AS
    SELECT
        s.HCPCS_Code,
        s.Quarter,
        s.WAC_per_unit,
        ROW_NUMBER() OVER (PARTITION BY s.HCPCS_Code, s.Quarter ORDER BY s.WAC_per_unit) AS row_num,
        COUNT(*) OVER (PARTITION BY s.HCPCS_Code, s.Quarter) AS total_count
    FROM bi_hcpcs_drug_pricing_stg s
    INNER JOIN temp_hist_first_month fm
        ON s.HCPCS_Code = fm.HCPCS_Code
        AND s.Quarter = fm.Quarter
        AND MONTH(s.period_date) = fm.first_month
    WHERE s.WAC_per_unit IS NOT NULL;

    -- Create ranked AWP data (TARGET QUARTER - first month only)
    CREATE TEMPORARY TABLE temp_hist_awp_ranked AS
    SELECT
        s.HCPCS_Code,
        s.Quarter,
        s.AWP_per_unit,
        ROW_NUMBER() OVER (PARTITION BY s.HCPCS_Code, s.Quarter ORDER BY s.AWP_per_unit) AS row_num,
        COUNT(*) OVER (PARTITION BY s.HCPCS_Code, s.Quarter) AS total_count
    FROM bi_hcpcs_drug_pricing_stg s
    INNER JOIN temp_hist_first_month fm
        ON s.HCPCS_Code = fm.HCPCS_Code
        AND s.Quarter = fm.Quarter
        AND MONTH(s.period_date) = fm.first_month
    WHERE s.AWP_per_unit IS NOT NULL;

    -- Calculate medians
    CREATE TEMPORARY TABLE temp_hist_median_calcs AS
    SELECT
        t1.HCPCS_Code,
        t1.Quarter,
        AVG(wac_ranked.WAC_per_unit) AS Median_WAC,
        AVG(awp_ranked.AWP_per_unit) AS Median_AWP
    FROM temp_hist_distinct_hcpcs_qtr t1
    LEFT JOIN temp_hist_wac_ranked wac_ranked
        ON t1.HCPCS_Code = wac_ranked.HCPCS_Code
        AND t1.Quarter = wac_ranked.Quarter
        AND (
            wac_ranked.row_num = FLOOR((wac_ranked.total_count + 1) / 2)
            OR wac_ranked.row_num = FLOOR((wac_ranked.total_count + 2) / 2)
        )
    LEFT JOIN temp_hist_awp_ranked awp_ranked
        ON t1.HCPCS_Code = awp_ranked.HCPCS_Code
        AND t1.Quarter = awp_ranked.Quarter
        AND (
            awp_ranked.row_num = FLOOR((awp_ranked.total_count + 1) / 2)
            OR awp_ranked.row_num = FLOOR((awp_ranked.total_count + 2) / 2)
        )
    GROUP BY t1.HCPCS_Code, t1.Quarter;

    -- Create final historical upsert table
    CREATE TEMPORARY TABLE temp_historical_upsert AS
    SELECT
        fm.HCPCS_Code,
        fm.Quarter,
        COALESCE(CAST(ROUND(AVG(fm.ASP), 2) AS CHAR(20)), 'NA') AS ASP,
        COALESCE(CAST(ROUND(mc.Median_WAC, 2) AS CHAR(20)), 'NA') AS Median_WAC,
        COALESCE(CAST(ROUND(mc.Median_AWP, 2) AS CHAR(20)), 'NA') AS Median_AWP
    FROM temp_hist_first_month fm
    LEFT JOIN temp_hist_median_calcs mc
        ON fm.HCPCS_Code = mc.HCPCS_Code
        AND fm.Quarter = mc.Quarter
    GROUP BY fm.HCPCS_Code, fm.Quarter, mc.Median_WAC, mc.Median_AWP;

    -- UPSERT into bi_historical_pricing
    INSERT INTO bi_historical_pricing (
        HCPCS_Code, Quarter, ASP, Median_WAC, Median_AWP, Updated_date
    )
    SELECT
        HCPCS_Code, Quarter, ASP, Median_WAC, Median_AWP, CURRENT_TIMESTAMP
    FROM temp_historical_upsert
    ON DUPLICATE KEY UPDATE
        ASP = VALUES(ASP),
        Median_WAC = VALUES(Median_WAC),
        Median_AWP = VALUES(Median_AWP),
        Updated_date = CURRENT_TIMESTAMP;

    SELECT ROW_COUNT() INTO p_rows_historical;

    -- Clean up temporary tables
    DROP TEMPORARY TABLE IF EXISTS bi_hcpcs_drug_pricing_stg;
    DROP TEMPORARY TABLE IF EXISTS temp_distinct_hcpcs_month;
    DROP TEMPORARY TABLE IF EXISTS temp_wac_ranked;
    DROP TEMPORARY TABLE IF EXISTS temp_awp_ranked;
    DROP TEMPORARY TABLE IF EXISTS temp_median_calcs;
    DROP TEMPORARY TABLE IF EXISTS temp_quarter_data;
    DROP TEMPORARY TABLE IF EXISTS temp_pricing_upsert;
    DROP TEMPORARY TABLE IF EXISTS temp_hist_distinct_hcpcs_qtr;
    DROP TEMPORARY TABLE IF EXISTS temp_hist_first_period;
    DROP TEMPORARY TABLE IF EXISTS temp_hist_first_month;
    DROP TEMPORARY TABLE IF EXISTS temp_hist_wac_ranked;
    DROP TEMPORARY TABLE IF EXISTS temp_hist_awp_ranked;
    DROP TEMPORARY TABLE IF EXISTS temp_hist_median_calcs;
    DROP TEMPORARY TABLE IF EXISTS temp_historical_upsert;

END //

DELIMITER ;
