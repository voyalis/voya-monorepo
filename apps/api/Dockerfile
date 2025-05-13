# Dockerfile (apps/api/Dockerfile)

# --- Etap 1: Build Aşaması (Builder) ---
# Güncel ve güvenli bir Node.js Alpine imajı kullanalım
FROM node:current-alpine AS builder
WORKDIR /app

# Sistem paketlerini güvenlik yamalarıyla güncelle (Alpine'da apk kullanılır)
# RUN apk add --no-cache --update alpine-keys \
#  && apk add --no-cache --update tzdata \
#  && apk add --no-cache --update git openssh \
#  && apk upgrade --no-cache \
#  && rm -rf /var/cache/apk/*
# YUKARIDAKİ APK KOMUTLARI ŞİMDİLİK YORUMDA KALSIN, BUILD SÜRESİNİ KISALTMAK İÇİN.
# EĞER 'npm ci' VEYA BAŞKA BİR ADIMDA 'git' GİBİ BİR ŞEY GEREKİRSE AKTİF EDERİZ.

# 1) Sadece bağımlılık tanımlarını kopyala (Docker katman cache'ini optimize etmek için)
# Monorepo kökündeki ana package.json ve lock dosyasını kopyala
COPY package.json package-lock.json* turbo.json ./
# API'ye özel package.json'ı kendi yoluna kopyala
COPY apps/api/package.json ./apps/api/
# Eğer paylaşımlı kütüphaneler (packages/*) varsa ve API'nin build'i için
# onların da package.json'ları gerekliyse, onları da benzer şekilde kopyalayın.
# Örnek: COPY packages/shared-utils/package.json ./packages/shared-utils/

# 2) Tüm workspace bağımlılıklarını kur (build için gerekli devDependencies dahil)
RUN npm ci
# Eğer sadece API ve onun workspace bağımlılıklarını kurmak isterseniz:
# RUN npm ci --filter=@voya/api...

# 3) Tüm kaynak kodunu kopyala (artık bağımlılıklar kurulduğu için)
COPY . .

# 4) API'yi Turborepo ile build et
# Bu komut, apps/api/package.json içindeki "build": "nest build" script'ini çalıştırır
# ve çıktıyı monorepo köküne göre apps/api/dist altına üretir.
# Docker içindeki tam yol /app/apps/api/dist olacaktır.
RUN npx turbo run build --filter=@voya/api

# --- Etap 2: Üretim İmajı (Runner) ---
FROM node:current-alpine AS runner
WORKDIR /app

# Sadece production bağımlılıklarını kur
# Ana package.json ve API'nin package.json'ını kopyala
COPY package.json package-lock.json* ./
COPY apps/api/package.json ./apps/api/
# Eğer paylaşımlı kütüphanelerin production bağımlılıkları varsa, onların package.json'larını da kopyala
RUN npm ci --omit=dev --ignore-scripts
# Sadece API'ye ait production bağımlılıklarını kurmak daha da optimize edebilir:
# RUN npm ci --omit=dev --ignore-scripts --filter=@voya/api...

# Build edilmiş API çıktılarını builder aşamasından kopyala
# Builder'daki WORKDIR /app idi. Build çıktısı /app/apps/api/dist altında olacak.
COPY --from=builder /app/apps/api/dist ./dist
# Bu komut, builder imajındaki /app/apps/api/dist klasörünün içeriğini
# runner imajındaki /app/dist klasörüne kopyalar.

# Ortam değişkeni olarak portu ayarla
ENV PORT 3000
EXPOSE 3000

# Node kullanıcısını oluştur ve ona geç (güvenlik için iyi pratik)
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
USER appuser

# Uygulamayı başlat (artık /app/dist/main.js bulunmalı)
CMD ["node", "dist/main.js"]
