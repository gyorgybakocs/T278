#!/bin/bash
set -euo pipefail

# --- postStart safety wrapper ---
# HACK:
#   Kubernetes blocks the container status 'Running' until the postStart hook completes.
#   If this script takes too long (waiting for workers), K8s might kill the container.
#   SOLUTION: We detect the flag, spawn the real logic in the background (nohup), and exit immediately.
if [[ "${1:-}" == "--poststart" ]]; then
  # USAGE:
  #   Redirects I/O to avoid holding open file descriptors that might confuse the runtime.
  nohup /bin/bash "$0" --run </dev/null >/proc/1/fd/1 2>/proc/1/fd/2 &
  exit 0
fi

# Internal run mode (so we don't re-enter the wrapper)
if [[ "${1:-}" == "--run" ]]; then
  shift || true
fi
# --- end wrapper ---

DB_USER="${POSTGRES_USER:-postgres}"
DB_NAME="${POSTGRES_DB:-$DB_USER}"
NAMESPACE="${POD_NAMESPACE:-default}"
WORKER_REPLICAS="${PG_WORKER_REPLICAS:-0}"
WORKER_STS="${PG_WORKER_STATEFULSET_NAME:-}"

# TIMING:
WORKER_WAIT_TIMEOUT_SEC="${WORKER_WAIT_TIMEOUT_SEC:-600}"
WORKER_WAIT_INTERVAL_SEC="${WORKER_WAIT_INTERVAL_SEC:-3}"

log() { echo "[$(date -Iseconds)] $*"; }

# ---- Guardrails: never fail the container in postStart ----
# RISK:
#   If we exit with non-zero in a background process, it's just a log error.
#   But we explicitly choose to 'exit 0' even on missing configs to keep the coordinator alive for debugging.

if [[ -z "$WORKER_STS" ]]; then
  log "WARN: PG_WORKER_STATEFULSET_NAME is missing -> skip worker registration."
  exit 0
fi

if [[ -z "${PGPASSWORD:-}" ]]; then
  log "WARN: PGPASSWORD is missing -> skip worker registration."
  exit 0
fi

# ROLE CHECK:
#   If replicas is 0, we are likely in a standalone or worker mode, so we skip registration.
if [[ "$WORKER_REPLICAS" -le 0 ]]; then
  log "INFO: PG_WORKER_REPLICAS=$WORKER_REPLICAS -> nothing to register."
  exit 0
fi

log "INFO: Waiting for coordinator DB to accept connections..."
until pg_isready -h localhost -p 5432 -U "$DB_USER" -d "$DB_NAME" >/dev/null 2>&1; do
  sleep 2
done

# SETUP:
#   Citus extension MUST be active on the coordinator before adding nodes.
#   We try to create it here just in case init-db.sh missed it or failed transiently.
log "INFO: Ensuring citus extension exists in coordinator DB ($DB_NAME)..."
if ! psql -h localhost -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 \
  -c "CREATE EXTENSION IF NOT EXISTS citus;" >/dev/null 2>&1; then
  log "WARN: CREATE EXTENSION citus failed (transient?) -> skip for now."
  exit 0
fi

log "INFO: Registering $WORKER_REPLICAS workers from StatefulSet '$WORKER_STS' in namespace '$NAMESPACE'"

# --- 1. STABILIZATION: Wait for ALL workers to be ready ---
log "INFO: 🛡️  Cluster Stabilization: Waiting for ALL $WORKER_REPLICAS workers to be ready..."
for (( i=0; i<WORKER_REPLICAS; i++ )); do
  TARGET_HOST="${WORKER_STS}-${i}.postgres-worker-headless.${NAMESPACE}.svc.cluster.local"
  # Fast check loop
  until pg_isready -h "$TARGET_HOST" -p 5432 -U "$DB_USER" -d "$DB_NAME" >/dev/null 2>&1; do
    log "INFO:    ... waiting for $TARGET_HOST (rolling update in progress?)"
    sleep 3
  done
done
log "INFO: ✅ Cluster is stable."

# --- 2. REGISTRATION LOOP ---
for (( i=0; i<WORKER_REPLICAS; i++ )); do
  # DISCOVERY:
  #   Constructs the deterministic DNS name provided by the Headless Service.
  #   Format: <statefulset-name>-<index>.<service-name>.<namespace>.svc.cluster.local
  WORKER_HOST="${WORKER_STS}-${i}.postgres-worker-headless.${NAMESPACE}.svc.cluster.local"
  log "INFO: Worker[$i] = $WORKER_HOST"

  # Wait for worker (redundant but safe)
  log "INFO: Waiting for worker to accept connections (timeout ${WORKER_WAIT_TIMEOUT_SEC}s)..."
  start_ts="$(date +%s)"
  while true; do
    if pg_isready -h "$WORKER_HOST" -p 5432 -U "$DB_USER" -d "$DB_NAME" >/dev/null 2>&1; then
      break
    fi
    now_ts="$(date +%s)"
    if (( now_ts - start_ts > WORKER_WAIT_TIMEOUT_SEC )); then
      log "WARN: Timeout waiting for worker $WORKER_HOST -> skip this worker."
      # RESILIENCE:
      #   We break the loop but continue to the next worker. One bad worker shouldn't stop the cluster.
      break
    fi
    sleep "$WORKER_WAIT_INTERVAL_SEC"
  done

  # Double check after loop exit
  if ! pg_isready -h "$WORKER_HOST" -p 5432 -U "$DB_USER" -d "$DB_NAME" >/dev/null 2>&1; then
    continue
  fi

  # 2) Idempotent check: already registered?
  #   WHY: This script runs on every container restart. We must not try to add an existing node,
  #   as 'master_add_node' might throw an error or duplicate entries depending on version.
  EXISTS="$(psql -h localhost -U "$DB_USER" -d "$DB_NAME" -tAc \
    "SELECT 1 FROM pg_dist_node WHERE nodename='${WORKER_HOST}' AND nodeport=5432 LIMIT 1;" 2>/dev/null || true)"

  if [[ "$EXISTS" == "1" ]]; then
    log "INFO: Already registered -> skip."
    continue
  fi

  # --- 3. SANITIZATION (The Fix for Duplicate Key) ---
  # Before adding the node, we tell all EXISTING nodes to forget about it.
  # This prevents "duplicate key" errors if a previous attempt failed halfway.
  EXISTING_NODES=$(psql -h localhost -U "$DB_USER" -d "$DB_NAME" -tAc "SELECT nodename FROM pg_dist_node WHERE nodeport=5432;")

  if [[ -n "$EXISTING_NODES" ]]; then
      for node in $EXISTING_NODES; do
         # Skip self
         if [[ "$node" == "$WORKER_HOST" ]]; then continue; fi

         # Send DELETE command to the existing worker.
         # We ignore errors (|| true) because usually the node won't exist there, which is good.
         psql -h "$node" -U "$DB_USER" -d "$DB_NAME" -c "DELETE FROM pg_dist_node WHERE nodename='$WORKER_HOST';" >/dev/null 2>&1 || true
      done
  fi
  # ---------------------------------------------------

  log "INFO: Registering node $WORKER_HOST..."

  MAX_RETRIES=10
  RETRY_DELAY=3
  REGISTERED=false

  for (( r=1; r<=MAX_RETRIES; r++ )); do
      if psql -h localhost -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 \
        -c "SELECT master_add_node('${WORKER_HOST}', 5432);" >/dev/null 2>&1; then
        log "INFO: ✅ Successfully registered $WORKER_HOST."
        REGISTERED=true
        break
      else
        log "WARN: ⚠️ master_add_node failed for $WORKER_HOST (Attempt $r/$MAX_RETRIES). Retrying in ${RETRY_DELAY}s..."
        sleep $RETRY_DELAY
      fi
  done

  if [ "$REGISTERED" = false ]; then
      log "ERROR: ❌ Failed to register $WORKER_HOST after $MAX_RETRIES attempts. Skipping."
  fi

  log "INFO: Registered."
done

log "INFO: Worker registration complete."
exit 0
