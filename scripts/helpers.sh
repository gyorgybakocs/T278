#!/bin/bash

# Function: get_latest_pod
# Description: Retrieves the name of the most recently created pod for a given component
#              that is currently in 'Running' state.
# Usage: get_latest_pod "component_name"
# Example: get_latest_pod "redis" -> returns "tis-stack-redis-xyz..."

get_latest_pod() {
    local component=$1

    # QUERY LOGIC:
    #   1. '-l ...': Filters pods by the standard component label used in our Helm charts.
    #   2. '--field-selector=status.phase=Running':
    #      CRITICAL: Ensures we don't pick up Pods that are 'Pending', 'Failed', or 'Terminating'.
    #      This prevents the test scripts from trying to execute commands in a pod that isn't ready yet.
    #   3. '--sort-by=.metadata.creationTimestamp':
    #      Orders the list so the oldest is first and the newest is last.
    kubectl get pod \
      -l "app.kubernetes.io/component=$component" \
      --field-selector=status.phase=Running \
      --sort-by=.metadata.creationTimestamp \
      -o jsonpath='{.items[*].metadata.name}' \
    | tr ' ' '\n' \
    | tail -n1
    # PARSING:
    #   Jsonpath returns a space-separated string of names.
    #   'tr' converts spaces to newlines so 'tail -n1' can reliably grab the very last (newest) pod name.
}
