# BUILD STRATEGY:
#   We use a dynamic base image argument.
#   WHY: This allows the build system (Kaniko) to pull a cached or specific
#   version of the upstream image (e.g., from the internal registry)
#   without hardcoding it in the Dockerfile.
ARG IMAGE_FROM_REGISTRY
FROM ${IMAGE_FROM_REGISTRY}

# PRIVILEGE ESCALATION:
#   Switch to root to install packages and modify file permissions.
#   We will drop back to the 'postgres' user at the end for security.
USER root

# DEPENDENCIES:
#   - gettext-base: Provides 'envsubst', essential for generating
#     postgresql.conf from the template at runtime.
#   - iputils-ping: Diagnostic tool useful for checking connectivity
#     between Coordinator and Workers in a distributed setup.
RUN apt-get update && \
    apt-get install -y --no-install-recommends gettext-base iputils-ping && \
    rm -rf /var/lib/apt/lists/*

# CONFIGURATION TEMPLATES:
#   We copy the template instead of the final config.
#   The entrypoint script will fill in the environment variables later.
COPY files/postgres/postgresql.conf.template /etc/postgresql/postgresql.conf.template
COPY files/postgres/pg_hba.conf              /etc/postgresql/pg_hba.conf

# CUSTOM TOOLING:
#   Installs the worker registration script.
#   This is not part of the standard init process but a custom tool
#   called by the Coordinator's postStart hook.
RUN mkdir -p /usr/local/bin/citus-scripts
COPY docker/postgres/scripts/register-workers.sh /usr/local/bin/citus-scripts/register-workers.sh
RUN chmod +x /usr/local/bin/citus-scripts/register-workers.sh

# INITIALIZATION HOOKS:
#   Scripts in /docker-entrypoint-initdb.d/ are automatically executed
#   by the official Postgres image ONLY when the data directory is empty (first boot).
#   Used here to create the Citus extension and custom databases.
COPY docker/postgres/scripts/init-db.sh /docker-entrypoint-initdb.d/002-init-custom-dbs.sh
RUN chmod +x /docker-entrypoint-initdb.d/002-init-custom-dbs.sh

# BOOTSTRAP:
#   Overrides the standard entrypoint to inject our config generation logic.
COPY docker/postgres/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# PERMISSIONS:
#   Ensures the postgres user (uid 999) can write the generated config files.
#   Without this, 'envsubst' in the entrypoint would fail with Permission Denied.
RUN mkdir -p /etc/postgresql && \
    chown -R postgres:postgres /etc/postgresql && \
    chmod 755 /etc/postgresql

# SECURITY:
#   Drop root privileges. The container runs as the 'postgres' user at runtime.
USER postgres

# EXECUTION:
#   1. Run /entrypoint.sh (config generation).
#   2. Exec 'postgres' with explicit config file paths to ensure our generated
#      files are used instead of the defaults in /var/lib/postgresql/data.
ENTRYPOINT ["/entrypoint.sh"]
CMD ["postgres", "-c", "config_file=/etc/postgresql/postgresql.conf", "-c", "hba_file=/etc/postgresql/pg_hba.conf"]
