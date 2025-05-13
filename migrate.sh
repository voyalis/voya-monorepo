#!/usr/bin/env bash

        # Scriptin herhangi bir komutta hata alması durumunda hemen çıkmasını sağlar.
        set -e
        # Tanımlanmamış değişken kullanımında hata verip çıkmasını sağlar.
        set -u
        # Pipeline'daki bir komut hata verirse tüm pipeline'ın hata vermesini sağlar.
        set -o pipefail

        # --- Veritabanı Bağlantı Bilgileri ---
        # Bu değişkenler ortamdan (environment) veya aşağıdaki gibi doğrudan set edilebilir.
        # Lokal Docker için:
        DB_HOST="${LOCAL_DB_HOST:-localhost}"
        DB_PORT="${LOCAL_DB_PORT:-5433}" # Docker Compose'daki portumuz
        DB_USER="${LOCAL_DB_USER:-voyas_user}"
        DB_PASSWORD="${LOCAL_DB_PASSWORD:-StrongPassword123!}"
        DB_NAME="${LOCAL_DB_NAME:-voyas_dev_db}"

        # Veya Neon için (CI/CD'de veya lokalde Neon'a bağlanırken kullanılacak):
        # NEON_DATABASE_URL formatı: postgresql://user:password@host:port/dbname?sslmode=require
        # Eğer NEON_DATABASE_URL ortam değişkeni set edilmişse onu kullan, yoksa lokal ayarları kullan.
        # PGPASSWORD ortam değişkeni psql tarafından otomatik olarak kullanılır.

        # Migration dosyalarının bulunduğu klasör (apps/api/src/database/migrations)
        # Bu script ana dizinden çalıştırılacağı için yol doğru.
        MIGRATIONS_DIR="apps/api/src/database/migrations"

        echo "🚀 Veritabanı migration'ları uygulanıyor..."
        echo "📂 Migration dosyaları kaynağı: $MIGRATIONS_DIR"

        # Hangi veritabanına bağlanılacağını belirle
        if [[ -n "${NEON_DATABASE_URL:-}" ]]; then
          echo "🎯 Hedef veritabanı: Neon (NEON_DATABASE_URL üzerinden)"
          # psql, DATABASE_URL formatını doğrudan kabul eder.
          # PGPASSWORD'ü ayrıştırmaya gerek yok, psql URL'den alır veya PGPASSWORD env var'ını kullanır.
          # Neon URL'sinden kullanıcı adı, şifre, host, port, dbname ayrıştırmak yerine
          # doğrudan URL'yi kullanmak daha basit olabilir.
          # Ancak psql'in -f parametresiyle URL doğrudan çalışmayabilir, bu yüzden
          # PGPASSWORD'ü set edip diğer parametreleri ayrıştırabiliriz veya psql'e tek tek verebiliriz.

          # Neon URL'sinden bilgileri ayrıştırma (opsiyonel, eğer PGPASSWORD set edilmeyecekse)
          # Örnek: postgresql://<user>:<password>@<host>:<port>/<dbname>
          # Bu ayrıştırma karmaşık olabilir, en iyisi PGPASSWORD ve diğer parametreleri kullanmak.

          # Neon için PGPASSWORD'ü ve diğer bağlantı parametrelerini ayarlayalım
          # (Bu script CI'da çalışacaksa, bu değişkenler CI secret'larından gelmeli)
          # Örnek: export PGPASSWORD=$(echo $NEON_DATABASE_URL | awk -F':' '{print $3}' | awk -F'@' '{print $1}')
          # Bu çok karmaşık ve hataya açık.
          # En iyisi CI'da PGPASSWORD, PGHOST, PGPORT, PGUSER, PGDATABASE değişkenlerini set etmek.
          # Şimdilik lokal için PGPASSWORD'ü kullanacağız.

          # Eğer NEON_DATABASE_URL set edilmişse, psql onu kullanır.
          # Biz sadece hangi DB'ye bağlandığımızı loglayalım.
          DB_CONNECTION_INFO="Neon DB (NEON_DATABASE_URL ile)"
          PSQL_COMMAND_BASE="psql \"$NEON_DATABASE_URL\""

        else
          echo "🎯 Hedef veritabanı: Lokal Docker (localhost:${DB_PORT})"
          DB_CONNECTION_INFO="Lokal Docker (Host: ${DB_HOST}, Port: ${DB_PORT}, DB: ${DB_NAME}, User: ${DB_USER})"
          # Lokal Docker için PGPASSWORD'ü set et
          export PGPASSWORD="${DB_PASSWORD}"
          PSQL_COMMAND_BASE="psql -h ${DB_HOST} -p ${DB_PORT} -U ${DB_USER} -d ${DB_NAME}"
        fi

        echo "Bağlantı Bilgisi: ${DB_CONNECTION_INFO}"

        # Migration dosyalarını bul ve sırala (V001, V002.1 vb. doğru sıralanması için)
        # 'find' komutu dosyaları listeleyecek, 'sort -V' ise versiyon numaralarına göre sıralayacak.
        find "$MIGRATIONS_DIR" -type f -name '*.sql' | sort -V | while IFS= read -r sql_file; do
          echo ""
          echo "----------------------------------------------------------------------"
          echo "⏳ Uygulanıyor: $(basename "$sql_file")"
          echo "----------------------------------------------------------------------"

          # psql komutunu çalıştır. -v ON_ERROR_STOP=1 ile ilk hatada durmasını sağlar.
          # Komutun tamamını çift tırnak içine almak ve değişkenleri doğru kullanmak önemli.
          if ${PSQL_COMMAND_BASE} -v ON_ERROR_STOP=1 -f "$sql_file"; then
            echo "✅ BAŞARILI: $(basename "$sql_file") uygulandı."
          else
            echo "❌ HATA: $(basename "$sql_file") uygulanırken bir sorun oluştu."
            # PGPASSWORD'ü temizle (güvenlik için)
            unset PGPASSWORD
            exit 1 # Hata durumunda script'ten çık
          fi
        done

        # PGPASSWORD'ü temizle (güvenlik için)
        unset PGPASSWORD

        echo ""
        echo "🎉 Tüm migration dosyaları başarıyla uygulandı!"
