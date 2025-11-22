"""
Preset.io Dashboard Creation Script
Pharmaceutical Pricing Dashboard - Buy and Bill Report

This script works specifically with Preset.io (managed Superset)

Prerequisites:
- Preset.io account and workspace
- Database connection configured in Preset
- API credentials from Preset
"""

import requests
import json
from typing import Dict, List, Optional

class PresetDashboardBuilder:
    def __init__(self, workspace_url: str, api_token: str = None, 
                 username: str = None, password: str = None):
        """
        Initialize the Preset Dashboard Builder
        
        Args:
            workspace_url: Your Preset workspace URL (e.g., 'https://yourcompany.us1a.app.preset.io')
            api_token: Preset API token (preferred) OR
            username: Preset username (if not using token)
            password: Preset password (if not using token)
        """
        self.base_url = workspace_url.rstrip('/')
        self.session = requests.Session()
        self.access_token = None
        
        if api_token:
            # Use API token (Preset Team/Enterprise feature)
            self.session.headers.update({
                "Authorization": f"Bearer {api_token}",
                "Content-Type": "application/json"
            })
            print("✅ Using API token authentication")
        elif username and password:
            # Use username/password
            self._authenticate(username, password)
        else:
            raise Exception("Must provide either api_token OR username+password")
    
    def _authenticate(self, username: str, password: str):
        """Authenticate with username and password"""
        # Get CSRF token first
        csrf_response = self.session.get(f"{self.base_url}/api/v1/security/csrf_token/")
        if csrf_response.status_code == 200:
            csrf_token = csrf_response.json()['result']
            
            # Login
            login_data = {
                "username": username,
                "password": password,
                "provider": "db",
                "refresh": True
            }
            
            headers = {
                "Content-Type": "application/json",
                "X-CSRFToken": csrf_token
            }
            
            response = self.session.post(
                f"{self.base_url}/api/v1/security/login",
                json=login_data,
                headers=headers
            )
            
            if response.status_code == 200:
                self.access_token = response.json()['access_token']
                self.session.headers.update({
                    "Authorization": f"Bearer {self.access_token}",
                    "Content-Type": "application/json",
                    "X-CSRFToken": csrf_token
                })
                print("✅ Authentication successful")
            else:
                raise Exception(f"Authentication failed: {response.text}")
        else:
            raise Exception(f"Failed to get CSRF token: {csrf_response.text}")
    
    def get_database_id(self, database_name: str) -> Optional[int]:
        """Get database ID by name"""
        response = self.session.get(f"{self.base_url}/api/v1/database/")
        
        if response.status_code != 200:
            print(f"❌ Failed to fetch databases: {response.text}")
            return None
            
        result = response.json()
        databases = result.get('result', [])
        
        for db in databases:
            if db['database_name'] == database_name:
                print(f"✅ Found database: {database_name} (ID: {db['id']})")
                return db['id']
        
        print(f"❌ Database '{database_name}' not found")
        print(f"Available databases: {[db['database_name'] for db in databases]}")
        return None
    
    def list_databases(self):
        """List all available databases"""
        response = self.session.get(f"{self.base_url}/api/v1/database/")
        if response.status_code == 200:
            databases = response.json()['result']
            print("\n📁 Available Databases:")
            for db in databases:
                print(f"  - {db['database_name']} (ID: {db['id']})")
        else:
            print(f"❌ Failed to list databases: {response.text}")
    
    def create_dataset(self, database_id: int, table_name: str, 
                       schema: Optional[str] = None) -> Optional[int]:
        """Create a dataset from a database table"""
        dataset_data = {
            "database": database_id,
            "schema": schema,
            "table_name": table_name
        }
        
        response = self.session.post(
            f"{self.base_url}/api/v1/dataset/",
            json=dataset_data
        )
        
        if response.status_code in [200, 201]:
            dataset_id = response.json()['id']
            print(f"✅ Created dataset: {table_name} (ID: {dataset_id})")
            return dataset_id
        elif response.status_code == 422:
            # Dataset might already exist
            print(f"⚠️  Dataset {table_name} might already exist, searching...")
            return self._find_dataset_by_name(table_name)
        else:
            print(f"❌ Failed to create dataset {table_name}: {response.text}")
            return self._find_dataset_by_name(table_name)
    
    def _find_dataset_by_name(self, table_name: str) -> Optional[int]:
        """Find dataset ID by table name"""
        response = self.session.get(f"{self.base_url}/api/v1/dataset/")
        
        if response.status_code != 200:
            return None
            
        datasets = response.json()['result']
        
        for ds in datasets:
            if ds['table_name'] == table_name:
                print(f"✅ Found existing dataset: {table_name} (ID: {ds['id']})")
                return ds['id']
        return None
    
    def create_chart(self, chart_config: Dict) -> Optional[int]:
        """Create a chart with given configuration"""
        response = self.session.post(
            f"{self.base_url}/api/v1/chart/",
            json=chart_config
        )
        
        if response.status_code in [200, 201]:
            chart_id = response.json()['id']
            chart_name = chart_config.get('slice_name', 'Unknown')
            print(f"✅ Created chart: {chart_name} (ID: {chart_id})")
            return chart_id
        else:
            chart_name = chart_config.get('slice_name', 'Unknown')
            print(f"❌ Failed to create chart '{chart_name}': {response.text}")
            return None
    
    def create_dashboard(self, dashboard_name: str, chart_ids: List[int]) -> Optional[int]:
        """Create a dashboard with given charts"""
        # Build dashboard JSON with layout
        position_json = self._build_dashboard_layout(chart_ids)
        
        dashboard_data = {
            "dashboard_title": dashboard_name,
            "slug": dashboard_name.lower().replace(' ', '-').replace('_', '-'),
            "published": True,
            "position_json": json.dumps(position_json),
            "css": "",
            "json_metadata": json.dumps({
                "color_scheme": "supersetColors",
                "label_colors": {},
                "shared_label_colors": {}
            })
        }
        
        response = self.session.post(
            f"{self.base_url}/api/v1/dashboard/",
            json=dashboard_data
        )
        
        if response.status_code in [200, 201]:
            dashboard_id = response.json()['id']
            print(f"✅ Created dashboard: {dashboard_name} (ID: {dashboard_id})")
            return dashboard_id
        else:
            print(f"❌ Failed to create dashboard: {response.text}")
            return None
    
    def _build_dashboard_layout(self, chart_ids: List[int]) -> Dict:
        """Build dashboard position JSON for Preset/Superset"""
        position_json = {
            "DASHBOARD_VERSION_KEY": "v2",
            "ROOT_ID": {
                "type": "ROOT",
                "id": "ROOT_ID",
                "children": ["GRID_ID"]
            },
            "GRID_ID": {
                "type": "GRID",
                "id": "GRID_ID",
                "children": [],
                "parents": ["ROOT_ID"]
            }
        }
        
        # Add charts in rows
        row_height = 50  # Grid units
        chart_width = 12  # Full width (12 columns)
        y_position = 0
        
        for idx, chart_id in enumerate(chart_ids):
            chart_key = f"CHART-{chart_id}"
            row_key = f"ROW-{idx}"
            
            # Add row
            position_json[row_key] = {
                "type": "ROW",
                "id": row_key,
                "children": [chart_key],
                "parents": ["ROOT_ID", "GRID_ID"]
            }
            
            # Add chart
            position_json[chart_key] = {
                "type": "CHART",
                "id": chart_key,
                "children": [],
                "parents": [row_key, "ROOT_ID", "GRID_ID"],
                "meta": {
                    "width": chart_width,
                    "height": row_height,
                    "chartId": chart_id
                }
            }
            
            position_json["GRID_ID"]["children"].append(row_key)
            y_position += row_height
        
        return position_json


def create_preset_pharmaceutical_dashboard():
    """
    Main function to create the pharmaceutical pricing dashboard in Preset.io
    """
    
    print("="*70)
    print("PRESET.IO DASHBOARD SETUP")
    print("="*70)
    
    # Configuration - UPDATE THESE VALUES FOR YOUR PRESET WORKSPACE
    PRESET_WORKSPACE_URL = "https://c9a32755.us1a.app.preset.io"  # Change this!
    
    # Option 1: Use API Token (Preset Team/Enterprise)
    # Get token from: Settings → API Tokens
    PRESET_API_TOKEN = None  # "your-api-token-here"
    
    # Option 2: Use Username/Password (if no API token)
    USERNAME = "haranathg@gmail.com"  # Change this!
    PASSWORD = "h4r4P3dca!"  # Change this!
    
    # Your database name as it appears in Preset
    DATABASE_NAME = "MySql-bnb"  # Change this!
    SCHEMA = None  # Set if your database uses schemas
    
    print("\n⚠️  IMPORTANT: Update the configuration above before running!")
    print(f"Current workspace: {PRESET_WORKSPACE_URL}")
    print(f"Database to use: {DATABASE_NAME}")
    
    # Initialize builder
    try:
        if PRESET_API_TOKEN:
            builder = PresetDashboardBuilder(PRESET_WORKSPACE_URL, api_token=PRESET_API_TOKEN)
        else:
            builder = PresetDashboardBuilder(PRESET_WORKSPACE_URL, username=USERNAME, password=PASSWORD)
    except Exception as e:
        print(f"\n❌ Failed to authenticate: {e}")
        print("\nTroubleshooting:")
        print("1. Check your workspace URL is correct")
        print("2. Verify your username/password or API token")
        print("3. Make sure you have permission to create dashboards")
        return
    
    # List available databases
    print("\n" + "="*70)
    builder.list_databases()
    print("="*70)
    
    # Get database ID
    database_id = builder.get_database_id(DATABASE_NAME)
    if not database_id:
        print(f"\n❌ Cannot proceed without database connection")
        print(f"Please add your database in Preset: Settings → Database Connections")
        return
    
    # Create datasets
    print("\n📁 Creating datasets...")
    print("-"*70)
    
    datasets = {}
    tables_to_create = [
        ('consolidated', 'bi_consolidated_drug_data'),
        ('hist_asp', 'bi_historical_asp'),
        ('hist_wac', 'bi_historical_wac'),
        ('hist_awp', 'bi_historical_awp'),
        ('drug_class', 'bi_drug_class')
    ]
    
    for key, table_name in tables_to_create:
        dataset_id = builder.create_dataset(database_id, table_name, SCHEMA)
        if dataset_id:
            datasets[key] = dataset_id
        else:
            print(f"⚠️  Warning: Could not create/find dataset for {table_name}")
    
    if not datasets.get('consolidated'):
        print("\n❌ Critical: Could not create main consolidated dataset")
        print("Please verify the table 'bi_consolidated_drug_data' exists in your database")
        return
    
    # Create charts
    print("\n📊 Creating charts...")
    print("-"*70)
    
    chart_ids = []
    
    # Chart 1: Data Table
    if datasets.get('consolidated'):
        chart_1_config = {
            "slice_name": "Drug Pricing - Data Table",
            "viz_type": "table",
            "datasource_id": datasets['consolidated'],
            "datasource_type": "table",
            "params": json.dumps({
                "groupby": [
                    "HCPCS_Code",
                    "Brand_name",
                    "Manufacturer",
                    "ASP_per_Unit_Current_Quarter",
                    "ASP_per_Unit_Previous_Quarter",
                    "ASP_Quarterly_Change_Pct",
                    "product_category"
                ],
                "metrics": [],
                "adhoc_filters": [],
                "row_limit": 100,
                "order_desc": True
            })
        }
        chart_id = builder.create_chart(chart_1_config)
        if chart_id:
            chart_ids.append(chart_id)
    
    # Chart 2: ASP Quarterly Change
    if datasets.get('consolidated'):
        chart_2_config = {
            "slice_name": "ASP Quarterly % Change",
            "viz_type": "dist_bar",
            "datasource_id": datasets['consolidated'],
            "datasource_type": "table",
            "params": json.dumps({
                "metrics": [{
                    "expressionType": "SIMPLE",
                    "column": {"column_name": "ASP_Quarterly_Change_Pct"},
                    "aggregate": "AVG",
                    "label": "ASP Change %"
                }],
                "groupby": ["Brand_name"],
                "row_limit": 20,
                "order_desc": True
            })
        }
        chart_id = builder.create_chart(chart_2_config)
        if chart_id:
            chart_ids.append(chart_id)
    
    # Chart 3: ASP Ratios
    if datasets.get('consolidated'):
        chart_3_config = {
            "slice_name": "ASP Ratios - WAC and AWP",
            "viz_type": "dist_bar",
            "datasource_id": datasets['consolidated'],
            "datasource_type": "table",
            "params": json.dumps({
                "metrics": [
                    {
                        "expressionType": "SIMPLE",
                        "column": {"column_name": "ASP_WAC_Ratio"},
                        "aggregate": "AVG",
                        "label": "ASP/WAC"
                    },
                    {
                        "expressionType": "SIMPLE",
                        "column": {"column_name": "ASP_AWP_Ratio"},
                        "aggregate": "AVG",
                        "label": "ASP/AWP"
                    }
                ],
                "groupby": ["Brand_name"],
                "row_limit": 20
            })
        }
        chart_id = builder.create_chart(chart_3_config)
        if chart_id:
            chart_ids.append(chart_id)
    
    # Chart 4: ASP History
    if datasets.get('hist_asp'):
        chart_4_config = {
            "slice_name": "ASP Historical Trends",
            "viz_type": "line",
            "datasource_id": datasets['hist_asp'],
            "datasource_type": "table",
            "params": json.dumps({
                "metrics": [{
                    "expressionType": "SIMPLE",
                    "column": {"column_name": "asp"},
                    "aggregate": "AVG",
                    "label": "ASP"
                }],
                "groupby": ["HCPCS_Code"],
                "granularity_sqla": "Date",
                "time_range": "Last year"
            })
        }
        chart_id = builder.create_chart(chart_4_config)
        if chart_id:
            chart_ids.append(chart_id)
    
    # Chart 5: WAC History
    if datasets.get('hist_wac'):
        chart_5_config = {
            "slice_name": "WAC Historical Trends",
            "viz_type": "line",
            "datasource_id": datasets['hist_wac'],
            "datasource_type": "table",
            "params": json.dumps({
                "metrics": [{
                    "expressionType": "SIMPLE",
                    "column": {"column_name": "Median_WAC"},
                    "aggregate": "AVG",
                    "label": "WAC"
                }],
                "groupby": ["HCPCS_Code"],
                "granularity_sqla": "Date",
                "time_range": "Last year"
            })
        }
        chart_id = builder.create_chart(chart_5_config)
        if chart_id:
            chart_ids.append(chart_id)
    
    # Chart 6: AWP History
    if datasets.get('hist_awp'):
        chart_6_config = {
            "slice_name": "AWP Historical Trends",
            "viz_type": "line",
            "datasource_id": datasets['hist_awp'],
            "datasource_type": "table",
            "params": json.dumps({
                "metrics": [{
                    "expressionType": "SIMPLE",
                    "column": {"column_name": "Median_AWP"},
                    "aggregate": "AVG",
                    "label": "AWP"
                }],
                "groupby": ["HCPCS_Code"],
                "granularity_sqla": "Date",
                "time_range": "Last year"
            })
        }
        chart_id = builder.create_chart(chart_6_config)
        if chart_id:
            chart_ids.append(chart_id)
    
    # Create dashboard
    if chart_ids:
        print("\n📋 Creating dashboard...")
        print("-"*70)
        dashboard_id = builder.create_dashboard(
            "Buy and Bill - Pharmaceutical Pricing",
            chart_ids
        )
        
        if dashboard_id:
            dashboard_url = f"{PRESET_WORKSPACE_URL}/superset/dashboard/{dashboard_id}/"
            print("\n" + "="*70)
            print("✅ SUCCESS! Dashboard created successfully!")
            print("="*70)
            print(f"\n🔗 Access your dashboard at:")
            print(f"   {dashboard_url}")
            print("\n📝 Next steps:")
            print("   1. Open the dashboard in Preset")
            print("   2. Add filters (HCPCS Code, Manufacturer, etc.)")
            print("   3. Arrange charts as needed")
            print("   4. Customize colors and formatting")
            print("   5. Share with your team!")
        else:
            print("\n❌ Failed to create dashboard")
    else:
        print("\n❌ No charts were created successfully")
        print("Please check the errors above and verify:")
        print("  - Database tables exist")
        print("  - Tables have data")
        print("  - Column names match your database")


if __name__ == "__main__":
    print("\n" + "="*70)
    print("PRESET.IO PHARMACEUTICAL PRICING DASHBOARD SETUP")
    print("="*70)
    print("\nThis script will create your dashboard in Preset.io")
    print("\n⚠️  Before running, update the configuration in the script:")
    print("   - PRESET_WORKSPACE_URL")
    print("   - USERNAME and PASSWORD (or API_TOKEN)")
    print("   - DATABASE_NAME")
    print("\n" + "="*70 + "\n")
    
    create_preset_pharmaceutical_dashboard()