#!/bin/bash

# Import helpers
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

test_citus() {
    echo "==============================================="
    echo "🧪 TESTING CITUS SHARDING & DISTRIBUTION"
    echo "==============================================="

    local pg_pod=$(get_latest_pod "postgres-coordinator")

    if [ -z "$pg_pod" ]; then
        echo "❌ Postgres Coordinator pod not found!"
        return 1
    fi

    echo "Target Pod: $pg_pod"
    echo "-----------------------------------------------"

    # Helper function for running SQL inside the pod
    run_sql() {
        kubectl exec "$pg_pod" -- bash -c "export PGPASSWORD=\"\$POSTGRES_PASSWORD\"; psql -U \"\$POSTGRES_USER\" -d langflow_db -tA -c \"$1\""
    }

    echo -n "1️⃣  Checking Citus Extension... "
    local version=$(run_sql "SELECT citus_version();")
    if [[ $version == *"Citus"* ]]; then
        echo "✅ OK ($version)"
    else
        echo "❌ FAILED (Citus extension not found or not active)"
        return 1
    fi

    echo "-----------------------------------------------"
    echo "2️⃣  Verifying Distributed Tables (Sharding)"

    # Check specifically for expected distributed tables.
    # Since we haven't distributed them yet in init, this might return empty, which is expected at this stage unless initialized manually.
    local dist_tables=$(run_sql "SELECT table_name || ' (' || distribution_column || ')' FROM citus_tables;")

    echo "   Found distributed tables:"
    if [ -z "$dist_tables" ]; then
        echo "      (None found yet - normal if sharding init hasn't run)"
    else
        echo "$dist_tables" | sed 's/^/      -> /'
    fi

    echo "-----------------------------------------------"
    echo "3️⃣  Checking Active Workers"
    local worker_count=$(run_sql "SELECT count(*) FROM master_get_active_worker_nodes();")

    echo "   -> Active Workers found: $worker_count"

    if [ "$worker_count" -gt 0 ]; then
        echo "✅ OK: Workers are registered."
    else
        echo "❌ FAILED: No workers found! Cluster is not formed."
        return 1
    fi

    echo "-----------------------------------------------"
    echo "🎉 CITUS INFRASTRUCTURE CHECK PASSED!"
    echo "==============================================="
}

# Execute if run as a script
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    set -e
    test_citus
fi
