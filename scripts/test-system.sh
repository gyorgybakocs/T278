#!/bin/bash
set -e

echo "======================================================="
echo "🚀 STARTING FULL SYSTEM VERIFICATION"
echo "======================================================="

SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"

# Source the test modules
source "$SCRIPT_DIR/test-redis.sh"
source "$SCRIPT_DIR/test-db.sh"
source "$SCRIPT_DIR/test-citus.sh"
# source "$SCRIPT_DIR/test-gunicorn.sh" # Not active yet

# --- EXECUTE TESTS ---

# 1. Redis Check
test_redis

# 2. Basic Database Check (CRUD)
test_db

# 3. Citus Infrastructure Check (Workers, Extension)
test_citus

echo ""
echo "======================================================="
echo "✅✅✅ ALL SYSTEM TESTS PASSED SUCCESSFULLY! ✅✅✅"
echo "======================================================="