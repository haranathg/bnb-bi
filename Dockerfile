# -------------------------------------------------------------------
# Apache Superset on Render (Minimal & Stable)
# -------------------------------------------------------------------

# Use the prebuilt Superset image (already includes all deps)
FROM apache/superset:latest

# Switch to root to install Postgres client libs
USER root
RUN apt-get update && apt-get install -y --no-install-recommends \
    libpq-dev \
 && rm -rf /var/lib/apt/lists/*

# Back to non-root runtime user
USER superset

# Install psycopg2-binary into Superset's virtualenv (for Postgres connection)
RUN . /app/.venv/bin/activate && pip install --no-cache-dir psycopg2-binary

# Copy your Superset config file
COPY superset_config.py /app/pythonpath/superset_config.py
ENV PYTHONPATH="/app/pythonpath"

# Entry script for first-time init and run
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
