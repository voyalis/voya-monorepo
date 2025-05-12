# Etap 1: Dependency Kurulum & Sistem Paketlerini Güncelleme
FROM node:current-alpine AS dependencies
WORKDIR /usr/src/app

# Sistem paketlerini güvenlik yamalarıyla güncelle (Alpine'da apk kullanılır)
RUN apk add --no-cache --update alpine-keys \
 && apk add --no-cache --update tzdata \
 && apk add --no-cache --update git openssh # Gerekirse (npm bazen git'e ihtiyaç duyar) \
 && apk upgrade --no-cache \
 && rm -rf /var/cache/apk/*

# Monorepo root’taki package.json’lar
COPY package.json package-lock.json* turbo.json ./
# API’ye özel package.json
COPY apps/api/package.json ./apps/api/

# Tüm workspace bağımlılıklarını kur
RUN npm ci

# Etap 2: Build Aşaması
FROM node:current-alpine AS builder
WORKDIR /usr/src/app

# Bir önceki aşamadan node_modules'ı kopyala
COPY --from=dependencies /usr/src/app/node_modules ./node_modules
# Tüm kaynak kodunu kopyala
COPY . .

# Turborepo ile sadece API’yı derle
RUN npx turbo run build --filter=@voya/api

# Etap 3: Minimal Runtime
FROM node:current-alpine AS runtime
WORKDIR /app

# Production için gerekli bağımlılıkları temiz bir şekilde kur
COPY package.json package-lock.json* turbo.json ./
COPY apps/api/package.json ./apps/api/
RUN npm ci --omit=dev --ignore-scripts

# Derlenmiş dosyaları al
COPY --from=builder /usr/src/app/dist/apps/api ./dist

ENV PORT=3000
EXPOSE ${PORT}

# Node kullanıcısını oluşturalım ve ona geçelim (güvenlik için iyi bir pratik)
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
USER appuser

CMD ["node", "dist/main.js"]
