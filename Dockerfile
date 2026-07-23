# --- Etapa 1: dependencias completas y pruebas (fail fast) ---
FROM node:20-alpine AS build
WORKDIR /app

# Capa de dependencias: se cachea mientras no cambien los manifiestos.
COPY package.json package-lock.json ./
RUN npm ci

# Solo lo necesario para ejecutar la bateria de pruebas.
COPY server.js db.js server.test.js ./
COPY public/ ./public/

# server.test.js escribe data/test-products.json junto a __dirname.
RUN mkdir -p data

# Si alguna prueba falla, RUN devuelve distinto de 0 y el build aborta aqui.
RUN npm test

# --- Etapa 2: imagen final, minima, solo lo necesario para ejecutar ---
FROM node:20-alpine AS runtime
ENV NODE_ENV=production
WORKDIR /app

# Dependencias de produccion unicamente; se limpia la cache para no inflar la capa.
# npm solo hace falta durante la construccion: el contenedor arranca con
# "node server.js" y nunca invoca npm ni npx. Se elimina en la misma capa para
# que el npm de la imagen base no quede en la imagen final; ahi vive el tar 6.2.1
# afectado por CVE-2026-59873. Es retirada de superficie de ataque, no exclusion
# del escaneo: no hay .trivyignore ni cambio de severidad.
COPY package.json package-lock.json ./
RUN npm ci --omit=dev \
    && npm cache clean --force \
    && rm -rf /usr/local/lib/node_modules/npm \
    && rm -f /usr/local/bin/npm /usr/local/bin/npx

# Codigo de ejecucion, tomado de la etapa build: la imagen final contiene
# exactamente los artefactos que pasaron las pruebas. Copiar desde build (y no
# desde el contexto) es ademas lo que impide que BuildKit descarte esa etapa
# por eliminacion de etapas muertas, que dejaria npm test sin ejecutar.
# server.test.js NO se copia.
COPY --from=build --chown=node:node /app/server.js /app/db.js ./
COPY --from=build --chown=node:node /app/public/ ./public/

# db.js escribe /app/data/products.json en el primer arranque.
RUN mkdir -p /app/data && chown -R node:node /app/data

USER node
EXPOSE 3000

HEALTHCHECK --interval=10s --timeout=3s --start-period=5s --retries=3 \
  CMD node -e "require('http').get('http://localhost:3000/health', r => process.exit(r.statusCode === 200 ? 0 : 1)).on('error', () => process.exit(1))"

# APP_VERSION y APP_COLOR se inyectan en tiempo de ejecucion.
# server.js ya usa v1/blue por defecto y trata SIMULATE_FAILURE ausente como false.
CMD ["node", "server.js"]
