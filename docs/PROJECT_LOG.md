VoyaGo++ Proje Gelişim Logu ve Karar Kaydı (v0.1 - Başlangıç)

Proje Adı: VoyaGo++ (Çalışma Adı: voya-monorepo)
Versiyon: v3.5 (Strateji Raporu Referansı)
Başlangıç Tarihi: 11 Mayıs 2025
DevOps Şampiyonu: AI Asistanı

Genel Amaç:
VoyaGo++ projesi için modern, ölçeklenebilir, güvenli ve maliyet etkin bir DevOps altyapısı ve kültürü oluşturmak. Hızlı ve kaliteli yazılım teslimatını mümkün kılmak.

Temel Strateji:
"Hibrit ve Evrimsel Şablonlama" ile başlayarak, voya-monorepo adında Nx tabanlı bir monorepo oluşturmak. Temel API (NestJS) ve Mobil (Flutter) kabuklarını kurmak. Turborepo ile build/task yönetimini optimize etmek. Lokal geliştirme için Docker tabanlı PostGIS'li PostgreSQL kullanmak. CI/CD için GitHub Actions'ı benimsemek. Başlangıçta sıfıra yakın maliyetle ilerlemek, ihtiyaç duyuldukça yönetilen servislere kademeli geçiş yapmak.

GELİŞİM LOGU:

Tarih: 11 Mayıs 2025

Adım 0: Ön Hazırlık ve Ortam Kontrolü

Yapılanlar:
Kullanıcının Windows + WSL ortamı teyit edildi.
Gerekli araçların (Git, Node.js v24.0.1, npm v11.3.0, Flutter v3.29.3, Docker v26.1.3) WSL içinde kurulu olduğu doğrulandı.
Kararlar/Notlar:
Proje adı voyaS yerine voya-monorepo olarak güncellendi.
Node.js v24.0.1'in, kurulacak Nx versiyonunun (muhtemelen daha eski bir v21.x) ideal destek aralığının (v20, v22) dışında olduğu tespit edildi. Ancak başlangıçta bu versiyonla devam edilip, sorun çıkarsa nvm ile v22'ye geçilmesi kararlaştırıldı. (Sonradan nx generate komutlarında çıkan sorunlar nedeniyle bu kararın doğruluğu teyit edildi ve Node.js versiyon uyumluluğunun önemi anlaşıldı, ancak kullanıcı isteğiyle v24 ile devam edildi.)
Sonuç: Geliştirme ortamı temel araçlar açısından hazır.
Adım 1: Proje İskeleti ve Ana package.json Oluşturma (Turborepo için)

Yapılanlar:
~/Projects/voya-monorepo klasörü oluşturuldu.
npm init -y ile ana package.json dosyası oluşturuldu.
jq '.name = "@voya/monorepo" | .workspaces = ["apps/*", "packages/*"]' package.json > package.json.tmp && mv package.json.tmp package.json komutuyla package.json güncellendi (name ve workspaces alanları eklendi).
npm install turbo --save-dev ile Turborepo geliştirme bağımlılığı olarak kuruldu (v2.5.3).
apps ve packages klasörleri oluşturuldu.
Kararlar/Notlar:
Ana proje adı olarak @voya/monorepo benimsendi.
Turborepo'nun workspace'leri tanıması için package.json'a workspaces alanı eklendi.
Sonuç: Temel monorepo yapısı ve Turborepo kurulumu için zemin hazırlandı. package.json dosyası, Turborepo'nun beklediği packageManager alanı eksikliği nedeniyle bir sonraki adımda uyarı verdi. Bu uyarı üzerine package.json dosyasına "packageManager": "npm@11.3.0" ve "private": true alanları eklendi ve JSON format hataları giderildi.
Adım 2: Temel turbo.json Yapılandırması

Yapılanlar:
voya-monorepo ana dizinine aşağıdaki içerikle turbo.json dosyası oluşturuldu:
JSON

{
  "$schema": "https://turborepo.org/schema.json",
  "tasks": { // "pipeline" anahtarı "tasks" olarak güncellendi (Turbo v2.x uyumu)
    "build": {
      "dependsOn": ["^build"],
      "outputs": ["dist/**", ".next/**", "build/**", "apps/api/dist/**", "apps/mobile/build/**"]
    },
    "test": {
      "dependsOn": ["build"],
      "outputs": ["coverage/**"]
    },
    "lint": {
      "outputs": []
    },
    "dev": { // Bu 'dev' görevi genel bir tanımdı, 'start:dev' ile karıştırılmamalı
      "cache": false,
      "persistent": true
    },
    "start:dev": { // API'nin 'start:dev' script'i için spesifik tanım
      "cache": false,
      "persistent": true
    },
    "clean": {
      "cache": false
    }
  }
}
Kararlar/Notlar:
Turborepo v2.x uyumluluğu için pipeline anahtarı tasks olarak güncellendi.
API'mizin package.json dosyasındaki start:dev script'ini Turborepo'nun doğru tanıması için tasks altına start:dev adında bir görev tanımı eklendi.
Sonuç: Turborepo'nun temel görevleri nasıl çalıştıracağını ve önbelleğe alacağını tanımlayan yapılandırma dosyası hazır.
Adım 3: Backend API (NestJS) Uygulama Kabuğunu Oluşturma ve Entegrasyon

Yapılanlar:
voya-monorepo ana dizininde npm install -D @nestjs/cli @nestjs/schematics typescript ts-node tsconfig-paths ile NestJS için gerekli CLI ve temel geliştirme araçları ana devDependencies'e eklendi.
apps/api klasörü temizlendi ve bu klasörün içine girilerek npx @nestjs/cli new . --skip-git --package-manager=npm --language=ts --strict --collection=@nestjs/schematics komutuyla standart bir NestJS proje iskeleti oluşturuldu. Bu, tüm gerekli dosyaları (src, test, tsconfig.json, nest-cli.json ve kendi package.json'ı) apps/api altına kurdu.
Oluşan apps/api/package.json dosyasındaki name alanı @voya/api olarak güncellendi.
apps/api klasörü içindeyken npm install çalıştırılarak API'ye özel bağımlılıklar kuruldu.
apps/api klasörü içindeyken npm run start:dev komutuyla API başarıyla çalıştırıldı ve http://localhost:3000 adresinden "Hello World!" yanıtı alındığı teyit edildi.
voya-monorepo ana dizinindeki package.json dosyasına, Turborepo aracılığıyla API'yi yönetmek için script'ler eklendi:
JSON

// package.json (ana dizin) -> scripts bölümü
"scripts": {
  "build:api": "turbo run build --filter=@voya/api",
  "start:dev:api": "turbo run start:dev --filter=@voya/api",
  "lint:api": "turbo run lint --filter=@voya/api",
  "test:api": "turbo run test --filter=@voya/api",
  "test": "echo \"Error: no test specified\" && exit 1"
},
voya-monorepo ana dizinindeyken npm run start:dev:api komutu çalıştırıldı ve API'nin Turborepo üzerinden de başarıyla başladığı teyit edildi.
Kararlar/Notlar:
NestJS projesini doğrudan apps/api içinde oluşturmak, nest new <yol> komutunun dışarıda oluşturup sonra taşıma ihtiyacını ortadan kaldırdı.
API'nin kendi package.json dosyasındaki name alanının @voya/api olması ve ana package.json'daki Turborepo --filter argümanının bu isimle eşleşmesi kritikti.
turbo.json'daki tasks altında start:dev tanımının olması, turbo run start:dev --filter=@voya/api komutunun doğru çalışmasını sağladı.
Sonuç: Nx ve Turborepo ile yönetilen monorepo içinde, çalışan ve temel olarak yapılandırılmış bir NestJS API'miz var.
Adım 4: Lokal Veritabanı (PostGIS'li PostgreSQL) Kurulumu ve API Bağlantısı

Yapılanlar:
voya-monorepo ana dizinine aşağıdaki içerikle docker-compose.yml dosyası oluşturuldu:
YAML

version: '3.8'
services:
  postgres_voyas:
    image: postgis/postgis:16-3.4
    container_name: voyas_db_local
    environment:
      POSTGRES_USER: voyas_user
      POSTGRES_PASSWORD: StrongPassword123!
      POSTGRES_DB: voyas_dev_db
    ports:
      - "5433:5432"
    volumes:
      - voyas_postgres_data:/var/lib/postgresql/data
    restart: unless-stopped
volumes:
  voyas_postgres_data:
docker-compose up -d komutuyla veritabanı konteyneri başarıyla başlatıldı. docker ps ile voyas_db_local'ın çalıştığı teyit edildi.
apps/api klasörüne gidildi ve npm install --save @nestjs/typeorm typeorm pg @nestjs/config komutlarıyla veritabanı bağlantısı için gerekli paketler kuruldu.
apps/api klasörüne .env dosyası oluşturularak veritabanı bağlantı bilgileri eklendi:
Kod snippet'i

DATABASE_HOST=localhost
DATABASE_PORT=5433
DATABASE_USER=voyas_user
DATABASE_PASSWORD=StrongPassword123!
DATABASE_DB_NAME=voyas_dev_db
apps/api/src/app.module.ts dosyası, ConfigModule ve TypeOrmModule.forRootAsync kullanılarak güncellendi. Bu sayede API, .env dosyasındaki bilgilerle PostgreSQL veritabanına bağlanacak şekilde yapılandırıldı. synchronize: true ve logging: true ayarları geliştirme için aktif edildi.
apps/api içindeyken npm run start:dev komutu tekrar çalıştırıldı. Terminal loglarında TypeORM'in veritabanına bağlandığına ve typeorm_metadata tablosunu kontrol ettiğine dair SQL sorguları görüldü.
Kararlar/Notlar:
Lokal geliştirme için Docker Compose ile PostGIS'li PostgreSQL kullanımı benimsendi.
API'nin veritabanı yapılandırması için @nestjs/config ve TypeORM kullanıldı.
Geliştirme kolaylığı için synchronize: true ayarı yapıldı, üretimde false olacağı not edildi.
Sonuç: API'miz artık lokalde çalışan PostgreSQL veritabanımıza başarıyla bağlanabiliyor.


