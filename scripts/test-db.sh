#!/bin/bash

# Import helpers
# INTENT: Load shared utility functions (like get_latest_pod) to ensure portability.
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

test_db() {
    echo "==============================================="
    echo "🧪 TESTING POSTGRES & PGBOUNCER FLOW"
    echo "==============================================="

    # 1. Define Target
    # We run the client (psql) inside the Coordinator pod, but target the PgBouncer Service.
    local client_pod=$(get_latest_pod "postgres-coordinator")
    local db_name="langflow_db"

    # Unique table and value for the test to avoid collisions
    local test_table="smoke_test_$(date +%s)"
    local test_value="InitTest_$(date +%s)"

    # Service name derived from Helm chart release name ('tis-stack')
    local pgbouncer_host="tis-stack-pgbouncer"
    local pgbouncer_port="6432"

    if [ -z "$client_pod" ]; then
        echo "❌ Coordinator pod not found (No Running pods)!"
        return 1
    fi

    echo "Client Pod: $client_pod"
    echo "Target Service: $pgbouncer_host:$pgbouncer_port"

    echo "-----------------------------------------------"
    echo "🔍 DIAGNOSTICS: Listing Databases"
    echo "-----------------------------------------------"

    # Diagnostics: List databases directly to ensure DB is up
    kubectl exec $client_pod -- bash -c "
        export PGPASSWORD=\"\$POSTGRES_PASSWORD\";
        psql -U \"\$POSTGRES_USER\" -d postgres -c '\l'
    "

    echo "-----------------------------------------------"
    echo "1️⃣  Writing via PGBOUNCER (Service: $pgbouncer_host, Port: $pgbouncer_port)"

    # CRITICAL: -h points to the PgBouncer Service (6432), not localhost.
    # This validates that PgBouncer is accepting connections and routing them correctly.
    kubectl exec $client_pod -- bash -c "
        export PGPASSWORD=\"\$POSTGRES_PASSWORD\";
        psql -U \"\$POSTGRES_USER\" -h $pgbouncer_host -p $pgbouncer_port -d $db_name -c \"
            CREATE TABLE IF NOT EXISTS $test_table (id SERIAL PRIMARY KEY, val TEXT);
            INSERT INTO $test_table (val) VALUES ('$test_value');
        \"
    "
    if [ $? -eq 0 ]; then
        echo "✅ Write via PgBouncer success."
    else
        echo "❌ Write failed via PgBouncer! (Is the service reachable? Check userlist.txt)"
        return 1
    fi

    echo "-----------------------------------------------"
    echo "2️⃣  Reading directly from POSTGRES (Localhost, Port: 5432)"

    # VERIFICATION: Read back directly from the DB storage (localhost:5432).
    # Finding the data here proves that PgBouncer successfully committed the transaction.
    local read_val=$(kubectl exec $client_pod -- bash -c "
        export PGPASSWORD=\"\$POSTGRES_PASSWORD\";
        psql -U \"\$POSTGRES_USER\" -h localhost -p 5432 -d $db_name -tA -c \"
            SELECT val FROM $test_table WHERE val = '$test_value';
        \"
    ")

    echo "   -> Wrote (via PgBouncer): $test_value"
    echo "   -> Read  (via Postgres):  $read_val"

    if [ "$read_val" == "$test_value" ]; then
        echo "✅ Data consistency verified!"
    else
        echo "❌ Data mismatch! Persistence failed."
        return 1
    fi

    echo "-----------------------------------------------"
    echo "🧹 Cleaning up test table (via PgBouncer)..."
    # Cleanup via PgBouncer to verify permission stability
    kubectl exec $client_pod -- bash -c "
        export PGPASSWORD=\"\$POSTGRES_PASSWORD\";
        psql -U \"\$POSTGRES_USER\" -h $pgbouncer_host -p $pgbouncer_port -d $db_name -c \"DROP TABLE $test_table;\"
    " > /dev/null
    echo "✅ Cleanup done."

    echo "==============================================="
    echo "🎉 DATABASE FLOW TEST PASSED!"
    echo "==============================================="
}

# Execute if run as a script
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    set -e
    test_db
fi
