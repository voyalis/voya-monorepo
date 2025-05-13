#!/usr/bin/env bash
set -euo pipefail

# --- Lokal DB parametreleri ---
DB_HOST="${LOCAL_DB_HOST:-localhost}"
DB_PORT="${LOCAL_DB_PORT:-5433}"
DB_USER="${LOCAL_DB_USER:-voyas_user}"
DB_PASSWORD="${LOCAL_DB_PASSWORD:-StrongPassword123!}"
DB_NAME="${LOCAL_DB_NAME:-voyas_dev_db}"

MIGRATIONS_DIR="apps/api/src/database/migrations"

echo "🚀 Veritabanı migration'ları uygulanıyor..."
echo "📂 Migration dosyaları kaynağı: $MIGRATIONS_DIR"

# Bağlantı argümanlarını hazırlayalım
if [[ -n "${NEON_DATABASE_URL:-}" ]]; then
  echo "🎯 Hedef veritabanı: Neon (NEON_DATABASE_URL üzerinden)"
  # psql -d "<connection_string>" şifresi URL içinde ise otomatik kullanır
  CONNECTION_ARGS=( -d "$NEON_DATABASE_URL" )
else
  echo "🎯 Hedef veritabanı: Lokal Docker (localhost:${DB_PORT})"
  export PGPASSWORD="$DB_PASSWORD"
  CONNECTION_ARGS=( -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" )
fi

echo "----------------------------------------------------------------------"
echo "Bağlantı argümanları: ${CONNECTION_ARGS[*]}"
echo "----------------------------------------------------------------------"

# SQL dosyalarını version sırasına göre uygula
find "$MIGRATIONS_DIR" -type f -name '*.sql' | sort -V | \
while IFS= read -r sql_file; do
  echo ""
  echo "⏳ Uygulanıyor: $(basename "$sql_file")"
  if psql "${CONNECTION_ARGS[@]}" -v ON_ERROR_STOP=1 -f "$sql_file"; then
    echo "✅ BAŞARILI: $(basename "$sql_file")"
  else
    echo "❌ HATA: $(basename "$sql_file") uygulanamadı!"
    exit 1
  fi
done

# Temizlik
unset PGPASSWORD
echo ""
echo "🎉 Tüm migration dosyaları başarıyla uygulandı!"
