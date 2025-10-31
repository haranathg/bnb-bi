# -------------------------------------------------------------------
# Apache Superset on Render (Minimal & Stable)
# -------------------------------------------------------------------
FROM apache/superset:latest

USER root
RUN apt-get update && apt-get install -y --no-install-recommends \
    libpq-dev \
 && rm -rf /var/lib/apt/lists/*

# ✅ Install psycopg2-binary *inside* Superset's venv
RUN /app/.venv/bin/pip install --no-cache-dir psycopg2-binary

# Superset configuration
COPY superset_config.py /app/pythonpath/superset_config.py
ENV PYTHONPATH="/app/pythonpath"

# Create entrypoint as root (has write access)
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

# Switch back to non-root runtime user
USER superset

EXPOSE 8088
CMD ["/app/entrypoint.sh"]
