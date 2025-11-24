-- =====================================================
-- CHECK: What formats exist in month_year field
-- =====================================================

SELECT
    month_year,
    LENGTH(month_year) AS length,
    COUNT(*) AS row_count
FROM bi_hcpcs_drug_pricing
GROUP BY month_year
ORDER BY row_count DESC
LIMIT 20;

-- Check for different patterns
SELECT
    'Has dot separator' AS pattern,
    COUNT(*) AS count
FROM bi_hcpcs_drug_pricing
WHERE month_year LIKE '%.%'

UNION ALL

SELECT
    'Has hyphen separator' AS pattern,
    COUNT(*) AS count
FROM bi_hcpcs_drug_pricing
WHERE month_year LIKE '%-%';
