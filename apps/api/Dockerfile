# Dockerfile (apps/api/Dockerfile)
# Multi-stage build for NestJS API within a Turborepo monorepo

# --- Stage 1: Install workspace dependencies (including devDeps for building) ---
    FROM node:current-alpine AS workspace-dependencies
    WORKDIR /usr/src/app
    
    # Copy root manifest files
    COPY package.json package-lock.json* turbo.json ./
    # Copy API and Mobile package definitions for hoisting
    COPY apps/api/package.json ./apps/api/
    COPY apps/mobile/package.json ./apps/mobile/
    
    # Install all dependencies (dev + prod)
    RUN npm ci
    
    
    # --- Stage 2: Build the API ---
    FROM node:current-alpine AS builder
    WORKDIR /usr/src/app
    
    # Reuse installed modules
    COPY --from=workspace-dependencies /usr/src/app/node_modules ./node_modules
    # Copy entire repo
    COPY . .
    
    # Trigger Turborepo build for the API package
    RUN npm run build:api
    
    
    # --- Stage 3: Create minimal runtime image ---
    FROM node:current-alpine AS runner
    WORKDIR /app
    
    # Copy manifests for production-only install
    COPY package.json package-lock.json* ./
    COPY apps/api/package.json ./apps/api/
    
    # Install only production deps for @voya/api
    RUN npm ci --omit=dev --ignore-scripts --filter=@voya/api
    
    # Copy built JS from builder stage (dist/src holds compiled output)
    COPY --from=builder /usr/src/app/apps/api/dist/src ./dist
    
    # Expose port and set environment
    ENV PORT=3000
    EXPOSE 3000
    
    # Drop to non-root user
    RUN addgroup -S appgroup && adduser -S appuser -G appgroup
    USER appuser
    
    # Start the app
    CMD ["node", "dist/main.js"]
    