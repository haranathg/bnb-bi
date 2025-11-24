-- =====================================================
-- EXECUTE CLEANUP - Remove old quarters IMMEDIATELY
-- Keep ONLY the most recent quarter's data
-- =====================================================

-- Find the latest quarter
SET @max_quarter_date = (
    SELECT MAX(STR_TO_DATE(CONCAT('01-', REPLACE(REPLACE(month_year, '.', '-'), 'Feburary', 'February')), '%d-%M-%Y'))
    FROM bi_hcpcs_drug_pricing
);

SET @latest_quarter = CONCAT('Q', QUARTER(@max_quarter_date), YEAR(@max_quarter_date));

-- Show current state
SELECT
    'CURRENT STATE' AS info,
    COUNT(*) AS total_rows,
    COUNT(DISTINCT CONCAT('Q',
           QUARTER(STR_TO_DATE(CONCAT('01-', REPLACE(REPLACE(month_year, '.', '-'), 'Feburary', 'February')), '%d-%M-%Y')),
           YEAR(STR_TO_DATE(CONCAT('01-', REPLACE(REPLACE(month_year, '.', '-'), 'Feburary', 'February')), '%d-%M-%Y'))
    )) AS total_quarters,
    @latest_quarter AS latest_quarter
FROM bi_hcpcs_drug_pricing;

-- Show what will be kept
SELECT
    'ROWS TO KEEP' AS action,
    @latest_quarter AS quarter,
    COUNT(*) AS count
FROM bi_hcpcs_drug_pricing
WHERE CONCAT('Q',
             QUARTER(STR_TO_DATE(CONCAT('01-', REPLACE(REPLACE(month_year, '.', '-'), 'Feburary', 'February')), '%d-%M-%Y')),
             YEAR(STR_TO_DATE(CONCAT('01-', REPLACE(REPLACE(month_year, '.', '-'), 'Feburary', 'February')), '%d-%M-%Y'))
      ) = @latest_quarter;

-- Show what will be deleted
SELECT
    'ROWS TO DELETE' AS action,
    COUNT(*) AS count,
    COUNT(DISTINCT CONCAT('Q',
           QUARTER(STR_TO_DATE(CONCAT('01-', REPLACE(REPLACE(month_year, '.', '-'), 'Feburary', 'February')), '%d-%M-%Y')),
           YEAR(STR_TO_DATE(CONCAT('01-', REPLACE(REPLACE(month_year, '.', '-'), 'Feburary', 'February')), '%d-%M-%Y'))
    )) AS old_quarters
FROM bi_hcpcs_drug_pricing
WHERE CONCAT('Q',
             QUARTER(STR_TO_DATE(CONCAT('01-', REPLACE(REPLACE(month_year, '.', '-'), 'Feburary', 'February')), '%d-%M-%Y')),
             YEAR(STR_TO_DATE(CONCAT('01-', REPLACE(REPLACE(month_year, '.', '-'), 'Feburary', 'February')), '%d-%M-%Y'))
      ) != @latest_quarter;

-- *** EXECUTE THE DELETE ***
DELETE FROM bi_hcpcs_drug_pricing
WHERE CONCAT('Q',
             QUARTER(STR_TO_DATE(CONCAT('01-', REPLACE(REPLACE(month_year, '.', '-'), 'Feburary', 'February')), '%d-%M-%Y')),
             YEAR(STR_TO_DATE(CONCAT('01-', REPLACE(REPLACE(month_year, '.', '-'), 'Feburary', 'February')), '%d-%M-%Y'))
      ) != @latest_quarter;

-- Show final state
SELECT
    'FINAL STATE' AS info,
    COUNT(*) AS total_rows,
    COUNT(DISTINCT HCPCS_Code) AS unique_drugs,
    COUNT(DISTINCT CONCAT('Q',
           QUARTER(STR_TO_DATE(CONCAT('01-', REPLACE(REPLACE(month_year, '.', '-'), 'Feburary', 'February')), '%d-%M-%Y')),
           YEAR(STR_TO_DATE(CONCAT('01-', REPLACE(REPLACE(month_year, '.', '-'), 'Feburary', 'February')), '%d-%M-%Y'))
    )) AS total_quarters,
    MIN(month_year) AS earliest_month,
    MAX(month_year) AS latest_month
FROM bi_hcpcs_drug_pricing;

-- Verify only one quarter remains
SELECT
    'QUARTER VERIFICATION' AS check_type,
    CONCAT('Q',
           QUARTER(STR_TO_DATE(CONCAT('01-', REPLACE(REPLACE(month_year, '.', '-'), 'Feburary', 'February')), '%d-%M-%Y')),
           YEAR(STR_TO_DATE(CONCAT('01-', REPLACE(REPLACE(month_year, '.', '-'), 'Feburary', 'February')), '%d-%M-%Y'))
    ) AS Quarter,
    COUNT(*) AS row_count,
    COUNT(DISTINCT month_year) AS months_in_quarter,
    COUNT(DISTINCT HCPCS_Code) AS unique_drugs
FROM bi_hcpcs_drug_pricing
GROUP BY Quarter;
