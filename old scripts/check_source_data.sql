-- Check what's in the source cms_drug_pricing table
SELECT
    CONCAT('Q',
           QUARTER(STR_TO_DATE(CONCAT('01-', REPLACE(REPLACE(month_year, '.', '-'), 'Feburary', 'February')), '%d-%M-%Y')),
           YEAR(STR_TO_DATE(CONCAT('01-', REPLACE(REPLACE(month_year, '.', '-'), 'Feburary', 'February')), '%d-%M-%Y'))
    ) AS Quarter,
    COUNT(DISTINCT HCPCS_Code) AS unique_drugs,
    COUNT(*) AS total_rows,
    MIN(month_year) AS first_month,
    MAX(month_year) AS last_month,
    COUNT(DISTINCT month_year) AS distinct_months
FROM cms_drug_pricing
WHERE HCPCS_Code IS NOT NULL
    AND month_year IS NOT NULL
    AND month_year != 'month_year'
    AND month_year LIKE '%.%'
    AND LENGTH(month_year) >= 8
GROUP BY Quarter
ORDER BY Quarter DESC
LIMIT 10;

-- Check the latest data available
SELECT
    'LATEST DATA CHECK' AS info,
    MAX(month_year) AS latest_month_in_source,
    COUNT(DISTINCT HCPCS_Code) AS drugs_in_latest_month
FROM cms_drug_pricing
WHERE HCPCS_Code IS NOT NULL
    AND month_year IS NOT NULL
    AND month_year != 'month_year';
