-- =====================================================
-- REBUILD bi_hcpcs_drug_pricing FROM SCRATCH
-- Remove bad data and rebuild with latest quarter
-- =====================================================

-- Step 1: Drop and recreate the table with updated schema
-- (Removes: Current_WAC_Package_Price, Current_AWP_Package_Price, WAC_by_AWP_ratio)
DROP TABLE IF EXISTS bi_hcpcs_drug_pricing;

-- Step 2: Verify table was dropped (will show error - that's OK)
-- SELECT 'After Drop' AS status, COUNT(*) AS row_count FROM bi_hcpcs_drug_pricing;

-- Step 3: Now run the main procedure to rebuild everything
-- This will process all quarters and keep only the latest (Q4 2024)
CALL sp_refresh_bi_tables_v3();

-- Step 4: Verify the result
SELECT
    'FINAL RESULT' AS check_type,
    COUNT(*) AS total_rows,
    COUNT(DISTINCT HCPCS_Code) AS unique_drugs,
    COUNT(DISTINCT month_year) AS distinct_months,
    MIN(month_year) AS earliest_month,
    MAX(month_year) AS latest_month,
    CONCAT('Q',
           QUARTER(STR_TO_DATE(CONCAT('01-', REPLACE(REPLACE(MAX(month_year), '.', '-'), 'Feburary', 'February')), '%d-%M-%Y')),
           YEAR(STR_TO_DATE(CONCAT('01-', REPLACE(REPLACE(MAX(month_year), '.', '-'), 'Feburary', 'February')), '%d-%M-%Y'))
    ) AS latest_quarter
FROM bi_hcpcs_drug_pricing;

-- Step 5: Show month distribution
SELECT
    month_year,
    COUNT(*) AS row_count,
    COUNT(DISTINCT HCPCS_Code) AS unique_drugs
FROM bi_hcpcs_drug_pricing
GROUP BY month_year
ORDER BY month_year DESC;
