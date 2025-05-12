# Etap 1: Dependency Kurulum & Sistem Paketlerini Güncelleme
FROM node:current-alpine AS dependencies
WORKDIR /usr/src/app

RUN apk add --no-cache --update alpine-keys \
 && apk add --no-cache --update tzdata \
 && apk add --no-cache --update git openssh \
 && apk upgrade --no-cache \
 && rm -rf /var/cache/apk/*

COPY package.json package-lock.json* turbo.json ./
COPY apps/api/package.json ./apps/api/

RUN npm ci

# Etap 2: Build Aşaması
FROM node:current-alpine AS builder
WORKDIR /usr/src/app

COPY --from=dependencies /usr/src/app/node_modules ./node_modules
COPY . .

RUN npx turbo run build --filter=@voya/api

# Etap 3: Minimal Runtime
FROM node:current-alpine AS runtime
WORKDIR /app

COPY package.json package-lock.json* turbo.json ./
COPY apps/api/package.json ./apps/api/
RUN npm ci --omit=dev --ignore-scripts

# Derlenmiş dosyaları al
# ESKİ SATIR: COPY --from=builder /usr/src/app/dist/apps/api ./dist
COPY --from=builder /usr/src/app/apps/api/dist ./dist

ENV PORT=3000
EXPOSE ${PORT}

RUN addgroup -S appgroup && adduser -S appuser -G appgroup
USER appuser

CMD ["node", "dist/main.js"]