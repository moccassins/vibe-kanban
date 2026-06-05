#!/bin/bash
# Create electric_sync role in the external Postgres database
set -e

DB_URL="${SERVER_DATABASE_URL}"

# Escape password for SQL (replace single quotes with double single quotes)
PW_ESCAPED=$(echo "${ELECTRIC_ROLE_PASSWORD}" | sed "s/'/''/g")

psql "$DB_URL" <<SQL
DO \$\$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'electric_sync') THEN
        CREATE ROLE electric_sync WITH LOGIN NOINHERIT;
    END IF;
END
\$\$;

ALTER ROLE electric_sync WITH PASSWORD '${PW_ESCAPED}';
GRANT pg_read_all_data TO electric_sync;
GRANT pg_replication TO electric_sync;
SQL

echo "electric_sync role ready."
