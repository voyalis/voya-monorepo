# Etap 1: Dependency Kurulum & Sistem Paketlerini Güncelleme
FROM node:20.17.1-alpine3.18 AS dependencies
WORKDIR /usr/src/app

# Sistem paketlerini güvenlik yamalarıyla güncelle
RUN apk update \
 && apk upgrade --no-cache \
 && rm -rf /var/cache/apk/*

# Monorepo root’taki package.json’lar
COPY package.json package-lock.json* turbo.json ./
# API’ye özel package.json
COPY apps/api/package.json ./apps/api/

# Tüm bağımlılıkları yüklüyoruz
RUN npm ci

# Etap 2: Build Aşaması
FROM node:20.17.1-alpine3.18 AS builder
WORKDIR /usr/src/app

COPY --from=dependencies /usr/src/app/node_modules ./node_modules
COPY . .

# Turborepo ile sadece API’yı derle
RUN npx turbo run build --filter=@voya/api

# Etap 3: Minimal Runtime
FROM node:20.17.1-alpine3.18 AS runtime
WORKDIR /app

# Sadece production bağımlılıklarını kur
COPY package.json package-lock.json* turbo.json ./
COPY apps/api/package.json ./apps/api/
RUN npm ci --omit=dev --ignore-scripts

# Derlenmiş dosyaları al
COPY --from=builder /usr/src/app/dist/apps/api ./dist

ENV PORT=3000
EXPOSE ${PORT}

CMD ["node", "dist/main.js"]
