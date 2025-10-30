# Apache Superset lightweight image for Render (Hybrid Auth + AnalystLite Role)
FROM apache/superset:latest

COPY superset_config.py /app/pythonpath/superset_config.py

# Install Postgres driver inside Superset virtualenv
RUN /app/.venv/bin/pip install --no-cache-dir psycopg2-binary

ENV SUPERSET_HOME=/app/superset_home

EXPOSE 8088

# Initialize metadata DB, create custom role, and user, then start Superset
# Create AnalystLite role (Gamma + query save perms) and default user on boot
CMD ["bash", "-c", "superset db upgrade && \
  superset init && \
  superset fab create-role --name AnalystLite || true && \
  superset fab grant-role-perm --role AnalystLite --permission 'can dashboard' --view-menu Superset || true && \
  superset fab grant-role-perm --role AnalystLite --permission 'can explore' --view-menu Superset || true && \
  superset fab grant-role-perm --role AnalystLite --permission 'can explore json' --view-menu Superset || true && \
  superset fab grant-role-perm --role AnalystLite --permission 'can sql_json' --view-menu Superset || true && \
  superset fab grant-role-perm --role AnalystLite --permission 'can save query' --view-menu Superset || true && \
  superset fab create-user --username dashuser --firstname Dash --lastname User --email dashuser@example.com --password dashuser --role AnalystLite || true && \
  gunicorn -w 2 -b 0.0.0.0:8088 'superset.app:create_app()'"]
