#!/bin/bash
set -e

# --- 1. Default Variables (Resource Tuning) ---
# We define defaults for ALL variables used in postgresql.conf.template.
# These match the logic from your original implementation.

# Connections & Transactions
export PG_MAX_CONNECTIONS=${PG_MAX_CONNECTIONS:-150}
# Citus requirement: max_prepared_transactions must be >= max_connections
export PG_MAX_PREPARED_TRANSACTIONS=${PG_MAX_PREPARED_TRANSACTIONS:-150}

# Memory Settings
export PG_SHARED_BUFFERS=${PG_SHARED_BUFFERS:-128MB}
export PG_EFFECTIVE_CACHE_SIZE=${PG_EFFECTIVE_CACHE_SIZE:-512MB}
export PG_WORK_MEM=${PG_WORK_MEM:-4MB}
export PG_MAINTENANCE_WORK_MEM=${PG_MAINTENANCE_WORK_MEM:-64MB}

# Worker Processes (CPU related)
export PG_MAX_WORKER_PROCESSES=${PG_MAX_WORKER_PROCESSES:-8}
export PG_MAX_PARALLEL_WORKERS=${PG_MAX_PARALLEL_WORKERS:-8}

# --- 2. Citus Logic Variables ---
export PG_WORKER_REPLICAS=${PG_WORKER_REPLICAS:-0} # Default to 0 (Standalone/Worker mode)


echo "🔧 Generating postgresql.conf from template..."

# Validation: Check if template exists to avoid silent failures
if [ ! -f /etc/postgresql/postgresql.conf.template ]; then
    echo "❌ ERROR: /etc/postgresql/postgresql.conf.template not found!"
    exit 1
fi

# Apply variables
envsubst < /etc/postgresql/postgresql.conf.template > /etc/postgresql/postgresql.conf

echo "🐘 Starting Citus/Postgres..."
# Pass control to the official Docker entrypoint
exec /usr/local/bin/docker-entrypoint.sh postgres -c config_file=/etc/postgresql/postgresql.conf
