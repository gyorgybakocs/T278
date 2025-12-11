#!/bin/bash
set -e

echo "==========================================================="
echo "⚙️  DYNAMIC RESOURCE CALCULATION"
echo "==========================================================="

# ==============================================================================
# 1. HARDWARE DETECTION
# ==============================================================================
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

# Calculates percentage of total RAM
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

    # Logic: Redis gets ~2% of Total RAM for caching
    local redis_mem_mb=$(calc_ram_percent 2)

    # For DBs, Request should equal Limit (Guaranteed QoS) to prevent OOM Kills
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