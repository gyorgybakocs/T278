#!/bin/bash

# Import helpers
# ROBUSTNESS:
#   Using "$(dirname "${BASH_SOURCE[0]}")" allows the script to be run from anywhere
#   (e.g., ./scripts/test-citus.sh or just ./test-citus.sh), maintaining the relative path to helpers.sh.
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

test_citus() {
    echo "==============================================="
    echo "🧪 TESTING CITUS SHARDING & DISTRIBUTION"
    echo "==============================================="

    # DISCOVERY:
    #   Uses the function defined in 'helpers.sh' to find the actual pod name.
    #   Crucial because the pod name changes with every deployment/restart.
    local pg_pod=$(get_latest_pod "postgres-coordinator")

    if [ -z "$pg_pod" ]; then
        echo "❌ Postgres Coordinator pod not found!"
        return 1
    fi

    echo "Target Pod: $pg_pod"
    echo "-----------------------------------------------"

    # Helper function for running SQL inside the pod
    # SECURITY & AUTOMATION:
    #   - We inject the password env var directly into the bash command inside the container.
    #   - We target 'langflow_db' specifically, assuming that's the main app DB.
    #   - '-tA': Tuples only (no headers) and unaligned, making parsing easier in bash.
    run_sql() {
        kubectl exec "$pg_pod" -- bash -c "export PGPASSWORD=\"\$POSTGRES_PASSWORD\"; psql -U \"\$POSTGRES_USER\" -d langflow_db -tA -c \"$1\""
    }

    echo -n "1️⃣  Checking Citus Extension... "
    # HEALTH CHECK:
    #   Simple query to verify if the extension is loaded in shared_preload_libraries
    #   and installed in the database.
    local version=$(run_sql "SELECT citus_version();")
    if [[ $version == *"Citus"* ]]; then
        echo "✅ OK ($version)"
    else
        echo "❌ FAILED (Citus extension not found or not active)"
        return 1
    fi

    echo "-----------------------------------------------"
    echo "2️⃣  Verifying Distributed Tables (Sharding)"

    # INTROSPECTION:
    #   Queries metadata to see if any tables have actually been distributed (sharded).
    #   This helps distinguish between a "running Citus node" and a "sharded application".
    local dist_tables=$(run_sql "SELECT table_name || ' (' || distribution_column || ')' FROM citus_tables;")

    echo "   Found distributed tables:"
    if [ -z "$dist_tables" ]; then
        echo "      (None found yet - normal if sharding init hasn't run)"
    else
        echo "$dist_tables" | sed 's/^/      -> /'
    fi

    echo "-----------------------------------------------"
    echo "3️⃣  Checking Active Workers"

    # DYNAMIC DISCOVERY: Get expected worker count from K8s via LABELS
    EXPECTED_WORKERS=$(kubectl get statefulset -l "app.kubernetes.io/component=postgres-worker" -o jsonpath='{.items[0].spec.replicas}' 2>/dev/null)

    if [ -z "$EXPECTED_WORKERS" ]; then EXPECTED_WORKERS=3; fi

    # Count registered workers (SQL Table Check)
    local worker_count=$(run_sql "SELECT count(*) FROM pg_dist_node WHERE noderole = 'primary';")
    if [ -z "$worker_count" ]; then worker_count=0; fi

    echo "   -> Active Workers found: $worker_count (Expected from K8s: $EXPECTED_WORKERS)"

    if [ "$worker_count" -ge "$EXPECTED_WORKERS" ]; then
        echo "✅ OK: All expected workers are registered."
    else
        echo "❌ FAILED: Mismatch in worker count! Found: $worker_count, Expected: $EXPECTED_WORKERS"
        return 1
    fi

    echo "-----------------------------------------------"
    echo "🎉 CITUS INFRASTRUCTURE CHECK PASSED!"
    echo "==============================================="
}

# Execute if run as a script
# MODULARITY:
#   Allows this file to be sourced by other scripts (like a main 'test-all.sh') without executing immediately,
#   OR run standalone as an executable.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    set -e
    test_citus
fi