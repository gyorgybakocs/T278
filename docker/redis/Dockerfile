ARG IMAGE_FROM_REGISTRY
FROM ${IMAGE_FROM_REGISTRY}

RUN apk add --no-cache gettext

COPY files/redis/redis.conf.template /etc/redis/redis.conf.template

COPY docker/redis/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
