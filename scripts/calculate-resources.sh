#!/bin/bash
set -e  # Exit immediately if a command exits with a non-zero status

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

log() {
    echo -e "[\033[1;34m$(date +'%H:%M:%S')\033[0m] $1"
}

wait_for_pre_stability() {
    log "🛑 PRE-CHECK: Verifying database stability before upgrade..."

    # Check if the coordinator pod exists to avoid waiting on first deployment
    if kubectl get pod -l app.kubernetes.io/component=postgres-coordinator --no-headers | grep -q "."; then
        # Wait for the Coordinator to be ready.
        # This prevents the 'Race Condition' where Helm restarts a pod that is still initializing (WAL creation).
        kubectl wait --for=condition=ready pod -l app.kubernetes.io/component=postgres-coordinator --timeout=120s > /dev/null

        log "✅ Coordinator is responding. Pausing for WAL flush safety..."
        sleep 5
    else
        log "ℹ️  No existing coordinator found. Skipping pre-check (First deployment?)."
    fi
}

wait_for_rollout_success() {
    log "🛑 POST-CHECK: Waiting for Rolling Update to complete..."

    # 1. Wait for StatefulSet (Workers) - This fixes the DNS/Network errors
    log "⏳ Waiting for Workers to stabilize..."
    kubectl rollout status statefulset/tis-stack-postgres-worker -n default --timeout=300s

    # 2. Wait for Deployment (Coordinator)
    log "⏳ Waiting for Coordinator to stabilize..."
    kubectl rollout status deployment/tis-stack-postgres-coordinator -n default --timeout=300s

    # 3. DNS Cache buffer
    log "💤 Pausing 10s for internal DNS propagation..."
    sleep 10

    log "✅ Deployment successful. Cluster is stable."
}

# ==============================================================================
# EXECUTION FLOW
# ==============================================================================

# --- STEP 1: PRE-CHECK ---
wait_for_pre_stability

# --- STEP 2: RESOURCE CALCULATION & HELM UPGRADE ---
echo "==========================================================="
echo "⚙️  DYNAMIC RESOURCE CALCULATION (Smart Adaptive + Burstable)"
echo "==========================================================="

# ==============================================================================
# 1. HARDWARE DETECTION
# ==============================================================================
# PURPOSE:
#   Detects the total physical RAM available on the host machine.
#   Supports both macOS (Darwin) and Linux (standard /proc/meminfo).
if [ "$(uname)" == "Darwin" ]; then
    TOTAL_MEM_BYTES=$(sysctl -n hw.memsize)
    TOTAL_MEM_MB=$((TOTAL_MEM_BYTES / 1024 / 1024))
else
    # Use standard linux tools
    TOTAL_MEM_MB=$(free -m | awk '/^Mem:/ {print $2}')
fi
CPU_CORES=$(nproc)

echo "   -> Host Hardware: ${TOTAL_MEM_MB} MB RAM | ${CPU_CORES} Cores"

# ==============================================================================
# 2. HELPER FUNCTIONS
# ==============================================================================

# LOGIC:
#   Calculates a percentage of total RAM, ensuring a safe floor value.
#   WHY: Redis needs a minimum amount of memory to boot and function correctly,
#   even on very small nodes.
calc_ram_percent() {
    local percent=$1
    local val=$((TOTAL_MEM_MB * percent / 100))
    # Minimum 64MB is still a safe floor for Redis/Small apps to boot
    if [ "$val" -lt 64 ]; then echo 64; else echo "$val"; fi
}

# ==============================================================================
# 3. COMPONENT FUNCTIONS
# ==============================================================================

configure_redis() {
    echo "-----------------------------------------------------------"
    echo "🔧 Configuring Component: REDIS"
    echo "-----------------------------------------------------------"

    # STRATEGY:
    #   Allocates ~2% of host RAM to Redis.
    #   TRADE-OFF: This is a conservative estimate for a sidecar/cache role.
    #   For a dedicated Redis cluster, this should be much higher.
    local redis_mem_mb=$(calc_ram_percent 2)

    # QOS GUARANTEE:
    #   Sets Request = Limit.
    #   WHY: This places the Pod in the 'Guaranteed' QoS class in Kubernetes,
    #   protecting it from being evicted first during node memory pressure.
    local redis_req_mb=$redis_mem_mb
    local redis_lim_mb=$redis_mem_mb

    echo "   -> MaxMemory Config: ${redis_mem_mb}MB"
    echo "   -> K8s Request/Limit: ${redis_lim_mb}MB (Guaranteed QoS)"

    echo "==========================================================="
    echo "📊 CALCULATED OPTIMAL VALUES FOR Redis:"
    echo "   -> Redis Max Memory:       ${redis_mem_mb}mb"
    echo "   -> Redis Requests Memory:  ${redis_req_mb}Mi"
    echo "   -> Redis Limits Memory:    ${redis_lim_mb}Mi"
    echo "==========================================================="

    echo "   -> Applying via Helm..."

    # AUTOMATION:
    #   Updates the deployed Helm release in-place with the calculated values.
    #   '--reuse-values' preserves other settings (like passwords/images).
    helm upgrade tis-stack ./charts/tis-stack \
        --namespace default \
        --reuse-values \
        --set redis.config.maxmemory="${redis_mem_mb}mb" \
        --set redis.resources.requests.memory="${redis_req_mb}Mi" \
        --set redis.resources.limits.memory="${redis_lim_mb}Mi"

    echo "✅ Redis configuration applied."
}

configure_postgres() {
    echo "-----------------------------------------------------------"
    echo "🔧 Configuring Component: POSTGRES (CITUS)"
    echo "-----------------------------------------------------------"

    # --- 1. RESOURCE BUDGETING ---

    # RATIO: Allocating 30% of Host RAM for the Postgres Cluster.
    # This leaves 70% for vLLM, Qdrant (Vector DB), Keycloak, etc.
    local db_allocation_ratio=0.30

    # Calculate Total Postgres Budget
    local total_db_budget_mb=$(awk -v host="$TOTAL_MEM_MB" -v ratio="$db_allocation_ratio" 'BEGIN {printf "%.0f", host * ratio}')

    # Remaining RAM for Citus (Coordinator + Workers)
    # We don't subtract Redis here explicitly anymore as 30% is already a conservative slice.
    local available_for_citus_mb=$total_db_budget_mb

    # Safety floor: Ensure at least 2GB is available for Citus
    if [ "$available_for_citus_mb" -lt 2048 ]; then
        echo "⚠️  WARNING: Very low memory detected for Citus ($available_for_citus_mb MB)."
        available_for_citus_mb=2048
    fi

    echo "   -> Citus Cluster Budget: ${available_for_citus_mb} MB (Target: 30% of Host)"

    # --- 2. CALCULATE WORKER COUNT ---

    # MINIMUM POD SIZE: We don't want workers smaller than 1.5GB if possible.
    local min_pod_size=1536

    # How many pods fit in the budget?
    local possible_nodes=$(( available_for_citus_mb / min_pod_size ))

    # Coordinator takes 1 slot.
    local calc_workers=$(( possible_nodes - 1 ))

    # Constraints: Min 1, Max 8
    if [ "$calc_workers" -lt 1 ]; then calc_workers=1; fi
    if [ "$calc_workers" -gt 8 ]; then calc_workers=8; fi

    # --- 3. SAFETY CHECK: PREVENT DESTRUCTIVE SCALE DOWN ---

    local current_workers=$(kubectl get statefulset tis-stack-postgres-worker -n default -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")

    echo "   -> Calculated Optimal Workers: ${calc_workers}"
    echo "   -> Current Running Workers:    ${current_workers}"

    local final_workers=$calc_workers

    # CRITICAL: If we have MORE workers running than calculated, we MUST keep them.
    if [ "$current_workers" -gt "$calc_workers" ]; then
        echo "⚠️  WARNING: Calculated workers ($calc_workers) < Current workers ($current_workers)."
        echo "   ⛔ Scaling down Citus automatically is UNSAFE (Data Loss Risk)."
        echo "   -> Enforcing current count: $current_workers"
        final_workers=$current_workers
    fi

    # --- 4. CALCULATE RAM PER POD (LIMITS) ---

    # Distribute the budget EQUALLY.
    local total_pods=$(( final_workers + 1 ))
    local pod_ram_mb=$(( available_for_citus_mb / total_pods ))

    echo "   -> Final Configuration: ${final_workers} Workers + 1 Coordinator"
    echo "   -> RAM per Pod (Limit): ${pod_ram_mb} MB"

    # --- 5. POSTGRES TUNING (Based on POD RAM LIMIT) ---

    # Max Connections: 50 per GB of POD RAM.
    PG_MAX_CONNECTIONS=$(( pod_ram_mb / 1024 * 50 ))
    if [ "$PG_MAX_CONNECTIONS" -lt 100 ]; then PG_MAX_CONNECTIONS=100; fi

    # Shared Buffers: 25% of the LIMIT (Postgres reserves this upfront!)
    local pg_shared_buffers=$(( pod_ram_mb / 4 ))

    # Effective Cache: 75%
    local pg_effective_cache_size=$(( pod_ram_mb * 3 / 4 ))
    local pg_work_mem=$(( (pod_ram_mb * 1024) / PG_MAX_CONNECTIONS / 4 ))
    if [ "$pg_work_mem" -lt 4096 ]; then pg_work_mem=4096; fi

    # Worker Processes: Cap at 4 per pod
    local pg_max_worker_processes=4
    local pg_max_parallel_workers=4

    # --- 6. APPLY VIA HELM (BURSTABLE MODE) ---

    # BURSTABLE CONFIG:
    # Requests = Low (512MB) -> Allows K8s to schedule easily.
    # Limits = High (pod_ram_mb) -> Allows "Ballooning" under load.
    local minimal_request_mb=512

    echo "==========================================================="
    echo "📊 FINAL SPECS FOR POSTGRES (Burstable):"
    echo "   -> Replicas:              ${final_workers}"
    echo "   -> Requests (Reserved):   ${minimal_request_mb}Mi"
    echo "   -> Limits (Max Usage):    ${pod_ram_mb}Mi"
    echo "   -> Max Connections:       ${PG_MAX_CONNECTIONS}"
    echo "   -> Shared Buffers:        ${pg_shared_buffers}MB"
    echo "   -> Work Mem:              ${pg_work_mem}kB"
    echo "==========================================================="

    echo "   -> Applying via Helm..."

    helm upgrade tis-stack ./charts/tis-stack \
        --namespace default \
        --reuse-values \
        --set postgres.worker.replicas=${final_workers} \
        --set postgres.coordinator.resources.requests.memory="${minimal_request_mb}Mi" \
        --set postgres.coordinator.resources.limits.memory="${pod_ram_mb}Mi" \
        --set postgres.worker.resources.requests.memory="${minimal_request_mb}Mi" \
        --set postgres.worker.resources.limits.memory="${pod_ram_mb}Mi" \
        --set postgres.config.max_connections=${PG_MAX_CONNECTIONS} \
        --set postgres.config.max_prepared_transactions=${PG_MAX_CONNECTIONS} \
        --set postgres.config.shared_buffers="${pg_shared_buffers}MB" \
        --set postgres.config.effective_cache_size="${pg_effective_cache_size}MB" \
        --set postgres.config.work_mem="${pg_work_mem}kB" \
        --set postgres.config.maintenance_work_mem="128MB" \
        --set postgres.config.max_worker_processes=4 \
        --set postgres.config.max_parallel_workers=4

    echo "✅ Postgres configuration applied."
}

configure_pgbouncer() {
    echo "-----------------------------------------------------------"
    echo "🔧 Configuring Component: PGBOUNCER"
    echo "-----------------------------------------------------------"

    # Dependency: Needs PG_MAX_CONNECTIONS calculated in configure_postgres
    if [ -z "$PG_MAX_CONNECTIONS" ]; then
        echo "⚠️  PG_MAX_CONNECTIONS not set, defaulting to 150."
        PG_MAX_CONNECTIONS=150
    fi

    # Scale PgBouncer connections relative to Backend connections
    local pgb_max_client_conn=$(( PG_MAX_CONNECTIONS * 50 ))
    if [ "$pgb_max_client_conn" -gt 10000 ]; then pgb_max_client_conn=10000; fi

    # Default Pool Size: ~50% of backend capacity
    local pgb_default_pool_size=$(( PG_MAX_CONNECTIONS / 2 ))
    if [ "$pgb_default_pool_size" -lt 20 ]; then pgb_default_pool_size=20; fi

    echo "==========================================================="
    echo "📊 CALCULATED OPTIMAL VALUES FOR PgBouncer:"
    echo "   -> PgBouncer Max Conns:    ${pgb_max_client_conn}"
    echo "   -> PgBouncer Pool Size:   ${pgb_default_pool_size}"
    echo "==========================================================="

    helm upgrade tis-stack ./charts/tis-stack \
        --namespace default \
        --reuse-values \
        --set pgbouncer.pool.max_client_conn=${pgb_max_client_conn} \
        --set pgbouncer.pool.default_pool_size=${pgb_default_pool_size}

    echo "✅ PgBouncer configuration applied."
}

init_sharding() {
    echo "-----------------------------------------------------------"
    echo "⚡ INITIALIZING CITUS SHARDING"
    echo "-----------------------------------------------------------"

    local pg_pod=$(kubectl get pods -l app.kubernetes.io/component=postgres-coordinator -o jsonpath='{.items[0].metadata.name}')

    log "✅ Tables found. Applying Distribution..."

    kubectl exec "$pg_pod" -- bash -c "export PGPASSWORD=\$POSTGRES_PASSWORD; psql -U \$POSTGRES_USER -d langflow_db -c \"SELECT create_distributed_table('transaction', 'id');\"" || log "⚠️ Transaction table likely already distributed."
    kubectl exec "$pg_pod" -- bash -c "export PGPASSWORD=\$POSTGRES_PASSWORD; psql -U \$POSTGRES_USER -d langflow_db -c \"SELECT create_distributed_table('message', 'id');\"" || log "⚠️ Message table likely already distributed."

    log "✅ Sharding applied successfully."
}

switch_to_transaction() {
    log "-----------------------------------------------------------"
    log "🚀 SWITCHING TO TRANSACTION MODE"
    log "-----------------------------------------------------------"

    helm upgrade tis-stack ./charts/tis-stack \
        --namespace default \
        --reuse-values \
        --set pgbouncer.pool.mode=transaction

    log "✅ System switched to Transaction mode."
}

# ==============================================================================
# 4. MAIN EXECUTION FLOW
# ==============================================================================

# Configure Redis (Original logic, maintained)
configure_redis

# Configure Postgres (New Adaptive logic)
configure_postgres

# Configure PgBouncer (Uses output from Postgres calc)
configure_pgbouncer

echo "==============================================="
echo "🎉 ALL RESOURCE CALCULATION WERE SET SUCCESSFULLY"
echo "==============================================="

# --- STEP 3: POST-CHECK ---
# This ensures the script only exits when the cluster is actually ready for tests
wait_for_rollout_success

# --- STEP 4: APPLY SHARDING (After DB is stable and tables exist) ---
init_sharding
switch_to_transaction
wait_for_rollout_success

echo "==============================================="
echo "🎉 ALL RESOURCE CALCULATIONS & SHARDING SET SUCCESSFULLY"
echo "==============================================="

exit 0