#!/bin/sh
set -e

# DEFAULTS:
#   Set safe default values for memory management if environment variables are missing.
#   WHY: This ensures the container is runnable in a standalone context (e.g., 'docker run')
#   without requiring a complex Helm chart to inject every single variable.
export REDIS_MAXMEMORY=${REDIS_MAXMEMORY:-256mb}
export REDIS_MAXMEMORY_POLICY=${REDIS_MAXMEMORY_POLICY:-allkeys-lru}
export REDIS_APPENDONLY=${REDIS_APPENDONLY:-no}

# TEMPLATING:
#   Inject environment variables into the configuration template.
#   WHY: Redis configuration files do not support environment variable expansion natively.
#   We use 'envsubst' as a lightweight pre-processor to bridge this gap.
envsubst < /etc/redis/redis.conf.template > /etc/redis/redis.conf

# EXECUTION:
#   Hand off control to the official Redis entrypoint.
#   'exec' replaces the shell process, ensuring Redis becomes PID 1 and receives signals.
exec docker-entrypoint.sh "$@"
