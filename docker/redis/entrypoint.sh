#!/bin/sh
set -e

export REDIS_MAXMEMORY=${REDIS_MAXMEMORY:-256mb}
export REDIS_MAXMEMORY_POLICY=${REDIS_MAXMEMORY_POLICY:-allkeys-lru}
export REDIS_APPENDONLY=${REDIS_APPENDONLY:-no}

envsubst < /etc/redis/redis.conf.template > /etc/redis/redis.conf

exec docker-entrypoint.sh "$@"
