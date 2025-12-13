#!/bin/bash
set -euo pipefail

DB_USER="${POSTGRES_USER:-postgres}"
DB_PORT="${POSTGRES_PORT:-5432}"

# AUTHENTICATION:
#   We export PGPASSWORD to avoid interactive password prompts during init.
#   RISK: This variable should be unset after use in a more strictly secured environment,
#   though it's only process-local here.
export PGPASSWORD="${POSTGRES_PASSWORD:-}"

echo "⏳ [Init-DB] Waiting for local Postgres (socket) ($DB_USER) to accept connections..."
# HEALTH CHECK:
#   We loop until pg_isready returns success.
#   WHY: The standard /docker-entrypoint-initdb.d/ scripts run *while* the DB is starting up.
#   We must ensure the socket is fully ready before issuing CREATE DATABASE commands.
until pg_isready -p "$DB_PORT" -U "$DB_USER" >/dev/null 2>&1; do
  sleep 2
done

echo "🐘 [Init-DB] Postgres is up (socket). Starting database verification..."

# CONFIGURATION:
#   DB_LIST is injected from values.yaml (a space-separated string).
if [ -z "${DB_LIST:-}" ]; then
  echo "⚠️  [Init-DB] DB_LIST is empty. No databases to create."
  exit 0
fi

for db in $DB_LIST; do
  echo "   -> Checking database: $db"
  # IDEMPOTENCY:
  #   We check if the DB exists before trying to create it to prevent errors on restart.
  #   The standard 'CREATE DATABASE IF NOT EXISTS' syntax is not supported in standard SQL
  #   (it is a PL/pgSQL construct), so we check pg_database directly.
  EXISTS="$(psql -U "$DB_USER" -tAc "SELECT 1 FROM pg_database WHERE datname='${db}'" || true)"

  if [ "$EXISTS" = "1" ]; then
    echo "      ✅ Database '$db' already exists. Skipping creation."
  else
    echo "      🔨 Creating database '$db'..."
    psql -U "$DB_USER" -v ON_ERROR_STOP=1 -c "CREATE DATABASE \"${db}\";"
  fi

  echo "      ⚡ Ensuring Citus extension is enabled in '$db'..."
  # CITUS ACTIVATION:
  #   Crucial step: The Citus extension must be created in EVERY database that needs sharding.
  #   Installing it in 'postgres' template alone is sometimes insufficient if the DB was already created.
  psql -U "$DB_USER" -d "$db" -v ON_ERROR_STOP=1 -c "CREATE EXTENSION IF NOT EXISTS citus;"
done

echo "✅ [Init-DB] Initialization sequence finished."
