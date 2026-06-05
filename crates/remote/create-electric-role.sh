#!/bin/bash
# Ensure Postgres has wal_level=logical for ElectricSQL
# and create electric_sync role if needed
set -e

DB_URL="${SERVER_DATABASE_URL}"

# Check wal_level — ElectricSQL needs logical replication
echo "Checking Postgres wal_level..."
WAL_LEVEL=$(psql "$DB_URL" -tAc "SHOW wal_level" 2>/dev/null || echo "unknown")
echo "wal_level: $WAL_LEVEL"

if [ "$WAL_LEVEL" != "logical" ]; then
    echo "WARNING: wal_level is '$WAL_LEVEL'. ElectricSQL requires 'logical'."
    echo "Set wal_level=logical in postgresql.conf and restart Postgres."
    echo "Attempting to set it..."
    psql "$DB_URL" -c "ALTER SYSTEM SET wal_level = logical;" 2>/dev/null || \
    echo "Cannot ALTER SYSTEM. You must manually set wal_level=logical in postgresql.conf"
fi

# Ensure electric_sync role exists — it's a role, not a separate user
# If the main user is superuser, this is just a formality
PW_ESCAPED=$(echo "${ELECTRIC_ROLE_PASSWORD}" | sed "s/'/''/g")

psql "$DB_URL" <<SQL
DO \$\$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'electric_sync') THEN
        CREATE ROLE electric_sync WITH LOGIN NOINHERIT PASSWORD '${PW_ESCAPED}';
    ELSE
        ALTER ROLE electric_sync WITH PASSWORD '${PW_ESCAPED}';
    END IF;
END
\$\$;

GRANT pg_read_all_data TO electric_sync;
GRANT pg_replication TO electric_sync;
SQL

echo "electric_sync role ready."
