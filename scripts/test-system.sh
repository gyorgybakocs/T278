#!/bin/bash
set -e

echo "======================================================="
echo "🧪 TIS-STACK: SYSTEM FUNCTIONAL TESTS"
echo "======================================================="

get_pod_name() {
    local component=$1
    kubectl get pod -l app.kubernetes.io/component=$component -o jsonpath='{.items[0].metadata.name}' 2>/dev/null
}

get_secret() {
    local key=$1
    kubectl get secret tis-app-secrets -o jsonpath="{.data.$key}" | base64 -d
}

check_redis() {
  echo "==============================================="
  echo "🧪 TESTING REDIS FUNCTIONALITY"
  echo "==============================================="

  REDIS_POD=$(
    kubectl get pod \
      -l app.kubernetes.io/component=redis \
      --field-selector=status.phase=Running \
      --sort-by=.metadata.creationTimestamp \
      -o jsonpath='{.items[*].metadata.name}' \
    | tr ' ' '\n' \
    | tail -n1
  )

  if [ -z "$REDIS_POD" ]; then
      echo "❌ Redis pod not found!"
      exit 1
  fi

  echo "Target Pod: $REDIS_POD"

  echo -n "-> Writing key 'smoke_test_key' ... "
  kubectl exec $REDIS_POD -- redis-cli -a redissecret set smoke_test_key "WORKS_PERFECTLY" 2>/dev/null
  echo "✅ OK"

  echo -n "-> Reading key 'smoke_test_key' ... "
  local RESULT=$(kubectl exec $REDIS_POD -- redis-cli -a redissecret get smoke_test_key 2>/dev/null)

  if [ "$RESULT" == "WORKS_PERFECTLY" ]; then
      echo "✅ OK (Value: $RESULT)"
  else
      echo "❌ FAILED (Expected: WORKS_PERFECTLY, Got: $RESULT)"
      exit 1
  fi

  echo -n "-> Deleting key ... "
  kubectl exec $REDIS_POD -- redis-cli -a redissecret del smoke_test_key 2>/dev/null
  echo "✅ OK"

  echo "==============================================="
  echo "🎉 REDIS TEST PASSED!"
  echo "==============================================="
}

check_postgres() {

    echo "-------------------------------------------------------"
    echo "Testing Component: POSTGRES (Pending Implementation)"
    echo "-------------------------------------------------------"
    # local pod=$(get_pod_name "coordinator") ...
}

check_redis
# check_postgres

echo "======================================================="
echo "🎉 ALL SYSTEM TESTS PASSED!"
echo "======================================================="