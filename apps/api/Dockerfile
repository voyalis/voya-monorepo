# Dockerfile (apps/api/Dockerfile)

# --- Etap 1: Tüm Workspace Bağımlılıklarını Kurma (Ana Bağımlılıklar) ---
    FROM node:current-alpine AS workspace-dependencies
    WORKDIR /usr/src/app
    
    # Sistem paketlerini güvenlik yamalarıyla güncelle (Alpine'da apk kullanılır)
    # RUN apk add --no-cache --update alpine-keys && apk add --no-cache --update tzdata && apk add --no-cache --update git openssh && apk upgrade --no-cache && rm -rf /var/cache/apk/*
    
    COPY package.json package-lock.json* turbo.json ./
    COPY apps/api/package.json ./apps/api/
    COPY apps/mobile/package.json ./apps/mobile/
    
    RUN npm ci
    
    # --- Etap 2: Uygulamayı Build Etme (Builder) ---
    FROM node:current-alpine AS builder
    WORKDIR /usr/src/app
    
    COPY --from=workspace-dependencies /usr/src/app/node_modules ./node_modules
    COPY . . 
    
    # API'yi Turborepo ile build et.
    # Bu, ana package.json'daki "build:api" script'ini çalıştırır.
    # Çıktı, monorepo köküne göre apps/api/dist altına üretilir.
    # Docker içindeki tam yol /app/apps/api/dist olacaktır.
    RUN npm run build:api
    
    # --- Etap 3: Minimal Runtime İmajı ---
    FROM node:current-alpine AS runner
    WORKDIR /app
    
    # Production için gerekli bağımlılıkları TEMİZ bir şekilde kur.
    COPY package.json package-lock.json* ./
    COPY apps/api/package.json ./apps/api/
    # Sadece API'ye ait production bağımlılıklarını kur.
    RUN npm ci --omit=dev --ignore-scripts --filter=@voya/api
    
    # Builder aşamasından build edilmiş API dosyalarını (dist klasörü) al.
    COPY --from=builder /app/apps/api/dist ./dist
    # Bu komut, builder imajındaki /app/apps/api/dist klasörünün içeriğini
    # runner imajındaki /app/dist klasörüne kopyalar.
    
    ENV PORT 3000
    EXPOSE 3000
    
    RUN addgroup -S appgroup && adduser -S appuser -G appgroup
    USER appuser
    
    CMD ["node", "dist/main.js"]