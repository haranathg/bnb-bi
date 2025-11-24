-- =====================================================
-- CHECK: Quarter Distribution in bi_hcpcs_drug_pricing
-- This should show ONLY the most recent quarter if working correctly
-- =====================================================

SELECT
    CONCAT('Q', QUARTER(STR_TO_DATE(CONCAT('01-', month_year), '%d-%M-%Y')),
           YEAR(STR_TO_DATE(CONCAT('01-', month_year), '%d-%M-%Y'))) AS Quarter,
    COUNT(*) AS row_count,
    COUNT(DISTINCT HCPCS_Code) AS unique_drugs,
    COUNT(DISTINCT month_year) AS unique_months,
    MIN(month_year) AS first_month,
    MAX(month_year) AS last_month
FROM bi_hcpcs_drug_pricing
GROUP BY Quarter
ORDER BY Quarter DESC
LIMIT 15;

-- =====================================================
-- Show the LATEST quarter info
-- =====================================================

SELECT
    'LATEST QUARTER SUMMARY' AS info,
    CONCAT('Q', QUARTER(STR_TO_DATE(CONCAT('01-', MAX(month_year)), '%d-%M-%Y')),
           YEAR(STR_TO_DATE(CONCAT('01-', MAX(month_year)), '%d-%M-%Y'))) AS latest_quarter,
    MAX(month_year) AS latest_month_year,
    (SELECT COUNT(*) FROM bi_hcpcs_drug_pricing) AS total_rows_in_table
FROM bi_hcpcs_drug_pricing;

-- =====================================================
-- Count how many quarters exist in the table
-- =====================================================

SELECT
    'TOTAL QUARTERS IN TABLE' AS metric,
    COUNT(DISTINCT CONCAT('Q', QUARTER(STR_TO_DATE(CONCAT('01-', month_year), '%d-%M-%Y')),
           YEAR(STR_TO_DATE(CONCAT('01-', month_year), '%d-%M-%Y')))) AS quarter_count
FROM bi_hcpcs_drug_pricing;
