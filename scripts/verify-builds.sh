#!/bin/bash
set -e

echo "==============================================="
echo "📦 BUILD VERIFICATION (Registry Check)"
echo "==============================================="

# Get Registry URL (Minikube IP : NodePort 30500)
REGISTRY_IP=$(minikube ip)
REGISTRY_PORT="30500"
REGISTRY_URL="http://$REGISTRY_IP:$REGISTRY_PORT"

echo "Using Registry at: $REGISTRY_URL"

# 1. Fetch Catalog (List of all repositories)
echo -n "🔍 Fetching image catalog... "
CATALOG=$(curl -s --connect-timeout 5 "$REGISTRY_URL/v2/_catalog")

if [ -z "$CATALOG" ]; then
    echo "❌ FAILED TO CONNECT TO REGISTRY!"
    echo "   Ensure Minikube is running and Registry NodePort (30500) is open."
    exit 1
fi
echo "✅ OK"

check_redis() {
  echo "==============================================="
  echo "CHECKING REDIS"
  echo "==============================================="

  REPO_NAME=$(kubectl get configmap redis-config -o jsonpath='{.data.REDIS_REPOSITORY}')

  if [ -z "$REPO_NAME" ]; then
      echo "❌ ERROR: Could not read REPO_NAME from 'redis-config' ConfigMap."
      exit 1
  fi

  if echo "$CATALOG" | grep -Fq "$REPO_NAME"; then
      echo "✅ FOUND: $REPO_NAME"
  else
      echo "❌ MISSING!"
      echo "   Expected: $REPO_NAME"
      echo "   Found in registry: $CATALOG"
      exit 1
  fi
}

check_redis
# check_postgres

echo "==============================================="
echo "🎉 ALL BUILDS VERIFIED SUCCESSFULLY"
echo "==============================================="
