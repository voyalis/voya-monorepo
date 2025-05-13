# --- Etap 1: Workspace Bağımlılıkları ---
    FROM node:current-alpine AS workspace-dependencies
    WORKDIR /usr/src/app
    
    COPY package.json package-lock.json* turbo.json ./
    COPY apps/api/package.json ./apps/api/
    COPY apps/mobile/package.json ./apps/mobile/
    
    RUN npm ci
    
    # --- Etap 2: Builder ---
    FROM node:current-alpine AS builder
    WORKDIR /usr/src/app
    
    # workspace-dependencies'tan node_modules'ı al
    COPY --from=workspace-dependencies /usr/src/app/node_modules ./node_modules
    COPY . .
    
    # Monorepo içindeki API'yi derle
    RUN npm run build:api
    
    # --- Etap 3: Runner (Production) ---
    FROM node:current-alpine AS runner
    WORKDIR /app
    
    COPY package.json package-lock.json* ./
    COPY apps/api/package.json ./apps/api/
    
    # Sadece production bağımlılıklarını kur
    RUN npm ci --omit=dev --filter=@voya/api
    
    # Builder aşamasından derlenmiş dist klasörünü alıp runner içine kopyala
    COPY --from=builder /usr/src/app/apps/api/dist ./dist
    
    ENV PORT 3000
    EXPOSE 3000
    
    RUN addgroup -S appgroup && adduser -S appuser -G appgroup
    USER appuser
    
    CMD ["node", "dist/main.js"]
    