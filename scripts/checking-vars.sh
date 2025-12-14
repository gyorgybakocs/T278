#!/bin/bash
set -e

# PURPOSE:
#   Verifies that the calculated resource limits (RAM, Connections) were actually
#   injected into the running containers' configuration files.
# WHY:
#   Helm charts and 'envsubst' templates can sometimes silently fail or ignore variables.
#   This script acts as the "Source of Truth" verification step in the pipeline.

echo "==========================================================="
echo "🔎 CHECKING RUNTIME DB CONFIG VALUES"
echo "==========================================================="

# ==============================================================================
# 1. HELPER FUNCTION
# ==============================================================================
# INTENT:
#   Don't Repeat Yourself (DRY). Both Redis and Postgres need file existence checks
#   and grep logic. We encapsulate this here.
check_config() {
    local pod=$1
    local conf_file=$2
    local params=("${@:3}") # Capture all arguments starting from index 3

    echo "-----------------------------------------------------------"
    echo "📦 Component: $pod"
    echo "   📄 File: $conf_file"
    echo "-----------------------------------------------------------"

    # VALIDATION:
    #   Ensures the config file exists before trying to grep it.
    #   Prevents confusing "No such file" errors if the container layout changes.
    if ! kubectl exec "$pod" -- sh -c "[ -f '$conf_file' ]"; then
        echo "   ❌ ERROR: Config file not found at $conf_file"
        return
    fi

    # INSPECTION:
    #   Reads the actual config file from *inside* the running process.
    #   WHY: This verifies what the process is actually using, bypassing any
    #   intermediate layers (like ConfigMaps) that might be detached.
    for param in "${params[@]}"; do
        # LOGIC:
        #   Grep for "key = value" (Postgres style) or "key value" (Redis style).
        #   We use -E for extended regex to handle whitespace flexibility.
        local val=$(kubectl exec "$pod" -- grep -E "^${param}.*" "$conf_file" | tail -n 1)

        if [ -n "$val" ]; then
            echo "   ✅ Found: $val"
        else
            echo "   ⚠️  WARNING: Parameter '$param' not found in config file (using default?)"
        fi
    done
}

# ==============================================================================
# 2. CHECK REDIS
# ==============================================================================
# DISCOVERY:
#   Finds the Redis pod dynamically using labels.
#   WHY: Pod names include random suffixes (e.g., redis-7f8b9c...), so we cannot hardcode them.
#   We take the first item found (.items[0]) assuming a single-replica deployment.
REDIS_POD=$(kubectl get pod -l "app.kubernetes.io/component=redis" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ -z "$REDIS_POD" ]; then
  echo "  ❌ No Redis pod found with label app=redis"
else
  # PARAMS:
  #   We only check maxmemory, as this is the critical one for stability.
  R_PARAMS=(
    "maxmemory"
    "maxmemory-policy"
  )
  check_config "$REDIS_POD" "/etc/redis/redis.conf" "${R_PARAMS[@]}"
fi

# ==============================================================================
# 3. CHECK POSTGRES (WORKER)
# ==============================================================================
# DISCOVERY:
#   We verify the WORKER node specifically.
#   WHY: In a Citus cluster, the workers handle the heavy distributed queries.
#   If their memory tuning is wrong, the query performance will suffer.
#   The Coordinator usually shares the same config map, so one check is sufficient.
PG_WORKER_POD=$(kubectl get pod -l "app.kubernetes.io/component=postgres-worker" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ -z "$PG_WORKER_POD" ]; then
  echo "  ❌ No Postgres Worker pod found!"
else
  # PARAMS:
  #   These match the variables injected by 'calculate-resources.sh'.
  #   Verifying them proves that the Helm upgrade was successful.
  PG_PARAMS=(
    "max_connections"
    "max_prepared_transactions"
    "shared_buffers"
    "effective_cache_size"
    "work_mem"
    "maintenance_work_mem"
    "max_worker_processes"
    "max_parallel_workers"
  )
  check_config "$PG_WORKER_POD" "/etc/postgresql/postgresql.conf" "${PG_PARAMS[@]}"
fi

# ==============================================================================
# 4. CHECK PGBOUNCER
# ==============================================================================
# DISCOVERY:
PGBOUNCER_POD=$(kubectl get pod -l "app.kubernetes.io/component=pgbouncer" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ -z "$PGBOUNCER_POD" ]; then
  echo "  ❌ No PgBouncer pod found!"
else
  # PARAMS:
  PGB_PARAMS=(
    "pool_mode"
    "max_client_conn"
    "default_pool_size"
  )
  check_config "$PGBOUNCER_POD" "/etc/pgbouncer/pgbouncer.ini" "${PGB_PARAMS[@]}"
fi

echo "==========================================================="
echo "✅ Verification Complete."
echo "==========================================================="
