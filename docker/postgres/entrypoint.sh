#!/bin/bash
set -e

# --- 1. Default Variables (Resource Tuning) ---
# FALLBACK STRATEGY:
#   We use parameter expansion (:-default) to set safe defaults if environment variables are missing.
#   WHY: This allows the container to start standalone (e.g., 'docker run') without crashing due to
#   missing config values, while still respecting overrides from Kubernetes ConfigMaps.

# Connections & Transactions
export PG_MAX_CONNECTIONS=${PG_MAX_CONNECTIONS:-150}
# CITUS REQUIREMENT:
#   'max_prepared_transactions' must be at least equal to 'max_connections'.
#   WHY: Citus uses 2PC (Two-Phase Commit) for distributed transactions across workers.
#   If this value is too low, distributed writes will fail.
export PG_MAX_PREPARED_TRANSACTIONS=${PG_MAX_PREPARED_TRANSACTIONS:-150}

# Memory Settings
# TUNING:
#   These defaults are relatively conservative (suited for dev/small instances).
#   Production deployments should override these via Helm values based on actual node RAM.
export PG_SHARED_BUFFERS=${PG_SHARED_BUFFERS:-128MB}
export PG_EFFECTIVE_CACHE_SIZE=${PG_EFFECTIVE_CACHE_SIZE:-512MB}
export PG_WORK_MEM=${PG_WORK_MEM:-4MB}
export PG_MAINTENANCE_WORK_MEM=${PG_MAINTENANCE_WORK_MEM:-64MB}

# Worker Processes (CPU related)
export PG_MAX_WORKER_PROCESSES=${PG_MAX_WORKER_PROCESSES:-8}
export PG_MAX_PARALLEL_WORKERS=${PG_MAX_PARALLEL_WORKERS:-8}

# --- 2. Citus Logic Variables ---
# ROLE DEFINITION:
#   Defaults to 0, which implies a worker node or standalone instance.
#   The Coordinator deployment explicitly sets this to the number of workers to wait for.
export PG_WORKER_REPLICAS=${PG_WORKER_REPLICAS:-0}


echo "🔧 Generating postgresql.conf from template..."

# VALIDATION:
#   Fail fast if the template is missing. This prevents the database from starting
#   with a default (unoptimized) config silently, which could hide deployment errors.
if [ ! -f /etc/postgresql/postgresql.conf.template ]; then
    echo "❌ ERROR: /etc/postgresql/postgresql.conf.template not found!"
    exit 1
fi

# TEMPLATING:
#   Uses 'envsubst' to replace ${VAR} placeholders in the template with actual env values.
#   This generates the final postgresql.conf used by the server.
envsubst < /etc/postgresql/postgresql.conf.template > /etc/postgresql/postgresql.conf

echo "🐘 Starting Citus/Postgres..."
# HANDOFF:
#   We use 'exec' to replace the current shell process with the postgres process.
#   WHY: This ensures Postgres becomes PID 1, receiving Unix signals (SIGTERM/SIGINT) correctly
#   for graceful shutdowns. Without 'exec', signals might be swallowed by the shell.
exec /usr/local/bin/docker-entrypoint.sh postgres -c config_file=/etc/postgresql/postgresql.conf
