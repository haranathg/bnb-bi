# Apache Superset lightweight image for Render (Hybrid Auth + AnalystLite Role)
FROM apache/superset:latest

# Install compiler and system dependencies for packages like geohash, psycopg2
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential gcc g++ libpq-dev python3-dev \
    && rm -rf /var/lib/apt/lists/*

# Copy config and requirements
COPY superset_config.py /app/pythonpath/superset_config.py
COPY requirements.txt /app/requirements.txt

# Install python dependencies
RUN pip install --no-cache-dir -r /app/requirements.txt

ENV SUPERSET_HOME=/app/superset_home
EXPOSE 8088

# Start Superset
CMD ["bash", "-c", "superset db upgrade && superset init && superset fab create-role --name AnalystLite || true && superset fab grant-role-perm --role AnalystLite --permission 'can dashboard' --view-menu Superset || true && superset fab grant-role-perm --role AnalystLite --permission 'can explore' --view-menu Superset || true && superset fab grant-role-perm --role AnalystLite --permission 'can explore json' --view-menu Superset || true && superset fab grant-role-perm --role AnalystLite --permission 'can sql_json' --view-menu Superset || true && superset fab grant-role-perm --role AnalystLite --permission 'can save query' --view-menu Superset || true && superset fab create-user --username dashuser --firstname Dash --lastname User --email dashuser@example.com --password dashuser --role AnalystLite || true && gunicorn -w 2 -b 0.0.0.0:8088 'superset.app:create_app()'"]
