-- =====================================================
-- CLEANUP SCRIPT: Remove old quarters from bi_hcpcs_drug_pricing
-- Keep ONLY the most recent quarter's data
-- =====================================================

-- Step 1: Check current state BEFORE cleanup
SELECT
    'BEFORE CLEANUP' AS status,
    COUNT(*) AS total_rows,
    COUNT(DISTINCT HCPCS_Code) AS unique_drugs,
    COUNT(DISTINCT CONCAT('Q',
           QUARTER(STR_TO_DATE(CONCAT('01-', REPLACE(REPLACE(month_year, '.', '-'), 'Feburary', 'February')), '%d-%M-%Y')),
           YEAR(STR_TO_DATE(CONCAT('01-', REPLACE(REPLACE(month_year, '.', '-'), 'Feburary', 'February')), '%d-%M-%Y'))
    )) AS total_quarters,
    MAX(month_year) AS latest_month,
    CONCAT('Q',
           QUARTER(STR_TO_DATE(CONCAT('01-', REPLACE(REPLACE(MAX(month_year), '.', '-'), 'Feburary', 'February')), '%d-%M-%Y')),
           YEAR(STR_TO_DATE(CONCAT('01-', REPLACE(REPLACE(MAX(month_year), '.', '-'), 'Feburary', 'February')), '%d-%M-%Y'))
    ) AS latest_quarter
FROM bi_hcpcs_drug_pricing;

-- Step 2: Show quarter distribution
SELECT
    CONCAT('Q',
           QUARTER(STR_TO_DATE(CONCAT('01-', REPLACE(REPLACE(month_year, '.', '-'), 'Feburary', 'February')), '%d-%M-%Y')),
           YEAR(STR_TO_DATE(CONCAT('01-', REPLACE(REPLACE(month_year, '.', '-'), 'Feburary', 'February')), '%d-%M-%Y'))
    ) AS Quarter,
    COUNT(*) AS row_count,
    COUNT(DISTINCT HCPCS_Code) AS unique_drugs,
    MIN(month_year) AS first_month,
    MAX(month_year) AS last_month
FROM bi_hcpcs_drug_pricing
GROUP BY Quarter
ORDER BY Quarter DESC
LIMIT 10;

-- Step 3: PERFORM THE CLEANUP
-- Find the latest quarter (using REPLACE to handle dots in month_year)
SET @max_quarter_date = (
    SELECT MAX(STR_TO_DATE(CONCAT('01-', REPLACE(REPLACE(month_year, '.', '-'), 'Feburary', 'February')), '%d-%M-%Y'))
    FROM bi_hcpcs_drug_pricing
);

SET @latest_quarter = CONCAT('Q', QUARTER(@max_quarter_date), YEAR(@max_quarter_date));

-- Show what will be kept
SELECT
    'DATA TO BE KEPT' AS action,
    @latest_quarter AS quarter,
    COUNT(*) AS rows_to_keep
FROM bi_hcpcs_drug_pricing
WHERE CONCAT('Q',
             QUARTER(STR_TO_DATE(CONCAT('01-', REPLACE(REPLACE(month_year, '.', '-'), 'Feburary', 'February')), '%d-%M-%Y')),
             YEAR(STR_TO_DATE(CONCAT('01-', REPLACE(REPLACE(month_year, '.', '-'), 'Feburary', 'February')), '%d-%M-%Y'))
      ) = @latest_quarter;

-- Show what will be deleted
SELECT
    'DATA TO BE DELETED' AS action,
    COUNT(*) AS rows_to_delete,
    COUNT(DISTINCT CONCAT('Q',
           QUARTER(STR_TO_DATE(CONCAT('01-', REPLACE(REPLACE(month_year, '.', '-'), 'Feburary', 'February')), '%d-%M-%Y')),
           YEAR(STR_TO_DATE(CONCAT('01-', REPLACE(REPLACE(month_year, '.', '-'), 'Feburary', 'February')), '%d-%M-%Y'))
    )) AS quarters_to_delete
FROM bi_hcpcs_drug_pricing
WHERE CONCAT('Q',
             QUARTER(STR_TO_DATE(CONCAT('01-', REPLACE(REPLACE(month_year, '.', '-'), 'Feburary', 'February')), '%d-%M-%Y')),
             YEAR(STR_TO_DATE(CONCAT('01-', REPLACE(REPLACE(month_year, '.', '-'), 'Feburary', 'February')), '%d-%M-%Y'))
      ) != @latest_quarter;

-- ***** EXECUTE THE DELETE *****
-- UNCOMMENT THE FOLLOWING LINE TO EXECUTE:
-- DELETE FROM bi_hcpcs_drug_pricing
-- WHERE CONCAT('Q',
--              QUARTER(STR_TO_DATE(CONCAT('01-', REPLACE(REPLACE(month_year, '.', '-'), 'Feburary', 'February')), '%d-%M-%Y')),
--              YEAR(STR_TO_DATE(CONCAT('01-', REPLACE(REPLACE(month_year, '.', '-'), 'Feburary', 'February')), '%d-%M-%Y'))
--       ) != @latest_quarter;

-- Step 4: Check state AFTER cleanup
SELECT
    'AFTER CLEANUP' AS status,
    COUNT(*) AS total_rows,
    COUNT(DISTINCT HCPCS_Code) AS unique_drugs,
    COUNT(DISTINCT CONCAT('Q',
           QUARTER(STR_TO_DATE(CONCAT('01-', REPLACE(REPLACE(month_year, '.', '-'), 'Feburary', 'February')), '%d-%M-%Y')),
           YEAR(STR_TO_DATE(CONCAT('01-', REPLACE(REPLACE(month_year, '.', '-'), 'Feburary', 'February')), '%d-%M-%Y'))
    )) AS total_quarters,
    MIN(month_year) AS earliest_month,
    MAX(month_year) AS latest_month
FROM bi_hcpcs_drug_pricing;

-- Step 5: Verify only one quarter remains
SELECT
    'FINAL QUARTER CHECK' AS verification,
    CONCAT('Q',
           QUARTER(STR_TO_DATE(CONCAT('01-', REPLACE(REPLACE(month_year, '.', '-'), 'Feburary', 'February')), '%d-%M-%Y')),
           YEAR(STR_TO_DATE(CONCAT('01-', REPLACE(REPLACE(month_year, '.', '-'), 'Feburary', 'February')), '%d-%M-%Y'))
    ) AS Quarter,
    COUNT(*) AS row_count,
    COUNT(DISTINCT month_year) AS months_in_quarter
FROM bi_hcpcs_drug_pricing
GROUP BY Quarter;
