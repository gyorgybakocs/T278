#!/bin/bash

# Simple checker for Postgres & PgBouncer runtime config values
# Matches the keys used in configure_resources.sh

echo "==========================================================="
echo "🔎 CHECKING RUNTIME DB CONFIG VALUES"
echo "==========================================================="

# ----------------- REDIS -----------------
REDIS_POD=$(kubectl get pod -l "app.kubernetes.io/component=redis" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)


if [ -z "$REDIS_POD" ]; then
  echo "  ❌ No Redis pod found with label app=redis"
else
  echo "  -> Pod: $REDIS_POD"
  R_CONF_PATH="/etc/redis/redis.conf"

  R_PARAMS=(
    "maxmemory"
  )

  kubectl exec "$REDIS_POD" -- sh -c "if [ ! -f '$R_CONF_PATH' ]; then echo '  ❌ Redis config file not found at $R_CONF_PATH'; exit 0; fi"

  for p in "${R_PARAMS[@]}"; do
    echo -n "  - $p ==> "
    kubectl exec "$REDIS_POD" -- sh -c "grep -E '^'$p'[[:space:]]+' '$R_CONF_PATH' || echo '<NOT SET>'"
  done

fi

echo
echo "✅ Config check finished."
