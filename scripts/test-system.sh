#!/bin/bash
# INTENT:
#   Enable "Fail Fast" mode.
# WHY:
#   In a CI/CD or critical verification pipeline, any single failure (Redis, DB, etc.)
#   compromises the integrity of the entire stack. We want to stop immediately
#   rather than cascading errors or giving a false sense of partial success.
set -e

echo "======================================================="
echo "🚀 STARTING FULL SYSTEM VERIFICATION"
echo "======================================================="

# PURPOSE:
#   Resolve the absolute path of the script directory.
# TRADE-OFF:
#   Using `dirname` is safer than relying on relative paths (./scripts/...),
#   as it allows this script to be called from any location (e.g., root, or inside scripts/).
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"

# Source the test modules
# INTENT:
#   Import functions from other files into the current shell scope.
# WHY:
#   Sourcing is preferred over executing them as subprocesses because it allows
#   shared variables (if any) and ensures that `set -e` propagates correctly
#   across function calls without complex exit code handling.
source "$SCRIPT_DIR/test-redis.sh"
source "$SCRIPT_DIR/test-db.sh"
source "$SCRIPT_DIR/test-citus.sh"
# source "$SCRIPT_DIR/test-gunicorn.sh" # Not active yet: Gunicorn is not currently part of the critical path check.

# --- EXECUTE TESTS ---

# 1. Redis Check
# RISK:
#   Redis is often the fastest to boot. We test it first to get quick feedback
#   on basic connectivity before waiting for heavier DB migrations.
test_redis

# 2. Basic Database Check (CRUD)
# PURPOSE:
#   Validates that the Postgres Coordinator is accepting connections and writing data.
test_db

# 3. Citus Infrastructure Check (Workers, Extension)
# WHY:
#   This is the most complex check. It runs last because it depends on the
#   Coordinator being healthy (verified in step 2).
test_citus

echo ""
echo "======================================================="
echo "✅✅✅ ALL SYSTEM TESTS PASSED SUCCESSFULLY! ✅✅✅"
echo "======================================================="
