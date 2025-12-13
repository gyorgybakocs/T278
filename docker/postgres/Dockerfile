ARG IMAGE_FROM_REGISTRY
FROM ${IMAGE_FROM_REGISTRY}

USER root

# Install gettext for 'envsubst' and iputils for network debugging if needed
RUN apt-get update && \
    apt-get install -y --no-install-recommends gettext-base iputils-ping && \
    rm -rf /var/lib/apt/lists/*

# 1. Copy Configuration Templates
COPY files/postgres/postgresql.conf.template /etc/postgresql/postgresql.conf.template
COPY files/postgres/pg_hba.conf              /etc/postgresql/pg_hba.conf

# 2. Copy Scripts
RUN mkdir -p /usr/local/bin/citus-scripts
COPY docker/postgres/scripts/register-workers.sh /usr/local/bin/citus-scripts/register-workers.sh
RUN chmod +x /usr/local/bin/citus-scripts/register-workers.sh
COPY docker/postgres/scripts/init-db.sh /docker-entrypoint-initdb.d/002-init-custom-dbs.sh
RUN chmod +x /docker-entrypoint-initdb.d/002-init-custom-dbs.sh

# 3. Copy Entrypoint
COPY docker/postgres/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# 4. Set Permissions
RUN mkdir -p /etc/postgresql && \
    chown -R postgres:postgres /etc/postgresql && \
    chmod 755 /etc/postgresql

USER postgres

ENTRYPOINT ["/entrypoint.sh"]
CMD ["postgres", "-c", "config_file=/etc/postgresql/postgresql.conf", "-c", "hba_file=/etc/postgresql/pg_hba.conf"]