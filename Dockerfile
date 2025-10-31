# -------------------------------------------------------------------
# Apache Superset on Render (stable, Render-friendly build)
# -------------------------------------------------------------------

# Use the official prebuilt Superset image with all frontend assets
FROM apache/superset:latest

# Switch to root to install system libraries if needed
USER root
RUN apt-get update && apt-get install -y --no-install-recommends \
    libpq-dev \
 && rm -rf /var/lib/apt/lists/*

# Switch back to non-root runtime user
USER superset

# -------------------------------------------------------------------
# Core Fix: install Postgres driver *inside* Superset’s own venv
# -------------------------------------------------------------------
RUN . /app/.venv/bin/activate && pip install --no-cache-dir psycopg2-binary

# -------------------------------------------------------------------
# Optional extra dependencies (your requirements.txt)
# -------------------------------------------------------------------
COPY requirements.txt /app/requirements.txt
RUN if [ -s /app/requirements.txt ]; then \
      . /app/.venv/bin/activate && \
      pip install --no-cache-dir -r /app/requirements.txt; \
    fi

# -------------------------------------------------------------------
# Superset configuration
# -------------------------------------------------------------------
COPY superset_config.py /app/pythonpath/superset_config.py
ENV PYTHONPATH="/app/pythonpath"

# -------------------------------------------------------------------
# Bootstrap script to initialize DB and create admin user on startup
# -------------------------------------------------------------------
RUN printf '%s\n' \
'#!/usr/bin/env bash' \
'set -euo pipefail' \
'echo "[entrypoint] Applying DB migrations..."' \
'superset db upgrade' \
'' \
'if [ -n "${SUPERSET_ADMIN_USERNAME:-}" ] && [ -n "${SUPERSET_ADMIN_PASSWORD:-}" ]; then' \
'  echo "[entrypoint] Ensuring admin user exists..."' \
'  superset fab create-admin \\' \
'    --username "$SUPERSET_ADMIN_USERNAME" \\' \
'    --firstname "${SUPERSET_ADMIN_FIRSTNAME:-Admin}" \\' \
'    --lastname "${SUPERSET_ADMIN_LASTNAME:-User}" \\' \
'    --email "${SUPERSET_ADMIN_EMAIL:-admin@example.com}" \\' \
'    --password "$SUPERSET_ADMIN_PASSWORD" || true' \
'fi' \
'' \
'echo "[entrypoint] Running superset init..."' \
'superset init' \
'' \
'echo "[entrypoint] Starting Superset on 0.0.0.0:${PORT:-8088}..."' \
'exec superset run -h 0.0.0.0 -p "${PORT:-8088}"' \
> /app/entrypoint.sh && chmod +x /app/entrypoint.sh

EXPOSE 8088
CMD ["/app/entrypoint.sh"]
