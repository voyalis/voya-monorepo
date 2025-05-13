#!/usr/bin/env bash
set -euo pipefail

# --- Local DB defaults (override via env) ---
LOCAL_DB_HOST="${LOCAL_DB_HOST:-localhost}"
LOCAL_DB_PORT="${LOCAL_DB_PORT:-5433}"
LOCAL_DB_USER="${LOCAL_DB_USER:-voyas_user}"
LOCAL_DB_PASSWORD="${LOCAL_DB_PASSWORD:-StrongPassword123!}"
LOCAL_DB_NAME="${LOCAL_DB_NAME:-voyas_dev_db}"

# Migrations klasörü (repo kökünden)
MIGRATIONS_DIR="apps/api/src/database/migrations"

# --- psql bağlantı argümanlarını hazırla ---
if [[ -n "${NEON_DATABASE_URL:-}" ]]; then
  echo "🎯 Using Neon via NEON_DATABASE_URL"
  CONNECTION_ARGS=( -d "$NEON_DATABASE_URL" )
else
  echo "🎯 Using local Docker at ${LOCAL_DB_HOST}:${LOCAL_DB_PORT}/${LOCAL_DB_NAME}"
  export PGPASSWORD="$LOCAL_DB_PASSWORD"
  CONNECTION_ARGS=(
    -h "$LOCAL_DB_HOST"
    -p "$LOCAL_DB_PORT"
    -U "$LOCAL_DB_USER"
    -d "$LOCAL_DB_NAME"
  )
fi

# --- Migrations tablosunu oluştur (bir kez) ---
psql "${CONNECTION_ARGS[@]}" <<'SQL'
CREATE TABLE IF NOT EXISTS schema_migrations (
  filename TEXT PRIMARY KEY,
  applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
SQL

echo "🚀 Applying migrations from $MIGRATIONS_DIR …"

# --- Her .sql dosyası için döngü ---
find "$MIGRATIONS_DIR" -type f -name '*.sql' | sort -V | while IFS= read -r sql_file; do
  fname=$(basename "$sql_file")

  # Zaten uygulanmışsa atla
  if psql "${CONNECTION_ARGS[@]}" -tAc \
       "SELECT 1 FROM schema_migrations WHERE filename = '$fname';" \
       | grep -q 1; then
    echo "⏩ Skipping already applied: $fname"
    continue
  fi

  echo ""
  echo "----------------------------------------------------------------------"
  echo "⏳ Applying: $fname"
  echo "----------------------------------------------------------------------"

  # SQL çalıştır (hata olsa da script'i durdurma)
  if psql "${CONNECTION_ARGS[@]}" -f "$sql_file"; then
    echo "✅ Success: $fname"
  else
    echo "⚠️ Warning: errors occurred in $fname, but marking as applied and continuing."
  fi

  # Kayıt
  psql "${CONNECTION_ARGS[@]}" -v ON_ERROR_STOP=1 \
    -c "INSERT INTO schema_migrations(filename) VALUES ('$fname');"
done

echo ""
echo "🎉 All migrations processed!"
