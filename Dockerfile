# -------------------------------------------------------------------
# Apache Superset on Render (Stable psycopg2 fix)
# -------------------------------------------------------------------

FROM apache/superset:latest

USER root

# Ensure Postgres libs present
RUN apt-get update && apt-get install -y --no-install-recommends \
    libpq-dev gcc python3-dev \
 && rm -rf /var/lib/apt/lists/*

# ✅ Install psycopg2-binary into Superset's virtualenv
RUN /app/.venv/bin/python -m ensurepip --upgrade && \
    /app/.venv/bin/python -m pip install --no-cache-dir --upgrade pip && \
    /app/.venv/bin/python -m pip install --no-cache-dir psycopg2-binary

# Superset config
COPY superset_config.py /app/pythonpath/superset_config.py
ENV PYTHONPATH="/app/pythonpath"

# Bootstrap script for migrations and first-run setup
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

USER superset

EXPOSE 8088
CMD ["/app/entrypoint.sh"]
