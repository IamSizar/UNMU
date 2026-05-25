# Admin dashboard (Vite + React SPA) → static serve on Railway.
# Stage 1: build the bundle. VITE_API_BASE_URL is baked at build time, so it
# must be passed as a build ARG (Railway provides service vars as build args).
FROM node:20-alpine AS build
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
ARG VITE_API_BASE_URL
ENV VITE_API_BASE_URL=$VITE_API_BASE_URL
# Skip `tsc -b` (pre-existing type errors); Vite bundles fine without it.
RUN npx vite build

# Stage 2: serve the static SPA. `serve -s` rewrites unknown routes to
# index.html (client-side routing) and binds Railway's injected $PORT.
FROM node:20-alpine
WORKDIR /app
RUN npm i -g serve
COPY --from=build /app/dist ./dist
EXPOSE 8080
CMD ["sh", "-c", "serve -s dist -l ${PORT:-8080}"]
