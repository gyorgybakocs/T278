#!/bin/bash
set -euo pipefail

# --- postStart safety wrapper ---
if [[ "${1:-}" == "--poststart" ]]; then
  # In postStart we must NOT fail the hook.
  # Run the real script in background and exit 0 immediately.
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

# Wait policy for workers
WORKER_WAIT_TIMEOUT_SEC="${WORKER_WAIT_TIMEOUT_SEC:-600}"   # 10 minutes
WORKER_WAIT_INTERVAL_SEC="${WORKER_WAIT_INTERVAL_SEC:-3}"

log() { echo "[$(date -Iseconds)] $*"; }

# ---- Guardrails: never fail the container in postStart ----
# If something critical is missing, log and exit 0.
if [[ -z "$WORKER_STS" ]]; then
  log "WARN: PG_WORKER_STATEFULSET_NAME is missing -> skip worker registration."
  exit 0
fi

if [[ -z "${PGPASSWORD:-}" ]]; then
  log "WARN: PGPASSWORD is missing -> skip worker registration."
  exit 0
fi

if [[ "$WORKER_REPLICAS" -le 0 ]]; then
  log "INFO: PG_WORKER_REPLICAS=$WORKER_REPLICAS -> nothing to register."
  exit 0
fi

log "INFO: Waiting for coordinator DB to accept connections..."
until pg_isready -h localhost -p 5432 -U "$DB_USER" -d "$DB_NAME" >/dev/null 2>&1; do
  sleep 2
done

# Ensure citus exists. If this fails transiently, do NOT kill the container.
log "INFO: Ensuring citus extension exists in coordinator DB ($DB_NAME)..."
if ! psql -h localhost -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 \
  -c "CREATE EXTENSION IF NOT EXISTS citus;" >/dev/null 2>&1; then
  log "WARN: CREATE EXTENSION citus failed (transient?) -> skip for now."
  exit 0
fi

log "INFO: Registering $WORKER_REPLICAS workers from StatefulSet '$WORKER_STS' in namespace '$NAMESPACE'"

for (( i=0; i<WORKER_REPLICAS; i++ )); do
  WORKER_HOST="${WORKER_STS}-${i}.postgres-worker-headless.${NAMESPACE}.svc.cluster.local"
  log "INFO: Worker[$i] = $WORKER_HOST"

  # 1) Wait for worker to be reachable (network + postgres)
  log "INFO: Waiting for worker to accept connections (timeout ${WORKER_WAIT_TIMEOUT_SEC}s)..."
  start_ts="$(date +%s)"
  while true; do
    if pg_isready -h "$WORKER_HOST" -p 5432 -U "$DB_USER" -d "$DB_NAME" >/dev/null 2>&1; then
      break
    fi
    now_ts="$(date +%s)"
    if (( now_ts - start_ts > WORKER_WAIT_TIMEOUT_SEC )); then
      log "WARN: Timeout waiting for worker $WORKER_HOST -> skip this worker."
      # DO NOT exit 1; just skip and continue.
      break
    fi
    sleep "$WORKER_WAIT_INTERVAL_SEC"
  done

  # If worker never became ready, continue with next one.
  if ! pg_isready -h "$WORKER_HOST" -p 5432 -U "$DB_USER" -d "$DB_NAME" >/dev/null 2>&1; then
    continue
  fi

  # 2) Idempotent check: already registered?
  EXISTS="$(psql -h localhost -U "$DB_USER" -d "$DB_NAME" -tAc \
    "SELECT 1 FROM pg_dist_node WHERE nodename='${WORKER_HOST}' AND nodeport=5432 LIMIT 1;" 2>/dev/null || true)"

  if [[ "$EXISTS" == "1" ]]; then
    log "INFO: Already registered -> skip."
    continue
  fi

  # 3) Register (if this fails, do not kill the container)
  log "INFO: Registering node..."
  if ! psql -h localhost -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 \
    -c "SELECT master_add_node('${WORKER_HOST}', 5432);" >/dev/null 2>&1; then
    log "WARN: master_add_node failed for $WORKER_HOST -> continue."
    continue
  fi

  log "INFO: Registered."
done

log "INFO: Worker registration complete."
exit 0
