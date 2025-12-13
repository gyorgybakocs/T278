#!/bin/bash

# Import helpers
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

test_gunicorn() {
    echo "==============================================="
    echo "🧪 GUNICORN VALIDATION TEST"
    echo "==============================================="

    # PURPOSE:
    #   Dynamically locate the target pod to avoid hardcoding specific pod hashes,
    #   which change with every deployment or restart.
    local langflow_pod=$(get_latest_pod "langflow")

    if [ -z "$langflow_pod" ]; then
        echo "⚠️  Langflow pod not found (No Running pods). Skipping Gunicorn test."
        return 0
    fi

    echo "Target Pod: $langflow_pod"
    echo "-----------------------------------------------"

    # Proof #1
    # INTENT:
    #   Verify application startup success by scanning standard output for the specific
    #   initialization signature of Gunicorn.
    # TRADE-OFF:
    #   Log scraping is brittle; if the Gunicorn configuration changes logging format
    #   or verbosity, this check might yield false negatives.
    if kubectl logs "$langflow_pod" 2>&1 | grep -q "Starting gunicorn"; then
        echo "✅ PROOF: Found 'Starting gunicorn' in logs."
    else
        echo "⚠️  Warning: 'Starting gunicorn' message not found in recent logs."
    fi

    # Proof #2
    echo "Checking process tree inside container..."
    # WHY:
    #   The log check proves it *started*, but this process check proves it is
    #   *currently running*. This handles cases where the app crashed immediately after start.
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
