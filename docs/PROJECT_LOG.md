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


GELİŞİM LOGU GÜNCELLEMESİ:

  Tarih: 11 Mayıs 2025 (Devam)

  Adım 5: .gitignore Yapılandırması ve Depo Temizliği

  Yapılanlar:
  Kapsamlı bir .gitignore dosyası voya-monorepo ana dizinine eklendi. Bu dosya node_modules, build çıktıları, loglar, environment dosyaları ve IDE/OS'e özel dosyaları içerecek şekilde yapılandırıldı.
  Daha önceki push'larda yanlışlıkla depoya eklenmiş olabilecek node_modules klasörleri (ana dizin ve apps/api için) git rm -r --cached <klasör_adı> komutları kullanılarak Git takibinden çıkarıldı. Bu işlem lokaldeki dosyaları silmedi, sadece Git'in artık bu klasörleri izlememesini sağladı.
  .gitignore dosyası ve yapılan temizlik işlemleri yeni bir commit ile Git'e eklendi.
  Tüm değişiklikler başarıyla GitHub'daki voya-monorepo deposuna push edildi. GitHub'dan gelen "büyük dosya" uyarısının node_modules kaynaklı olduğu ve .gitignore ile bu sorunun gelecekte yaşanmayacağı anlaşıldı.
  Kararlar/Notlar:
  node_modules klasörlerinin kesinlikle Git'e gönderilmemesi gerektiği bir kez daha teyit edildi.
  .gitignore dosyasının projenin en başından itibaren doğru yapılandırılmasının önemi vurgulandı.
  Ana package-lock.json dosyasının Git'e dahil edilmesi, ancak alt paketlerdeki (apps/*/package-lock.json) lock dosyalarının .gitignore ile hariç tutulması düşünülebilir (npm workspaces davranışı ve tutarlılık için bu konu ileride tekrar değerlendirilebilir, şimdilik ana lock dosyası yeterli).
  Sonuç: Git depomuz artık daha temiz ve sadece gerekli kod/konfigürasyon dosyalarını içeriyor. node_modules gibi büyük ve gereksiz klasörler depoya gönderilmeyecek.

  GELİŞİM LOGU GÜNCELLEMESİ:

Tarih: 11 Mayıs 2025 (Devam)

Adım 6: Mobil (Flutter) Uygulama Kabuğu Entegrasyonu

Yapılanlar:
voya-monorepo/apps/ altına mobile adında bir klasör oluşturuldu.
apps/mobile klasörü içine flutter create . --project-name=mobile --org=com.voyas komutuyla standart bir Flutter uygulama iskeleti kuruldu.
Mobil uygulamanın Turborepo tarafından tanınması ve yönetilebilmesi için apps/mobile/package.json dosyası oluşturuldu ve içine @voya/mobile adı ile temel build, test, lint, clean ve dev (flutter run) script'leri eklendi.
Ana voya-monorepo/package.json dosyasına, Turborepo aracılığıyla mobil uygulamaya ait script'leri çalıştırmak için kısayollar (build:mobile, start:dev:mobile vb.) eklendi.
Kararlar/Notlar:
Flutter projesi, monorepo içinde kendi package.json dosyasıyla bir workspace paketi olarak tanımlandı.
Mobil uygulama için start:dev script'i, flutter run komutunu çalıştıracak şekilde ayarlandı.
Sonuç: Monorepo içinde hem backend API'miz hem de mobil Flutter uygulamamız için temel iskeletler ve Turborepo ile yönetim altyapısı oluşturuldu.
Adım 7: Son Değişikliklerin GitHub'a Gönderilmesi

Yapılanlar:
Mobil uygulama eklenmesi ve ilgili Turborepo yapılandırmalarını içeren tüm değişiklikler Git'e eklendi.
feat(mobile): Add Flutter mobile app shell and integrate with Turborepo mesajıyla yeni bir commit oluşturuldu.
Değişiklikler başarıyla GitHub'daki voya-monorepo deposuna push edildi.
Sonuç: Projenin en güncel hali, mobil uygulama iskeletiyle birlikte GitHub'da bulunmaktadır.
Harika! Artık hem API'miz hem de Mobil uygulamamız için temel iskeletler monorepo'muzda ve Turborepo ile yönetilmeye hazır.

GELİŞİM LOGU GÜNCELLEMESİ:

Tarih: 12 Mayıs 2025

Adım 6.A (Devam): API ile Veritabanına İlk Kayıt ve Okuma İşlemi

Yapılanlar:
Message entity'si (src/messages/message.entity.ts) oluşturuldu.
NestJS CLI ile MessagesModule, MessagesService, MessagesController oluşturuldu.
MessagesModule, TypeOrmModule.forFeature([Message]) ile Message entity'sini import etti.
MessagesService içine, Message repository'si kullanılarak create(createMessageDto) ve findAll() metodları eklendi. CreateMessageDto tanımlandı.
MessagesController içine /messages yolu için @Post() (mesaj oluşturma) ve @Get() (mesaj listeleme) endpoint'leri, @UsePipes(new ValidationPipe()) ile birlikte eklendi.
AppModule, MessagesModule'ü import etti.
main.ts dosyasına (isteğe bağlı olarak) app.setGlobalPrefix('api/v1'); ve global ValidationPipe eklendi.
API (npm run start:dev:api ile) yeniden başlatıldı.
curl veya Postman ile POST /api/v1/messages endpoint'ine JSON data gönderilerek yeni bir mesaj başarıyla oluşturuldu ve veritabanına kaydedildi.
curl veya Postman ile GET /api/v1/messages endpoint'inden veritabanındaki mesajlar başarıyla listelendi.
Kararlar/Notlar:
API endpoint'lerinin çalışması için global prefix (api/v1) ve controller path'i (messages) doğru şekilde birleştirildi.
TypeORM synchronize: true ayarı sayesinde messages tablosu veritabanında otomatik olarak oluşturuldu.
ValidationPipe temel düzeyde çalışıyor (eksik paketler daha önce kurulmuştu).
Sonuç: VoyaGo++ API'si artık lokal PostgreSQL veritabanına bağlanabiliyor, veri yazabiliyor ve okuyabiliyor. Temel CRUD işlemlerinden Create ve Read başarıyla test edildi.

GELİŞİM LOGU GÜNCELLEMESİ:

Tarih: 12 Mayıs 2025 (Devam)

Adım 8 (Devam): Mobil (Flutter) Uygulamasının Turborepo Entegrasyonunun Test Edilmesi ve Tamamlanması

Yapılanlar (Devamı): 5. turbo.json dosyasına, apps/mobile/package.json içindeki dev script'ini (flutter run) çalıştırabilmek için genel bir dev görev tanımı eklendi ("dev": { "cache": false, "persistent": true }). 6. voya-monorepo ana dizininden npm run start:dev:mobile komutu çalıştırıldı. 7. Turborepo, @voya/mobile paketindeki dev script'ini (yani flutter run) başarıyla tetikledi. 8. Flutter uygulaması, WSL içinde varsayılan hedef olan Linux için derlendi ve başlatıldı. XDG_RUNTIME_DIR ile ilgili bir hata alındı ancak uygulamanın çalışmasını engellemedi. Dart VM servisi ve Flutter DevTools erişilebilir hale geldi.
Kararlar/Notlar:
Turborepo, mobil uygulama için de temel görevleri (lint, test, build, run) başarıyla yönetebiliyor.
XDG_RUNTIME_DIR hatası, WSL'de Linux GUI uygulamalarıyla ilgili genel bir durum olup, Android/iOS/Web hedefleri için bir engel teşkil etmeyebilir. İleride gerekirse incelenecek.
Sonuç: Hem API hem de Mobil uygulamamız için temel geliştirme ve çalıştırma komutları Turborepo üzerinden yönetilebilir durumda. Monorepo'muzun temel iskeleti ve görev otomasyonu çalışıyor.

Tarih: 12 Mayıs 2025 (Devam)

Adım 9: Temel CI Pipeline'ının (GitHub Actions) Kurulumu ve Mobil Build Sorununun Giderilmesi

Yapılanlar:
.github/workflows/ci.yml dosyası oluşturuldu.
lint-test-build adlı bir iş (job) tanımlandı:
Node.js v20.x kuruldu.
nrwl/nx-set-shas@v4 ile etkilenen projelerin tespiti için base/head SHA'ları ayarlandı.
turbo run lint, turbo run test, turbo run build komutları sadece etkilenen projeler için çalıştırıldı. Bu adımlar API için başarıyla tamamlandı.
build-mobile-apk adlı ayrı bir iş tanımlandı:
Java ve Flutter SDK'ları kuruldu.
İlk denemede "No Android SDK found" hatası alındı.
Düzeltme: Workflow'a android-actions/setup-android@v3 adımı eklenerek GitHub Actions runner'ına tam bir Android SDK ortamı kurulması sağlandı.
flutter doctor -v adımı teşhis için eklendi.
Mobil bağımlılıkları kuruldu (flutter pub get).
npm run build:mobile (yani turbo run build --filter=@voya/mobile, o da flutter build apk --debug'ı çalıştırır) komutu çalıştırıldı.
Oluşan APK, actions/upload-artifact@v4 ile artifact olarak kaydedildi.
Kararlar/Notlar:
CI pipeline'ı push (main, develop, feature/* vb.) ve pull_request (main, develop, release/*) olaylarında tetiklenecek şekilde ayarlandı.
Mobil build için Android SDK'sının CI runner'ında ayrıca kurulması gerektiği anlaşıldı ve çözüldü.
nrwl/nx-set-shas kullanımı, Turborepo'nun affected mantığının CI'da da verimli çalışmasını sağlayacaktır.
Sonuç: Temel CI pipeline'ımız artık hem backend API hem de mobil uygulama için lint, test ve build işlemlerini başarıyla otomatik olarak gerçekleştiriyor. Mobil APK build'i de sorunsuz çalışıyor ve artifact olarak erişilebilir durumda.

GELİŞİM LOGU GÜNCELLEMESİ:

Tarih: 12 Mayıs 2025 (Devam)

Adım 9 (Devam): CI/CD Pipeline'ının Tamamlanması ve API'nin Fly.io'ya Deploy Edilmesi

Yapılanlar:
apps/api/Dockerfile güncellenerek geçerli bir taban imaj (node:current-alpine) kullanıldı ve build yolu düzeltildi.
GitHub Actions workflow (ci.yml) dosyasına permissions: { contents: read, packages: write } eklenerek GITHUB_TOKEN'a GHCR'a yazma izni verildi.
build-and-push-api-image job'ı, API Docker imajını başarıyla build edip GHCR'a (ghcr.io/voyalis/voya-api) push etti.
deploy-api-to-fly job'ı, GHCR'daki bu imajı kullanarak API'yi Fly.io'daki voya-api-test uygulamasına başarıyla deploy etti.
Tüm CI job'ları (api-ci, mobile-ci, build-and-push-api-image, deploy-api-to-fly) başarıyla tamamlandı.
Kararlar/Notlar:
Dockerfile'da doğru taban imajının ve build çıktı yollarının kullanılması kritikti.
GHCR'a push için GITHUB_TOKEN'a packages: write izninin verilmesi gerekti.
Fly.io deploy'u için fly.toml ve FLY_API_TOKEN doğru şekilde yapılandırıldı.
Sonuç: VoyaGo++ API'si için tam bir CI/CD pipeline'ı (lint, test, build, imaj oluşturma, GHCR'a push, Fly.io'ya deploy) başarıyla kuruldu. API'nin test ortamı artık otomatik olarak güncelleniyor. Mobil uygulama için de CI (lint, test, APK build) akışı çalışıyor.