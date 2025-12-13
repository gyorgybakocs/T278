#!/bin/bash

# Import helpers (works both standalone and sourced)
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

test_redis() {
    echo "==============================================="
    echo "🧪 TESTING REDIS FUNCTIONALITY"
    echo "==============================================="

    local redis_pod=$(get_latest_pod "redis")

    if [ -z "$redis_pod" ]; then
        echo "❌ Redis pod not found (No Running pods found with component=redis)!"
        return 1
    fi

    echo "Target Pod: $redis_pod"

    echo -n "-> Writing key 'smoke_test_key' ... "
    kubectl exec $redis_pod -- redis-cli -a redissecret set smoke_test_key "WORKS_PERFECTLY" > /dev/null
    echo "✅ OK"

    echo -n "-> Reading key 'smoke_test_key' ... "
    local result=$(kubectl exec $redis_pod -- redis-cli -a redissecret get smoke_test_key)

    if [ "$result" == "WORKS_PERFECTLY" ]; then
        echo "✅ OK (Value: $result)"
    else
        echo "❌ FAILED (Expected: WORKS_PERFECTLY, Got: $result)"
        return 1
    fi

    echo -n "-> Deleting key ... "
    kubectl exec $redis_pod -- redis-cli -a redissecret del smoke_test_key > /dev/null
    echo "✅ OK"

    echo "-----------------------------------------------"
    echo "🎉 REDIS TEST PASSED!"
    echo "==============================================="
}

# Execute if run as a script (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    set -e
    test_redis
fi
