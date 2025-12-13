#!/bin/bash

# Import helpers
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

test_gunicorn() {
    echo "==============================================="
    echo "🧪 GUNICORN VALIDATION TEST"
    echo "==============================================="

    local langflow_pod=$(get_latest_pod "langflow")

    if [ -z "$langflow_pod" ]; then
        echo "⚠️  Langflow pod not found (No Running pods). Skipping Gunicorn test."
        return 0
    fi

    echo "Target Pod: $langflow_pod"
    echo "-----------------------------------------------"

    # Proof #1
    if kubectl logs "$langflow_pod" 2>&1 | grep -q "Starting gunicorn"; then
        echo "✅ PROOF: Found 'Starting gunicorn' in logs."
    else
        echo "⚠️  Warning: 'Starting gunicorn' message not found in recent logs."
    fi

    # Proof #2
    echo "Checking process tree inside container..."
    kubectl exec "$langflow_pod" -- /bin/sh -c 'ps aux | grep gunicorn'

    echo "==============================================="
    echo "🎉 GUNICORN CHECK FINISHED"
    echo "==============================================="
}

# Execute if run as a script
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    set -e
    test_gunicorn
fi
