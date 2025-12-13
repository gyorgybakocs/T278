# BUILD STRATEGY:
#   We use a dynamic base image argument passed by Kaniko.
#   WHY: This allows us to rely on a mirrored or cached version of Redis
#   from our internal registry, ensuring reproducible builds even if Docker Hub is down.
ARG IMAGE_FROM_REGISTRY
FROM ${IMAGE_FROM_REGISTRY}

# DEPENDENCIES:
#   We install 'gettext' to get the 'envsubst' utility.
#   WHY: Redis does not natively support environment variable expansion in redis.conf.
#   We use 'envsubst' in the entrypoint to inject values like maxmemory at runtime.
RUN apk add --no-cache gettext

# CONFIGURATION:
#   Copy the template file. The actual 'redis.conf' will be generated
#   from this template at container startup.
COPY files/redis/redis.conf.template /etc/redis/redis.conf.template

# BOOTSTRAP:
#   Install our custom entrypoint script which handles the config generation logic.
COPY docker/redis/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# EXECUTION:
#   Override the standard entrypoint to run our setup logic first.
ENTRYPOINT ["/entrypoint.sh"]
