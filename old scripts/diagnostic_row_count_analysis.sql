-- =====================================================
-- DIAGNOSTIC ANALYSIS: Row Count Comparison
-- Investigating bi_hcpcs_drug_pricing vs bi_historical_pricing
-- =====================================================

-- 1. Basic row counts
SELECT
    'bi_hcpcs_drug_pricing' AS table_name,
    COUNT(*) AS total_rows,
    COUNT(DISTINCT HCPCS_Code) AS unique_hcpcs,
    COUNT(DISTINCT month_year) AS unique_periods
FROM bi_hcpcs_drug_pricing

UNION ALL

SELECT
    'bi_historical_pricing' AS table_name,
    COUNT(*) AS total_rows,
    COUNT(DISTINCT HCPCS_Code) AS unique_hcpcs,
    COUNT(DISTINCT Quarter) AS unique_periods
FROM bi_historical_pricing;

-- =====================================================
-- 2. Check if the 3:1 ratio is correct (monthly vs quarterly)
-- =====================================================

SELECT
    'Expected Ratio Analysis' AS analysis,
    (SELECT COUNT(*) FROM bi_hcpcs_drug_pricing) AS pricing_rows,
    (SELECT COUNT(*) FROM bi_historical_pricing) AS historical_rows,
    ROUND((SELECT COUNT(*) FROM bi_hcpcs_drug_pricing) /
          (SELECT COUNT(*) FROM bi_historical_pricing), 2) AS actual_ratio,
    '~3.0' AS expected_ratio;

-- =====================================================
-- 3. Check for duplicate or missing data
-- =====================================================

-- Check for duplicates in bi_hcpcs_drug_pricing
SELECT
    'bi_hcpcs_drug_pricing duplicates' AS check_type,
    COUNT(*) - COUNT(DISTINCT CONCAT(HCPCS_Code, '|', month_year)) AS duplicate_count
FROM bi_hcpcs_drug_pricing

UNION ALL

-- Check for duplicates in bi_historical_pricing
SELECT
    'bi_historical_pricing duplicates' AS check_type,
    COUNT(*) - COUNT(DISTINCT CONCAT(HCPCS_Code, '|', Quarter)) AS duplicate_count
FROM bi_historical_pricing;

-- =====================================================
-- 4. Sample data comparison for a specific HCPCS code
-- =====================================================

-- Pick a HCPCS code that exists in both tables
SET @sample_hcpcs = (
    SELECT HCPCS_Code
    FROM bi_hcpcs_drug_pricing
    WHERE HCPCS_Code IN (SELECT HCPCS_Code FROM bi_historical_pricing)
    LIMIT 1
);

-- Show monthly data
SELECT
    'MONTHLY DATA' AS data_type,
    HCPCS_Code,
    month_year,
    ASP_current_quarter
FROM bi_hcpcs_drug_pricing
WHERE HCPCS_Code = @sample_hcpcs
ORDER BY month_year
LIMIT 10;

-- Show quarterly data for same code
SELECT
    'QUARTERLY DATA' AS data_type,
    HCPCS_Code,
    Quarter,
    ASP
FROM bi_historical_pricing
WHERE HCPCS_Code = @sample_hcpcs
ORDER BY Quarter
LIMIT 10;

-- =====================================================
-- 5. Check period distribution
-- =====================================================

-- Months per quarter in bi_hcpcs_drug_pricing
SELECT
    CONCAT('Q', QUARTER(STR_TO_DATE(CONCAT('01-', month_year), '%d-%M-%Y')),
           YEAR(STR_TO_DATE(CONCAT('01-', month_year), '%d-%M-%Y'))) AS Quarter,
    COUNT(*) AS monthly_records,
    COUNT(DISTINCT month_year) AS months_in_quarter
FROM bi_hcpcs_drug_pricing
GROUP BY Quarter
ORDER BY Quarter
LIMIT 20;

-- =====================================================
-- 6. Find any quarters in historical that don't have corresponding months
-- =====================================================

SELECT
    h.Quarter,
    COUNT(DISTINCT h.HCPCS_Code) AS hcpcs_in_historical,
    COUNT(DISTINCT p.HCPCS_Code) AS hcpcs_in_pricing
FROM bi_historical_pricing h
LEFT JOIN bi_hcpcs_drug_pricing p
    ON h.HCPCS_Code = p.HCPCS_Code
    AND CONCAT('Q', QUARTER(STR_TO_DATE(CONCAT('01-', p.month_year), '%d-%M-%Y')),
               YEAR(STR_TO_DATE(CONCAT('01-', p.month_year), '%d-%M-%Y'))) = h.Quarter
GROUP BY h.Quarter
HAVING hcpcs_in_historical != hcpcs_in_pricing
ORDER BY h.Quarter
LIMIT 20;

-- =====================================================
-- 7. Check if there are HCPCS codes with inconsistent data
-- =====================================================

SELECT
    'HCPCS in pricing but not historical' AS check_type,
    COUNT(DISTINCT p.HCPCS_Code) AS count
FROM bi_hcpcs_drug_pricing p
LEFT JOIN bi_historical_pricing h ON p.HCPCS_Code = h.HCPCS_Code
WHERE h.HCPCS_Code IS NULL

UNION ALL

SELECT
    'HCPCS in historical but not pricing' AS check_type,
    COUNT(DISTINCT h.HCPCS_Code) AS count
FROM bi_historical_pricing h
LEFT JOIN bi_hcpcs_drug_pricing p ON h.HCPCS_Code = p.HCPCS_Code
WHERE p.HCPCS_Code IS NULL;
