# Power BI Data Consolidation - Implementation Guide

## Overview
This guide explains how to replace your current Excel-based Power BI data pipeline with a direct MySQL table connection.

## Current Architecture (Manual Process)
```
MySQL cms_drug_pricing table 
    → Export to Excel
    → Manual Excel formulas in "Data prep-bnb-pbi rpt-10.xlsx"
    → Create 5 separate Excel files:
        - Historical ASP File.xlsx
        - Historical WAC.xlsx
        - Historical AWP.xlsx
        - Drug Class.xlsx
        - Master.xlsx
    → Power BI imports all 5 Excel files
```

## New Architecture (Automated)
```
MySQL cms_drug_pricing table 
    → SQL script creates consolidated tables
    → Power BI connects directly to MySQL tables
```

## Database Tables Created

### 1. **bi_consolidated_drug_data** (Main Table)
This is the primary table that replaces the "Master" Excel file and combines data from multiple sources.

**Key Fields:**
- HCPCS_Code, Brand_name, Manufacturer
- ASP_per_Unit_Current_Quarter, ASP_per_Unit_Previous_Quarter
- Medicare_Payment_Limit
- ASP_Quarterly_Change_Pct
- Median_WAC_per_HCPCS_Unit, Median_AWP_per_HCPCS_Unit
- ASP_WAC_Ratio, ASP_AWP_Ratio
- WAC_AWP_Last_Change
- Time period fields (month_year, period_date)
- Product category and metadata fields

### 2. **bi_historical_asp** (Time Series Table)
Replaces "Historical ASP File.xlsx"

**Fields:**
- HCPCS_Code
- asp (ASP value)
- quarter (e.g., "Q42024")
- Date

### 3. **bi_historical_wac** (Time Series Table)
Replaces "Historical WAC.xlsx"

**Fields:**
- HCPCS_Code
- Median_WAC
- quarter
- Date

### 4. **bi_historical_awp** (Time Series Table)
Replaces "Historical AWP.xlsx"

**Fields:**
- HCPCS_Code
- Median_AWP
- quarter
- Date

### 5. **bi_drug_class** (Lookup Table)
Replaces "Drug Class.xlsx"

**Fields:**
- HCPCS_Code (Primary Key)
- General_Drug_Class
- Specialized_Drug_Class

## Implementation Steps

### Step 1: Run the SQL Script
```bash
mysql -u your_username -p your_database < create_powerbi_consolidated_table.sql
```

Or run it directly in MySQL Workbench/your preferred SQL client.

### Step 2: Populate the Drug Class Table
The drug class table needs to be populated from your Drug Class.xlsx file:

```sql
-- Option A: If you have a CSV export of Drug Class.xlsx
LOAD DATA LOCAL INFILE '/path/to/Drug_Class.csv' 
INTO TABLE bi_drug_class 
FIELDS TERMINATED BY ',' 
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(HCPCS_Code, General_Drug_Class, Specialized_Drug_Class);

-- Option B: Manual INSERT statements
INSERT INTO bi_drug_class (HCPCS_Code, General_Drug_Class, Specialized_Drug_Class)
VALUES 
('J0135', 'Oncology', 'Cancer Immunotherapy'),
('J9035', 'Oncology', 'Chemotherapy'),
-- ... etc
```

### Step 3: Update Power BI Data Sources

#### Replace Excel Connections with MySQL Connections

**For Main Data (Master sheet replacement):**
```powerquery
let
    Source = MySQL.Database("your_server", "your_database"),
    bi_consolidated_drug_data = Source{[Schema="your_database",Item="bi_consolidated_drug_data"]}[Data]
in
    bi_consolidated_drug_data
```

**For Historical ASP:**
```powerquery
let
    Source = MySQL.Database("your_server", "your_database"),
    bi_historical_asp = Source{[Schema="your_database",Item="bi_historical_asp"]}[Data]
in
    bi_historical_asp
```

**For Historical WAC:**
```powerquery
let
    Source = MySQL.Database("your_server", "your_database"),
    bi_historical_wac = Source{[Schema="your_database",Item="bi_historical_wac"]}[Data]
in
    bi_historical_wac
```

**For Historical AWP:**
```powerquery
let
    Source = MySQL.Database("your_server", "your_database"),
    bi_historical_awp = Source{[Schema="your_database",Item="bi_historical_awp"]}[Data]
in
    bi_historical_awp
```

**For Drug Class:**
```powerquery
let
    Source = MySQL.Database("your_server", "your_database"),
    bi_drug_class = Source{[Schema="your_database",Item="bi_drug_class"]}[Data]
in
    bi_drug_class
```

### Step 4: Verify Relationships in Power BI
Ensure these relationships exist in your Power BI model:
- bi_consolidated_drug_data[HCPCS_Code] ↔ bi_historical_asp[HCPCS_Code]
- bi_consolidated_drug_data[HCPCS_Code] ↔ bi_historical_wac[HCPCS_Code]
- bi_consolidated_drug_data[HCPCS_Code] ↔ bi_historical_awp[HCPCS_Code]
- bi_consolidated_drug_data[HCPCS_Code] ↔ bi_drug_class[HCPCS_Code]

## Data Refresh Strategy

### Option 1: Scheduled SQL Job (Recommended)
Create a MySQL event to automatically refresh the tables:

```sql
DELIMITER //

CREATE EVENT refresh_powerbi_tables
ON SCHEDULE EVERY 1 DAY
STARTS CURRENT_TIMESTAMP
DO
BEGIN
    -- Recreate tables with fresh data
    CALL create_powerbi_consolidated_table();
END //

DELIMITER ;
```

### Option 2: Manual Refresh
Run the SQL script manually whenever cms_drug_pricing is updated.

### Option 3: Power BI Gateway Refresh
Configure Power BI Gateway to refresh from MySQL on a schedule (hourly, daily, etc.)

## Key Calculations Implemented

### 1. ASP Handling
```sql
CASE 
    WHEN ASP_Override IS NOT NULL AND ASP_Override != 0 
    THEN ASP_Override
    ELSE ASP 
END AS ASP_Current
```

### 2. Quarterly Change Percentage
```sql
((Current_Quarter_ASP - Previous_Quarter_ASP) / Previous_Quarter_ASP) * 100
```

### 3. ASP/WAC Ratio
```sql
ASP_per_Unit_Current_Quarter / Median_WAC_per_HCPCS_Unit
```

### 4. ASP/AWP Ratio
```sql
ASP_per_Unit_Current_Quarter / Median_AWP_per_HCPCS_Unit
```

### 5. WAC/AWP Last Change Date
```sql
GREATEST(WAC_Effect_Date, AWP_Effect_Date)
```

## Performance Optimizations

The SQL script includes several indexes for optimal Power BI query performance:
- HCPCS_Code indexes on all tables (primary lookup)
- Manufacturer index (for filtering)
- Period_date indexes (for time-based filtering)
- Brand_name index (for search functionality)
- Product_category index (for category filtering)

## Advantages of This Approach

1. **Eliminates Manual Steps**: No more Excel exports and formula management
2. **Real-Time Data**: Power BI can refresh directly from MySQL
3. **Data Consistency**: Single source of truth, no Excel version conflicts
4. **Better Performance**: Direct SQL queries are faster than Excel processing
5. **Easier Maintenance**: Update logic in one SQL script vs. multiple Excel files
6. **Audit Trail**: data_refresh_timestamp shows when data was last updated
7. **Scalability**: Can handle larger datasets than Excel

## Troubleshooting

### Issue: Column names don't match in Power BI
**Solution:** Update your Power BI visualizations to use the new column names from the SQL tables.

### Issue: Historical data looks different
**Solution:** Verify the quarter calculation logic in the SQL script matches your Excel formulas.

### Issue: Missing data for certain HCPCS codes
**Solution:** Check the WHERE clauses in the SQL script - they filter out NULL values.

### Issue: Ratios showing NULL
**Solution:** This is expected when denominator is NULL or 0. The SQL script handles division by zero.

## Column Mapping (Old vs New)

### Master.xlsx → bi_consolidated_drug_data
| Excel Column | SQL Column |
|--------------|------------|
| HCPCS Code | HCPCS_Code |
| Brand name | Brand_name |
| Concat | Concat |
| Manufacturer | Manufacturer |
| ASP per Unit Previous Quarter | ASP_per_Unit_Previous_Quarter |
| ASP per Unit Current Quarter | ASP_per_Unit_Current_Quarter |
| Medicare Payment Limit | Medicare_Payment_Limit |
| ASP Quarterly Change % | ASP_Quarterly_Change_Pct |
| Median WAC per HCPCS Unit | Median_WAC_per_HCPCS_Unit |
| Median AWP per HCPCS Unit | Median_AWP_per_HCPCS_Unit |
| WAC/AWP (last change) | WAC_AWP_Last_Change |
| ASP/WAC Ratio | ASP_WAC_Ratio |
| ASP/AWP Ratio | ASP_AWP_Ratio |

## Maintenance Schedule

**Weekly:**
- Verify data refresh is working
- Check for new HCPCS codes

**Monthly:**
- Review Drug Class mappings
- Update any business logic changes

**Quarterly:**
- Validate ASP quarterly calculations
- Review data quality and completeness

## Contact & Support

For issues or questions:
- Check MySQL logs for SQL execution errors
- Verify cms_drug_pricing table has current data
- Review Power BI Gateway connection status
- Ensure MySQL user has proper permissions

## Next Steps

1. ✅ Run the SQL script to create tables
2. ✅ Populate bi_drug_class table
3. ✅ Update Power BI data sources
4. ✅ Test report functionality
5. ✅ Set up automated refresh schedule
6. ✅ Archive old Excel files (keep as backup initially)
7. ✅ Document any custom report modifications needed
