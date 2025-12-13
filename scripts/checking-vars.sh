#!/bin/bash

# Simple checker for Postgres & PgBouncer runtime config values
# Matches the keys used in configure_resources.sh

echo "==========================================================="
echo "🔎 CHECKING RUNTIME DB CONFIG VALUES"
echo "==========================================================="

# ----------------- REDIS -----------------
# DISCOVERY:
#   Finds the Redis pod dynamically using labels.
#   WHY: Pod names include random suffixes (e.g., redis-7f8b9c...), so we cannot hardcode them.
#   We take the first item found (.items[0]) assuming a single-replica deployment for verification.
REDIS_POD=$(kubectl get pod -l "app.kubernetes.io/component=redis" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)


if [ -z "$REDIS_POD" ]; then
  echo "  ❌ No Redis pod found with label app=redis"
else
  echo "  -> Pod: $REDIS_POD"
  R_CONF_PATH="/etc/redis/redis.conf"

  R_PARAMS=(
    "maxmemory"
  )

  # VALIDATION:
  #   Ensures the config file exists before trying to grep it.
  #   Prevents confusing "No such file" errors if the container layout changes.
  kubectl exec "$REDIS_POD" -- sh -c "if [ ! -f '$R_CONF_PATH' ]; then echo '  ❌ Redis config file not found at $R_CONF_PATH'; exit 0; fi"

  for p in "${R_PARAMS[@]}"; do
    echo -n "  - $p ==> "
    # INSPECTION:
    #   Reads the actual config file from *inside* the running container.
    #   WHY: This verifies that the Helm values were correctly injected and written to disk,
    #   catching issues where 'envsubst' might have failed or the wrong template was used.
    #   This is the ultimate source of truth for the running process.
    kubectl exec "$REDIS_POD" -- sh -c "grep -E '^'$p'[[:space:]]+' '$R_CONF_PATH' || echo '<NOT SET>'"
  done

fi

echo
echo "✅ Config check finished."
