-- =====================================================
-- SQL Query to Create Consolidated Power BI Table
-- This replaces the manual Excel file processing pipeline
-- =====================================================

-- Drop the table if it exists
DROP TABLE IF EXISTS bi_consolidated_drug_data;

-- Create the consolidated table
CREATE TABLE bi_consolidated_drug_data AS
WITH 
-- CTE 1: Base data from cms_drug_pricing with calculated fields
base_data AS (
    SELECT 
        HCPCS_Code,
        Short_Description,
        LABELER_NAME AS Manufacturer,
        Drug_Name AS Brand_name,
        Payment_Limit AS Medicare_Payment_Limit,
        
        -- ASP handling (using override if available, otherwise regular ASP)
        CASE 
            WHEN ASP_Override IS NOT NULL AND ASP_Override != 0 THEN ASP_Override
            ELSE ASP 
        END AS ASP_Current,
        
        -- WAC and AWP fields
        Current_WAC_Unit_Price AS WAC_per_Unit,
        Current_AWP_Unit_Price AS AWP_per_Unit,
        
        -- Date fields
        Current_WAC_Effect_Date AS WAC_Effect_Date,
        Current_AWP_Effect_Date AS AWP_Effect_Date,
        GREATEST(
            COALESCE(Current_WAC_Effect_Date, '1900-01-01'),
            COALESCE(Current_AWP_Effect_Date, '1900-01-01')
        ) AS WAC_AWP_Last_Change,
        
        -- Time period fields
        month_year,
        month_name,
        year_name,
        
        -- Additional metadata
        product,
        route_of_administration,
        brand_generic,
        product_category,
        HCPCS_Deactivation,
        J_Code_Desc,
        
        -- Create a date field from month_year for easier time-based queries
        -- Handle both "Oct-2024" and "Oct.2024" formats, and full month names
        -- Fix common typos like "Feburary"
        STR_TO_DATE(
            CONCAT('01-', REPLACE(REPLACE(month_year, '.', '-'), 'Feburary', 'February')), 
            '%d-%M-%Y'
        ) AS period_date,
        
        -- Row number to help with historical tracking
        ROW_NUMBER() OVER (
            PARTITION BY HCPCS_Code 
            ORDER BY STR_TO_DATE(
                CONCAT('01-', REPLACE(REPLACE(month_year, '.', '-'), 'Feburary', 'February')), 
                '%d-%M-%Y'
            ) DESC
        ) AS period_rank
        
    FROM cms_drug_pricing
    WHERE HCPCS_Code IS NOT NULL
        AND month_year IS NOT NULL
        AND month_year != 'month_year'  -- Exclude header rows
        AND month_year LIKE '%.%'       -- Must contain period separator
        AND LENGTH(month_year) >= 8     -- Minimum valid length (May.2015 = 8 chars)
),

-- CTE 2: Current quarter data (most recent period)
current_quarter AS (
    SELECT 
        HCPCS_Code,
        ASP_Current AS ASP_per_Unit_Current_Quarter,
        WAC_per_Unit AS Median_WAC_per_HCPCS_Unit,
        AWP_per_Unit AS Median_AWP_per_HCPCS_Unit,
        period_date AS current_period_date
    FROM base_data
    WHERE period_rank = 1
),

-- CTE 3: Previous quarter data
previous_quarter AS (
    SELECT 
        HCPCS_Code,
        ASP_Current AS ASP_per_Unit_Previous_Quarter,
        period_date AS previous_period_date
    FROM base_data
    WHERE period_rank = 2
),

-- CTE 4: Calculate quarterly changes and ratios
calculated_metrics AS (
    SELECT 
        c.HCPCS_Code,
        c.ASP_per_Unit_Current_Quarter,
        p.ASP_per_Unit_Previous_Quarter,
        
        -- Calculate ASP Quarterly Change %
        CASE 
            WHEN p.ASP_per_Unit_Previous_Quarter IS NOT NULL 
                 AND p.ASP_per_Unit_Previous_Quarter != 0 
            THEN ((c.ASP_per_Unit_Current_Quarter - p.ASP_per_Unit_Previous_Quarter) 
                  / p.ASP_per_Unit_Previous_Quarter)
            ELSE NULL
        END AS ASP_Quarterly_Change_Pct,
        
        c.Median_WAC_per_HCPCS_Unit,
        c.Median_AWP_per_HCPCS_Unit,
        
        -- Calculate ASP/WAC Ratio
        CASE 
            WHEN c.Median_WAC_per_HCPCS_Unit IS NOT NULL 
                 AND c.Median_WAC_per_HCPCS_Unit != 0
            THEN c.ASP_per_Unit_Current_Quarter / c.Median_WAC_per_HCPCS_Unit
            ELSE NULL
        END AS ASP_WAC_Ratio,
        
        -- Calculate ASP/AWP Ratio
        CASE 
            WHEN c.Median_AWP_per_HCPCS_Unit IS NOT NULL 
                 AND c.Median_AWP_per_HCPCS_Unit != 0
            THEN c.ASP_per_Unit_Current_Quarter / c.Median_AWP_per_HCPCS_Unit
            ELSE NULL
        END AS ASP_AWP_Ratio
        
    FROM current_quarter c
    LEFT JOIN previous_quarter p ON c.HCPCS_Code = p.HCPCS_Code
),

-- CTE 5: Historical ASP data (for time series analysis)
historical_asp AS (
    SELECT 
        HCPCS_Code,
        ASP_Current AS asp,
        period_date,
        CONCAT('Q', QUARTER(period_date), YEAR(period_date)) AS quarter
    FROM base_data
    WHERE ASP_Current IS NOT NULL
),

-- CTE 6: Historical WAC data (for time series analysis)
historical_wac AS (
    SELECT 
        HCPCS_Code,
        WAC_per_Unit AS Median_WAC,
        period_date,
        CONCAT('Q', QUARTER(period_date), YEAR(period_date)) AS quarter
    FROM base_data
    WHERE WAC_per_Unit IS NOT NULL
),

-- CTE 7: Historical AWP data (for time series analysis)
historical_awp AS (
    SELECT 
        HCPCS_Code,
        AWP_per_Unit AS Median_AWP,
        period_date,
        CONCAT('Q', QUARTER(period_date), YEAR(period_date)) AS quarter
    FROM base_data
    WHERE AWP_per_Unit IS NOT NULL
)

-- Final SELECT: Combine all data into consolidated structure
SELECT 
    -- Identifiers
    CAST(bd.HCPCS_Code AS CHAR(100)) AS HCPCS_Code,
    bd.Brand_name,
    CONCAT(bd.HCPCS_Code, ' - ', bd.Brand_name) AS Concat,
    CAST(bd.Manufacturer AS CHAR(255)) AS Manufacturer,
    bd.Short_Description,
    bd.J_Code_Desc,
    
    -- Current and Previous Quarter ASP
    cm.ASP_per_Unit_Previous_Quarter,
    cm.ASP_per_Unit_Current_Quarter,
    bd.Medicare_Payment_Limit,
    
    -- Calculated Metrics
    cm.ASP_Quarterly_Change_Pct,
    cm.Median_WAC_per_HCPCS_Unit,
    cm.Median_AWP_per_HCPCS_Unit,
    bd.WAC_AWP_Last_Change,
    ROUND(cm.ASP_WAC_Ratio, 4) AS ASP_WAC_Ratio,
    ROUND(cm.ASP_AWP_Ratio, 4) AS ASP_AWP_Ratio,
    
    -- Time Period Information
    CAST(bd.month_year AS CHAR(20)) AS month_year,
    CAST(bd.month_name AS CHAR(20)) AS month_name,
    CAST(bd.year_name AS CHAR(10)) AS year_name,
    bd.period_date,
    
    -- Additional Attributes
    CAST(bd.product AS CHAR(255)) AS product,
    CAST(bd.route_of_administration AS CHAR(100)) AS route_of_administration,
    CAST(bd.brand_generic AS CHAR(50)) AS brand_generic,
    CAST(bd.product_category AS CHAR(100)) AS product_category,
    CAST(bd.HCPCS_Deactivation AS CHAR(10)) AS HCPCS_Deactivation,
    
    -- Metadata
    CURRENT_TIMESTAMP AS data_refresh_timestamp

FROM base_data bd
INNER JOIN calculated_metrics cm ON bd.HCPCS_Code = cm.HCPCS_Code
WHERE bd.period_rank = 1  -- Only include most recent period in main table
ORDER BY bd.HCPCS_Code;

-- =====================================================
-- Modify column types for large text fields
-- MySQL doesn't support VARCHAR in CAST, so we ALTER after creation
-- =====================================================

ALTER TABLE bi_consolidated_drug_data
    MODIFY COLUMN Brand_name VARCHAR(18000),
    MODIFY COLUMN Concat VARCHAR(18100),
    MODIFY COLUMN Short_Description VARCHAR(300),
    MODIFY COLUMN J_Code_Desc VARCHAR(450);

-- =====================================================
-- Create indexes for better Power BI query performance
-- =====================================================

CREATE INDEX idx_hcpcs_code ON bi_consolidated_drug_data(HCPCS_Code);
CREATE INDEX idx_manufacturer ON bi_consolidated_drug_data(Manufacturer);
CREATE INDEX idx_period_date ON bi_consolidated_drug_data(period_date);
CREATE INDEX idx_brand_name ON bi_consolidated_drug_data(Brand_name(255));
CREATE INDEX idx_product_category ON bi_consolidated_drug_data(product_category);

-- =====================================================
-- Optional: Create separate time-series tables for historical data
-- These support the Historical ASP, WAC, AWP queries in Power Query
-- =====================================================

-- Historical ASP Table
DROP TABLE IF EXISTS bi_historical_asp;
CREATE TABLE bi_historical_asp AS
SELECT 
    CAST(HCPCS_Code AS CHAR(100)) AS HCPCS_Code,
    ROUND(
        CASE 
            WHEN ASP_Override IS NOT NULL AND ASP_Override != 0 THEN ASP_Override
            ELSE ASP 
        END, 2
    ) AS asp,
    CAST(CONCAT('Q', QUARTER(STR_TO_DATE(CONCAT('01-', REPLACE(REPLACE(month_year, '.', '-'), 'Feburary', 'February')), '%d-%M-%Y')), YEAR(STR_TO_DATE(CONCAT('01-', REPLACE(REPLACE(month_year, '.', '-'), 'Feburary', 'February')), '%d-%M-%Y'))) AS CHAR(10)) AS quarter,
    STR_TO_DATE(CONCAT('01-', REPLACE(REPLACE(month_year, '.', '-'), 'Feburary', 'February')), '%d-%M-%Y') AS Date
FROM cms_drug_pricing
WHERE HCPCS_Code IS NOT NULL
    AND month_year IS NOT NULL
    AND month_year != 'month_year'
    AND month_year LIKE '%.%'
    AND LENGTH(month_year) >= 8
    AND (CASE WHEN ASP_Override IS NOT NULL AND ASP_Override != 0 THEN ASP_Override ELSE ASP END) IS NOT NULL
ORDER BY HCPCS_Code, Date;

CREATE INDEX idx_hist_asp_hcpcs ON bi_historical_asp(HCPCS_Code);
CREATE INDEX idx_hist_asp_date ON bi_historical_asp(Date);

-- Historical WAC Table
DROP TABLE IF EXISTS bi_historical_wac;
CREATE TABLE bi_historical_wac AS
SELECT 
    CAST(HCPCS_Code AS CHAR(100)) AS HCPCS_Code,
    ROUND(Current_WAC_Unit_Price, 2) AS Median_WAC,
    CAST(CONCAT('Q', QUARTER(STR_TO_DATE(CONCAT('01-', REPLACE(REPLACE(month_year, '.', '-'), 'Feburary', 'February')), '%d-%M-%Y')), YEAR(STR_TO_DATE(CONCAT('01-', REPLACE(REPLACE(month_year, '.', '-'), 'Feburary', 'February')), '%d-%M-%Y'))) AS CHAR(10)) AS quarter,
    STR_TO_DATE(CONCAT('01-', REPLACE(REPLACE(month_year, '.', '-'), 'Feburary', 'February')), '%d-%M-%Y') AS Date
FROM cms_drug_pricing
WHERE HCPCS_Code IS NOT NULL
    AND month_year IS NOT NULL
    AND month_year != 'month_year'
    AND month_year LIKE '%.%'
    AND LENGTH(month_year) >= 8
    AND Current_WAC_Unit_Price IS NOT NULL
ORDER BY HCPCS_Code, Date;

CREATE INDEX idx_hist_wac_hcpcs ON bi_historical_wac(HCPCS_Code);
CREATE INDEX idx_hist_wac_date ON bi_historical_wac(Date);

-- Historical AWP Table
DROP TABLE IF EXISTS bi_historical_awp;
CREATE TABLE bi_historical_awp AS
SELECT 
    CAST(HCPCS_Code AS CHAR(100)) AS HCPCS_Code,
    ROUND(Current_AWP_Unit_Price, 2) AS Median_AWP,
    CAST(CONCAT('Q', QUARTER(STR_TO_DATE(CONCAT('01-', REPLACE(REPLACE(month_year, '.', '-'), 'Feburary', 'February')), '%d-%M-%Y')), YEAR(STR_TO_DATE(CONCAT('01-', REPLACE(REPLACE(month_year, '.', '-'), 'Feburary', 'February')), '%d-%M-%Y'))) AS CHAR(10)) AS quarter,
    STR_TO_DATE(CONCAT('01-', REPLACE(REPLACE(month_year, '.', '-'), 'Feburary', 'February')), '%d-%M-%Y') AS Date
FROM cms_drug_pricing
WHERE HCPCS_Code IS NOT NULL
    AND month_year IS NOT NULL
    AND month_year != 'month_year'
    AND month_year LIKE '%.%'
    AND LENGTH(month_year) >= 8
    AND Current_AWP_Unit_Price IS NOT NULL
ORDER BY HCPCS_Code, Date;

CREATE INDEX idx_hist_awp_hcpcs ON bi_historical_awp(HCPCS_Code);
CREATE INDEX idx_hist_awp_date ON bi_historical_awp(Date);

-- =====================================================
-- Optional: Create Drug Class lookup table
-- (You'll need to populate this from your Drug Class.xlsx file)
-- =====================================================

DROP TABLE IF EXISTS bi_drug_class;
CREATE TABLE bi_drug_class (
    HCPCS_Code VARCHAR(100) PRIMARY KEY,
    General_Drug_Class VARCHAR(255),
    Specialized_Drug_Class VARCHAR(255)
);

-- Note: You'll need to import data from Drug Class.xlsx into this table
-- Example import command (adjust based on your setup):
-- LOAD DATA LOCAL INFILE 'Drug_Class.csv' 
-- INTO TABLE bi_drug_class 
-- FIELDS TERMINATED BY ',' 
-- ENCLOSED BY '"'
-- LINES TERMINATED BY '\n'
-- IGNORE 1 ROWS;

CREATE INDEX idx_drug_class_hcpcs ON bi_drug_class(HCPCS_Code);

-- =====================================================
-- Grant permissions (adjust user as needed)
-- =====================================================

-- GRANT SELECT ON bi_consolidated_drug_data TO 'bi_user'@'%';
-- GRANT SELECT ON bi_historical_asp TO 'bi_user'@'%';
-- GRANT SELECT ON bi_historical_wac TO 'bi_user'@'%';
-- GRANT SELECT ON bi_historical_awp TO 'bi_user'@'%';
-- GRANT SELECT ON bi_drug_class TO 'bi_user'@'%';

-- =====================================================
-- Verification Queries
-- =====================================================

-- Check row counts
SELECT 'bi_consolidated_drug_data' AS table_name, COUNT(*) AS row_count 
FROM bi_consolidated_drug_data
UNION ALL
SELECT 'bi_historical_asp', COUNT(*) FROM bi_historical_asp
UNION ALL
SELECT 'bi_historical_wac', COUNT(*) FROM bi_historical_wac
UNION ALL
SELECT 'bi_historical_awp', COUNT(*) FROM bi_historical_awp;

-- Sample data check
SELECT * FROM bi_consolidated_drug_data LIMIT 10;
