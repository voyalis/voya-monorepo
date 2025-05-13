#!/usr/bin/env bash
# migrate.sh: Run SQL migrations idempotently with history tracking
set -euo pipefail

# --- Configuration ---
DB_HOST="${LOCAL_DB_HOST:-localhost}"
DB_PORT="${LOCAL_DB_PORT:-5433}"
DB_USER="${LOCAL_DB_USER:-voyas_user}"
DB_PASSWORD="${LOCAL_DB_PASSWORD:-StrongPassword123!}"
DB_NAME="${LOCAL_DB_NAME:-voyas_dev_db}"
MIGRATIONS_DIR="apps/api/src/database/migrations"

# --- Prepare connection arguments ---
if [[ -n "${NEON_DATABASE_URL:-}" ]]; then
  echo "🎯 Target: Neon Database via NEON_DATABASE_URL"
  CONNECTION_ARGS=( -d "$NEON_DATABASE_URL" )
else
  echo "🎯 Target: Local Docker (${DB_HOST}:${DB_PORT} / ${DB_NAME})"
  export PGPASSWORD="$DB_PASSWORD"
  CONNECTION_ARGS=( -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" )
fi

# --- Ensure migration history table exists ---
echo "🔍 Ensuring schema_migrations table exists"
psql "${CONNECTION_ARGS[@]}" -v ON_ERROR_STOP=1 <<'EOSQL'
CREATE TABLE IF NOT EXISTS schema_migrations (
  filename TEXT PRIMARY KEY,
  applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
EOSQL

echo "🚀 Applying migrations from $MIGRATIONS_DIR"

# --- Apply each SQL file once ---
find "$MIGRATIONS_DIR" -type f -name '*.sql' | sort -V | while IFS= read -r sql_file; do
  fname=$(basename "$sql_file")
  # Check history
  already=$(psql "${CONNECTION_ARGS[@]}" -tAc "SELECT 1 FROM schema_migrations WHERE filename='\$fname' LIMIT 1;")
  if [[ "\$already" == "1" ]]; then
    echo "⏭️ Skipping \$fname (already applied)"
    continue
  fi

  echo "----------------------------------------------------------------------"
  echo "⏳ Applying \$fname"
  echo "----------------------------------------------------------------------"

  if psql "${CONNECTION_ARGS[@]}" -v ON_ERROR_STOP=1 -f "$sql_file"; then
    echo "✅ Success: \$fname"
    # Record in history
    psql "${CONNECTION_ARGS[@]}" -v ON_ERROR_STOP=1 -c "INSERT INTO schema_migrations(filename) VALUES('\$fname');"
  else
    echo "❌ Failed: \$fname"
    unset PGPASSWORD
    exit 1
  fi

done

# Cleanup
unset PGPASSWORD

echo "🎉 All migrations applied"