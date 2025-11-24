-- Verify what's left in the table
SELECT
    'CURRENT STATE' AS check_type,
    COUNT(*) AS total_rows,
    COUNT(DISTINCT HCPCS_Code) AS unique_drugs,
    MIN(month_year) AS earliest_month,
    MAX(month_year) AS latest_month,
    COUNT(DISTINCT month_year) AS distinct_months
FROM bi_hcpcs_drug_pricing;

-- Show what quarters remain
SELECT
    CONCAT('Q',
           QUARTER(STR_TO_DATE(CONCAT('01-', REPLACE(REPLACE(month_year, '.', '-'), 'Feburary', 'February')), '%d-%M-%Y')),
           YEAR(STR_TO_DATE(CONCAT('01-', REPLACE(REPLACE(month_year, '.', '-'), 'Feburary', 'February')), '%d-%M-%Y'))
    ) AS Quarter,
    COUNT(*) AS row_count,
    COUNT(DISTINCT HCPCS_Code) AS unique_drugs,
    GROUP_CONCAT(DISTINCT month_year ORDER BY month_year) AS months
FROM bi_hcpcs_drug_pricing
GROUP BY Quarter;

-- Sample of remaining data
SELECT
    HCPCS_Code,
    month_year,
    Drug_Name,
    CONCAT('Q',
           QUARTER(STR_TO_DATE(CONCAT('01-', REPLACE(REPLACE(month_year, '.', '-'), 'Feburary', 'February')), '%d-%M-%Y')),
           YEAR(STR_TO_DATE(CONCAT('01-', REPLACE(REPLACE(month_year, '.', '-'), 'Feburary', 'February')), '%d-%M-%Y'))
    ) AS Quarter
FROM bi_hcpcs_drug_pricing
ORDER BY month_year DESC, HCPCS_Code
LIMIT 20;

-- Check the source table to see what we should have
SELECT
    'SOURCE TABLE CHECK' AS info,
    CONCAT('Q',
           QUARTER(STR_TO_DATE(CONCAT('01-', REPLACE(REPLACE(month_year, '.', '-'), 'Feburary', 'February')), '%d-%M-%Y')),
           YEAR(STR_TO_DATE(CONCAT('01-', REPLACE(REPLACE(month_year, '.', '-'), 'Feburary', 'February')), '%d-%M-%Y'))
    ) AS Quarter,
    COUNT(DISTINCT HCPCS_Code) AS unique_drugs_in_source,
    COUNT(DISTINCT month_year) AS distinct_months,
    MIN(month_year) AS first_month,
    MAX(month_year) AS last_month
FROM cms_drug_pricing
WHERE HCPCS_Code IS NOT NULL
    AND month_year IS NOT NULL
    AND month_year != 'month_year'
GROUP BY Quarter
ORDER BY Quarter DESC
LIMIT 5;
