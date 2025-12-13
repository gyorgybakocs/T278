#!/bin/bash

# Import helpers
# INTENT:
#   Load shared utility functions (like get_latest_pod) to avoid code duplication across tests.
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

test_redis() {
    echo "==============================================="
    echo "🧪 TESTING REDIS FUNCTIONALITY"
    echo "==============================================="

    # PURPOSE:
    #   Dynamically identify the target Redis pod name.
    # WHY:
    #   Pod names in Kubernetes include random hashes (e.g., redis-7f8b9c...).
    #   Hardcoding names would break the test after every redeployment.
    local redis_pod=$(get_latest_pod "redis")

    if [ -z "$redis_pod" ]; then
        echo "❌ Redis pod not found (No Running pods found with component=redis)!"
        return 1
    fi

    echo "Target Pod: $redis_pod"

    echo -n "-> Writing key 'smoke_test_key' ... "
    # TRADE-OFF:
    #   We use `kubectl exec` to run redis-cli inside the container.
    #   This is slower than an external connection but proves that the container
    #   itself is healthy and the internal binary functions correctly,
    #   bypassing potential Service/Ingress misconfigurations.
    kubectl exec $redis_pod -- redis-cli -a redissecret set smoke_test_key "WORKS_PERFECTLY" > /dev/null
    echo "✅ OK"

    echo -n "-> Reading key 'smoke_test_key' ... "
    local result=$(kubectl exec $redis_pod -- redis-cli -a redissecret get smoke_test_key)

    # INTENT:
    #   Strict string equality check to validate data persistence/retrieval.
    if [ "$result" == "WORKS_PERFECTLY" ]; then
        echo "✅ OK (Value: $result)"
    else
        echo "❌ FAILED (Expected: WORKS_PERFECTLY, Got: $result)"
        return 1
    fi

    echo -n "-> Deleting key ... "
    # WHY:
    #   Cleanup is mandatory to prevent "state pollution". Leaving test keys
    #   could confuse administrators debugging the system later.
    kubectl exec $redis_pod -- redis-cli -a redissecret del smoke_test_key > /dev/null
    echo "✅ OK"

    echo "-----------------------------------------------"
    echo "🎉 REDIS TEST PASSED!"
    echo "==============================================="
}

# Execute if run as a script (not sourced)
# PATTERN:
#   Allows this file to be used both as a standalone executable script
#   and as a library sourced by a master test runner (test-system.sh).
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    set -e
    test_redis
fi
