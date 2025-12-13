#!/bin/bash
set -e

echo "==========================================================="
echo "⚙️  DYNAMIC RESOURCE CALCULATION"
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
    TOTAL_MEM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    TOTAL_MEM_MB=$((TOTAL_MEM_KB / 1024))
fi

echo "   -> Host Hardware: ${TOTAL_MEM_MB} MB RAM"

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
    # Minimum 64MB is still a safe floor for Redis to boot, but logic is percentage based.
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

# ==============================================================================
# 4. MAIN EXECUTION FLOW
# ==============================================================================

configure_redis

echo "==============================================="
echo "🎉 ALL RESOURCE CALCULATION WERE SET SUCCESSFULLY"
echo "==============================================="
