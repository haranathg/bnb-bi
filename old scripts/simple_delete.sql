-- Simple DELETE - keeps only the latest quarter
DELETE FROM bi_hcpcs_drug_pricing
WHERE CONCAT('Q',
             QUARTER(STR_TO_DATE(CONCAT('01-', REPLACE(REPLACE(month_year, '.', '-'), 'Feburary', 'February')), '%d-%M-%Y')),
             YEAR(STR_TO_DATE(CONCAT('01-', REPLACE(REPLACE(month_year, '.', '-'), 'Feburary', 'February')), '%d-%M-%Y'))
      ) != (
          SELECT CONCAT('Q',
                 QUARTER(MAX(STR_TO_DATE(CONCAT('01-', REPLACE(REPLACE(month_year, '.', '-'), 'Feburary', 'February')), '%d-%M-%Y'))),
                 YEAR(MAX(STR_TO_DATE(CONCAT('01-', REPLACE(REPLACE(month_year, '.', '-'), 'Feburary', 'February')), '%d-%M-%Y'))))
          FROM (SELECT month_year FROM bi_hcpcs_drug_pricing) AS t
      );

SELECT 'Cleanup complete' AS status, COUNT(*) AS remaining_rows FROM bi_hcpcs_drug_pricing;
