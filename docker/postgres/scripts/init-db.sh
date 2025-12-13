#!/bin/bash
set -euo pipefail

DB_USER="${POSTGRES_USER:-postgres}"
DB_PORT="${POSTGRES_PORT:-5432}"

# PGPASSWORD optional if local trust/socket auth is used during init;
# keep it if you want it for later phases.
export PGPASSWORD="${POSTGRES_PASSWORD:-}"

echo "⏳ [Init-DB] Waiting for local Postgres (socket) ($DB_USER) to accept connections..."
until pg_isready -p "$DB_PORT" -U "$DB_USER" >/dev/null 2>&1; do
  sleep 2
done

echo "🐘 [Init-DB] Postgres is up (socket). Starting database verification..."

if [ -z "${DB_LIST:-}" ]; then
  echo "⚠️  [Init-DB] DB_LIST is empty. No databases to create."
  exit 0
fi

for db in $DB_LIST; do
  echo "   -> Checking database: $db"
  EXISTS="$(psql -U "$DB_USER" -tAc "SELECT 1 FROM pg_database WHERE datname='${db}'" || true)"

  if [ "$EXISTS" = "1" ]; then
    echo "      ✅ Database '$db' already exists. Skipping creation."
  else
    echo "      🔨 Creating database '$db'..."
    psql -U "$DB_USER" -v ON_ERROR_STOP=1 -c "CREATE DATABASE \"${db}\";"
  fi

  echo "      ⚡ Ensuring Citus extension is enabled in '$db'..."
  psql -U "$DB_USER" -d "$db" -v ON_ERROR_STOP=1 -c "CREATE EXTENSION IF NOT EXISTS citus;"
done

echo "✅ [Init-DB] Initialization sequence finished."
