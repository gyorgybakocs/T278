ARG IMAGE_FROM_REGISTRY
FROM ${IMAGE_FROM_REGISTRY}

USER root

# Install gettext to allow usage of 'envsubst' in entrypoint script
RUN apk add --no-cache gettext

# Copy configuration templates
COPY files/pgbouncer/pgbouncer.ini.template /etc/pgbouncer/pgbouncer.ini.template
COPY files/pgbouncer/userlist.txt.template /etc/pgbouncer/userlist.txt.template

# Copy and setup entrypoint script
COPY docker/pgbouncer/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Ensure postgres user has permissions to write generated configs
RUN mkdir -p /etc/pgbouncer && \
    chown -R postgres:postgres /etc/pgbouncer && \
    chmod 755 /etc/pgbouncer

USER postgres

ENTRYPOINT ["/entrypoint.sh"]
CMD ["pgbouncer", "/etc/pgbouncer/pgbouncer.ini"]
