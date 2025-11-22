# bi_historical_pricing Table - Field Mapping Documentation

## Table Overview
The `bi_historical_pricing` table combines historical pricing data from three separate tables into a single unified structure for easier analysis and reporting.

## Source Tables
1. `bi_historical_asp` - Historical Average Sales Price data
2. `bi_historical_wac` - Historical Wholesale Acquisition Cost data
3. `bi_historical_awp` - Historical Average Wholesale Price data

---

## Field Mappings

### 1. HCPCS_Code
- **Data Type**: CHAR(100)
- **Source**: Unified from all three tables
  - `bi_historical_asp.HCPCS_Code`
  - `bi_historical_wac.HCPCS_Code`
  - `bi_historical_awp.HCPCS_Code`
- **Description**: Unique drug identifier (J-Code)
- **Logic**: All unique HCPCS codes from any of the three source tables are included
- **Example**: 'J0135', 'J9035'

### 2. quarter
- **Data Type**: CHAR(10)
- **Source**: Unified from all three tables
  - `bi_historical_asp.quarter`
  - `bi_historical_wac.quarter`
  - `bi_historical_awp.quarter`
- **Description**: Calendar quarter identifier
- **Format**: 'Q[1-4][YYYY]'
- **Example**: 'Q12024', 'Q32023'

### 3. date
- **Data Type**: DATE
- **Source**: Unified from all three tables
  - `bi_historical_asp.Date`
  - `bi_historical_wac.Date`
  - `bi_historical_awp.Date`
- **Description**: Period start date (first day of the month)
- **Logic**: Derived from month_year field in cms_drug_pricing table
- **Example**: '2024-01-01', '2023-10-01'

### 4. asp
- **Data Type**: DECIMAL (rounded to 2 decimal places)
- **Source**: `bi_historical_asp.asp`
- **Original Source**: From cms_drug_pricing table
  - Uses `ASP_Override` if available and non-zero
  - Otherwise uses `ASP`
- **Description**: Average Sales Price per unit
- **Can be NULL**: Yes (if no ASP data available for this HCPCS/date combination)
- **Example**: 125.50, 1500.25

### 5. wac
- **Data Type**: DECIMAL (rounded to 2 decimal places)
- **Source**: `bi_historical_wac.Median_WAC`
- **Original Source**: `cms_drug_pricing.Current_WAC_Unit_Price`
- **Description**: Wholesale Acquisition Cost per unit
- **Can be NULL**: Yes (if no WAC data available for this HCPCS/date combination)
- **Example**: 150.00, 1750.80

### 6. awp
- **Data Type**: DECIMAL (rounded to 2 decimal places)
- **Source**: `bi_historical_awp.Median_AWP`
- **Original Source**: `cms_drug_pricing.Current_AWP_Unit_Price`
- **Description**: Average Wholesale Price per unit
- **Can be NULL**: Yes (if no AWP data available for this HCPCS/date combination)
- **Example**: 180.00, 2100.50

### 7. asp_wac_ratio
- **Data Type**: DECIMAL (rounded to 4 decimal places)
- **Source**: Calculated field
- **Formula**: `asp / wac`
- **Conditions**:
  - Only calculated when both asp and wac are NOT NULL
  - Only calculated when wac ≠ 0
  - Otherwise returns NULL
- **Description**: Ratio of ASP to WAC (shows relationship between sales price and wholesale cost)
- **Example**: 0.8367 (means ASP is 83.67% of WAC)

### 8. asp_awp_ratio
- **Data Type**: DECIMAL (rounded to 4 decimal places)
- **Source**: Calculated field
- **Formula**: `asp / awp`
- **Conditions**:
  - Only calculated when both asp and awp are NOT NULL
  - Only calculated when awp ≠ 0
  - Otherwise returns NULL
- **Description**: Ratio of ASP to AWP (shows relationship between sales price and wholesale price)
- **Example**: 0.6944 (means ASP is 69.44% of AWP)

### 9. has_asp
- **Data Type**: TINYINT (0 or 1)
- **Source**: Calculated field
- **Logic**:
  - `1` if asp IS NOT NULL
  - `0` if asp IS NULL
- **Description**: Indicator flag showing whether ASP data is available for this record
- **Use Case**: Useful for filtering or identifying data completeness

### 10. has_wac
- **Data Type**: TINYINT (0 or 1)
- **Source**: Calculated field
- **Logic**:
  - `1` if wac IS NOT NULL
  - `0` if wac IS NULL
- **Description**: Indicator flag showing whether WAC data is available for this record
- **Use Case**: Useful for filtering or identifying data completeness

### 11. has_awp
- **Data Type**: TINYINT (0 or 1)
- **Source**: Calculated field
- **Logic**:
  - `1` if awp IS NOT NULL
  - `0` if awp IS NULL
- **Description**: Indicator flag showing whether AWP data is available for this record
- **Use Case**: Useful for filtering or identifying data completeness

---

## Data Combination Logic

### UNION Approach
The table uses a UNION approach to combine all unique HCPCS_Code/Date/Quarter combinations from the three source tables:

```sql
all_periods AS (
    SELECT DISTINCT HCPCS_Code, Date, quarter
    FROM (
        SELECT HCPCS_Code, Date, quarter FROM bi_historical_asp
        UNION
        SELECT HCPCS_Code, Date, quarter FROM bi_historical_wac
        UNION
        SELECT HCPCS_Code, Date, quarter FROM bi_historical_awp
    ) combined
)
```

### LEFT JOIN Approach
Once all unique combinations are identified, the table performs LEFT JOINs to bring in pricing data:

- **Result**: Every HCPCS/Date combination from any source table gets a row
- **Benefit**: No data loss - even if a drug only has ASP but not WAC/AWP, it will still appear
- **Trade-off**: Some fields may be NULL if that pricing type isn't available for that period

---

## Indexes Created

1. **idx_hist_pricing_hcpcs**: Index on HCPCS_Code
   - Purpose: Fast lookups by drug code

2. **idx_hist_pricing_date**: Index on date
   - Purpose: Fast time-series queries

3. **idx_hist_pricing_quarter**: Index on quarter
   - Purpose: Fast quarterly aggregations

4. **idx_hist_pricing_composite**: Composite index on (HCPCS_Code, date)
   - Purpose: Optimized for queries filtering by both drug and time period

---

## Sample Record Examples

### Example 1: Complete Data
```
HCPCS_Code: J9035
quarter: Q12024
date: 2024-01-01
asp: 1250.50
wac: 1500.00
awp: 1800.00
asp_wac_ratio: 0.8337
asp_awp_ratio: 0.6947
has_asp: 1
has_wac: 1
has_awp: 1
```

### Example 2: Partial Data (Only ASP and WAC)
```
HCPCS_Code: J0135
quarter: Q32023
date: 2023-07-01
asp: 500.25
wac: 625.00
awp: NULL
asp_wac_ratio: 0.8004
asp_awp_ratio: NULL
has_asp: 1
has_wac: 1
has_awp: 0
```

### Example 3: Only WAC Available
```
HCPCS_Code: J2505
quarter: Q22023
date: 2023-04-01
asp: NULL
wac: 750.00
awp: NULL
asp_wac_ratio: NULL
asp_awp_ratio: NULL
has_asp: 0
has_wac: 1
has_awp: 0
```

---

## Common Query Patterns

### Get all pricing data for a specific drug
```sql
SELECT *
FROM bi_historical_pricing
WHERE HCPCS_Code = 'J9035'
ORDER BY date DESC;
```

### Get records with complete pricing data
```sql
SELECT *
FROM bi_historical_pricing
WHERE has_asp = 1 AND has_wac = 1 AND has_awp = 1;
```

### Quarterly price trends
```sql
SELECT quarter, AVG(asp) as avg_asp, AVG(wac) as avg_wac
FROM bi_historical_pricing
WHERE HCPCS_Code = 'J9035'
GROUP BY quarter
ORDER BY date;
```

---

## Data Quality Checks

### Recommended Validation Queries

1. **Check for orphaned dates** (dates in combined table not in source):
```sql
SELECT DISTINCT hp.HCPCS_Code, hp.date
FROM bi_historical_pricing hp
WHERE hp.has_asp = 0 AND hp.has_wac = 0 AND hp.has_awp = 0;
```

2. **Compare row counts**:
```sql
SELECT
    (SELECT COUNT(*) FROM bi_historical_asp) as asp_count,
    (SELECT COUNT(*) FROM bi_historical_wac) as wac_count,
    (SELECT COUNT(*) FROM bi_historical_awp) as awp_count,
    (SELECT COUNT(*) FROM bi_historical_pricing) as combined_count;
```

3. **Check ratio calculations**:
```sql
SELECT *
FROM bi_historical_pricing
WHERE asp IS NOT NULL
  AND wac IS NOT NULL
  AND wac != 0
  AND asp_wac_ratio IS NULL;
-- Should return 0 rows
```

---

## Notes

- All NULL values in pricing fields indicate that particular pricing type was not available for that HCPCS/date combination
- Ratios are only calculated when both components are available and denominator is non-zero
- The table is completely rebuilt each time `sp_refresh_bi_tables()` is called
- Sort order is by HCPCS_Code, then date (ascending)
