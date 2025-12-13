#!/bin/bash

# Import helpers
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

test_db() {
    echo "==============================================="
    echo "🧪 TESTING POSTGRES (COORDINATOR) FLOW"
    echo "==============================================="

    # PURPOSE:
    #   Isolate the database process verification from service discovery issues.
    #   We target the Pod directly rather than the Service IP to confirm the
    #   Postgres process itself is healthy, regardless of K8s networking state.
    local client_pod=$(get_latest_pod "postgres-coordinator")
    local db_name="langflow_db"
    # TRADE-OFF:
    #   Using a timestamp-based suffix avoids collisions if multiple tests run in parallel,
    #   though this script is currently designed for sequential execution.
    local test_table="smoke_test_$(date +%s)"
    local test_value="InitTest_$(date +%s)"

    if [ -z "$client_pod" ]; then
        echo "❌ Coordinator pod not found (No Running pods)!"
        return 1
    fi

    echo "Client Pod: $client_pod"

    echo "-----------------------------------------------"
    echo "🔍 DIAGNOSTICS: Listing Databases & Tables"
    echo "-----------------------------------------------"

    # 1. List all databases
    # INTENT:
    #   Verify that the bootstrap phase successfully created the expected databases
    #   (e.g., langflow_db) before attempting strictly typed operations.
    echo "Available Databases:"
    kubectl exec $client_pod -- bash -c "
        export PGPASSWORD=\"\$POSTGRES_PASSWORD\";
        psql -U \"\$POSTGRES_USER\" -d postgres -c '\l'
    "

    # 2. List tables in the target database
    echo "-----------------------------------------------"
    echo "Tables in $db_name:"
    kubectl exec $client_pod -- bash -c "
        export PGPASSWORD=\"\$POSTGRES_PASSWORD\";
        psql -U \"\$POSTGRES_USER\" -d $db_name -c '\dt' || echo '⚠️  Database $db_name does not exist or is not accessible.'
    "

    echo "-----------------------------------------------"
    echo "1️⃣  Writing to POSTGRES COORDINATOR (Port: 5432)"
    # TRADE-OFF:
    #   Directly accessing the Coordinator (Port 5432) bypasses any potential PgBouncer
    #   or load balancer layer. This ensures we are testing the storage engine,
    #   not the middleware.
    kubectl exec $client_pod -- bash -c "
        export PGPASSWORD=\"\$POSTGRES_PASSWORD\";
        psql -U \"\$POSTGRES_USER\" -h localhost -p 5432 -d $db_name -c \"
            CREATE TABLE IF NOT EXISTS $test_table (id SERIAL PRIMARY KEY, val TEXT);
            INSERT INTO $test_table (val) VALUES ('$test_value');
        \"
    "
    if [ $? -eq 0 ]; then echo "✅ Write success."; else echo "❌ Write failed."; return 1; fi

    echo "-----------------------------------------------"
    echo "2️⃣  Reading directly from POSTGRES (Localhost, Port: 5432)"
    # RISK:
    #   This check implies strong consistency. If we were testing a read-replica here,
    #   we might encounter replication lag. Since this is the Coordinator, immediate
    #   consistency is expected.
    local read_val=$(kubectl exec $client_pod -- bash -c "
        export PGPASSWORD=\"\$POSTGRES_PASSWORD\";
        psql -U \"\$POSTGRES_USER\" -h localhost -p 5432 -d $db_name -tA -c \"
            SELECT val FROM $test_table WHERE val = '$test_value';
        \"
    ")

    echo "   -> Wrote: $test_value"
    echo "   -> Read:  $read_val"

    if [ "$read_val" == "$test_value" ]; then
        echo "✅ Data consistency verified!"
    else
        echo "❌ Data mismatch! Persistence failed."
        return 1
    fi

    echo "-----------------------------------------------"
    echo "🧹 Cleaning up test table..."
    # WHY:
    #   Leaving test tables pollutes the schema and can confuse future manual debugging.
    #   We drop the specific ephemeral table created for this run.
    kubectl exec $client_pod -- bash -c "
        export PGPASSWORD=\"\$POSTGRES_PASSWORD\";
        psql -U \"\$POSTGRES_USER\" -h localhost -p 5432 -d $db_name -c \"DROP TABLE $test_table;\"
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
