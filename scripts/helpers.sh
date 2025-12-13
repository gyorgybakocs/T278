#!/bin/bash

# Function: get_latest_pod
# Description: Retrieves the name of the most recently created pod for a given component
#              that is currently in 'Running' state.
# Usage: get_latest_pod "component_name"
# Example: get_latest_pod "redis" -> returns "tis-stack-redis-xyz..."

get_latest_pod() {
    local component=$1

    kubectl get pod \
      -l "app.kubernetes.io/component=$component" \
      --field-selector=status.phase=Running \
      --sort-by=.metadata.creationTimestamp \
      -o jsonpath='{.items[*].metadata.name}' \
    | tr ' ' '\n' \
    | tail -n1
}
