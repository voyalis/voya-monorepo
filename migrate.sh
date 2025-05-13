#!/usr/bin/env bash
set -euo pipefail

# --- Configuration -----------------------------------------------------------

# Local Docker defaults (override by exporting these before running the script)
LOCAL_DB_HOST="${LOCAL_DB_HOST:-localhost}"
LOCAL_DB_PORT="${LOCAL_DB_PORT:-5433}"
LOCAL_DB_USER="${LOCAL_DB_USER:-voyas_user}"
LOCAL_DB_PASSWORD="${LOCAL_DB_PASSWORD:-StrongPassword123!}"
LOCAL_DB_NAME="${LOCAL_DB_NAME:-voyas_dev_db}"

# Where your .sql migration files live (relative to repo root)
MIGRATIONS_DIR="apps/api/src/database/migrations"

# --- Build psql connection arguments -----------------------------------------

if [[ -n "${NEON_DATABASE_URL:-}" ]]; then
  echo "🎯 Using Neon database via NEON_DATABASE_URL"
  CONNECTION_ARGS=( -d "$NEON_DATABASE_URL" )
else
  echo "🎯 Using local Docker database at ${LOCAL_DB_HOST}:${LOCAL_DB_PORT}/${LOCAL_DB_NAME}"
  export PGPASSWORD="$LOCAL_DB_PASSWORD"
  CONNECTION_ARGS=(
    -h "$LOCAL_DB_HOST"
    -p "$LOCAL_DB_PORT"
    -U "$LOCAL_DB_USER"
    -d "$LOCAL_DB_NAME"
  )
fi

# --- Ensure schema_migrations table exists ----------------------------------

psql "${CONNECTION_ARGS[@]}" -v ON_ERROR_STOP=1 <<'SQL'
CREATE TABLE IF NOT EXISTS schema_migrations (
  filename TEXT PRIMARY KEY,
  applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
SQL

# --- Apply each migration in order ------------------------------------------

echo "🚀 Applying migrations from $MIGRATIONS_DIR …"

find "$MIGRATIONS_DIR" -type f -name '*.sql' | sort -V | while IFS= read -r sql_file; do
  fname=$(basename "$sql_file")

  # Skip if already applied
  already=$(psql "${CONNECTION_ARGS[@]}" -tAc \
    "SELECT 1 FROM schema_migrations WHERE filename = '$fname';")

  if [[ -n "$already" ]]; then
    echo "⏩ Skipping already applied: $fname"
    continue
  fi

  # Apply
  echo ""
  echo "----------------------------------------------------------------------"
  echo "⏳ Applying: $fname"
  echo "----------------------------------------------------------------------"
  psql "${CONNECTION_ARGS[@]}" -v ON_ERROR_STOP=1 -f "$sql_file"

  # Record success
  psql "${CONNECTION_ARGS[@]}" -v ON_ERROR_STOP=1 -c \
    "INSERT INTO schema_migrations(filename) VALUES ('$fname');"

  echo "✅ Success: $fname"
done

echo ""
echo "🎉 All migrations applied!"
