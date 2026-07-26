# Inventario App — CI/CD, Kubernetes y Blue-Green

Práctica de **Sistemas Distribuidos — Despliegue de Aplicaciones** (segundo interciclo).

| | |
|---|---|
| **Autores** | Josué Sáenz — [@JosueSaenz2006](https://github.com/JosueSaenz2006) y Edwin Angamarca|
| **Repositorio** | https://github.com/JosueSaenz2006/Practica-CI-CD |
| **Registro de imágenes** | `ghcr.io/josuesaenz2006/practica-ci-cd` (público) |
| **Aplicación** | `inventario-app` — catálogo de inventario Node.js/Express |
| **Clúster** | Minikube (driver docker), Kubernetes v1.35.1 |

---

## Índice

1. [Objetivo](#1-objetivo)
2. [Arquitectura](#2-arquitectura)
3. [Tecnologías](#3-tecnologías)
4. [Estructura del repositorio](#4-estructura-del-repositorio)
5. [La aplicación](#5-la-aplicación)
6. [Endpoints](#6-endpoints)
7. [Pruebas automatizadas](#7-pruebas-automatizadas)
8. [Dockerfile multi-stage](#8-dockerfile-multi-stage)
9. [Pipeline CI/CD](#9-pipeline-cicd)
10. [Barrera Trivy y CVE real corregida](#10-barrera-trivy-y-cve-real-corregida)
11. [Publicación en GHCR](#11-publicación-en-ghcr)
12. [Despliegue en Kubernetes](#12-despliegue-en-kubernetes)
13. [Readiness, liveness y arranque lento](#13-readiness-liveness-y-arranque-lento)
14. [Secret y secretKeyRef](#14-secret-y-secretkeyref)
15. [Rolling Update sin downtime](#15-rolling-update-sin-downtime)
16. [Blue-Green](#16-blue-green)
17. [Persistencia efímera y recreación de pods](#17-persistencia-efímera-y-recreación-de-pods)
18. [Rolling Update vs Blue-Green](#18-rolling-update-vs-blue-green)
19. [Métricas DORA](#19-métricas-dora)
20. [Instalación y ejecución](#20-instalación-y-ejecución)
21. [Comandos para reproducir las evidencias](#21-comandos-para-reproducir-las-evidencias)
22. [Evidencias verificadas](#22-evidencias-verificadas)
23. [Conclusiones](#23-conclusiones)

---

## 1. Objetivo

Llevar un cambio de código desde un commit hasta usuarios reales, de forma automatizada, segura y sin interrupciones, cubriendo el ciclo completo:

```
commit → pruebas → imagen → escaneo de seguridad → registro → Kubernetes → tráfico real
```

Se implementan además tres componentes adicionales sobre el requisito base — **escaneo de vulnerabilidades bloqueante**, **readiness realista con arranque lento** y **gestión de credenciales con Secret** — y dos estrategias de despliegue: **Rolling Update** y **Blue-Green**.

El criterio que atraviesa toda la práctica: **ningún usuario debe recibir un error durante un despliegue**. Cada afirmación de este documento está respaldada por mediciones reproducibles, no por suposiciones.

## 2. Arquitectura

```
┌──────────────┐   git push    ┌────────────────────────────────────────┐
│  Desarrollo  │──────────────▶│         GitHub Actions (CI)            │
│  local       │               │                                        │
└──────────────┘               │  build-test:  npm ci → npm test        │
                               │       ↓ needs                          │
                               │  build-push:  docker build (local)     │
                               │               ↓                        │
                               │               Trivy CRITICAL  ◀── barrera
                               │               ↓ (solo si pasa)         │
                               │               push :SHA + :latest      │
                               └───────────────┬────────────────────────┘
                                               │
                                               ▼
                                  ghcr.io/josuesaenz2006/practica-ci-cd
                                        (público, sin credenciales)
                                               │
                                     kubectl (Continuous Delivery)
                                               ▼
        ┌──────────────────────────────────────────────────────────────┐
        │                    Minikube — namespace default              │
        │                                                              │
        │   Service inventario-app  (NodePort 10.100.232.220:32133)    │
        │            selector: app=inventario-app, slot=<blue|green>   │
        │                          │                                   │
        │             ┌────────────┴────────────┐                      │
        │             ▼                         ▼                      │
        │   Deployment ...-blue        Deployment ...-green            │
        │   4 réplicas, slot=blue      4 réplicas, slot=green          │
        │   imagen f5b43b94            imagen 2ebe61cc                 │
        │             │                         │                      │
        │             └───────────┬─────────────┘                      │
        │                         ▼                                    │
        │              Secret inventario-app-secret                    │
        │              (API_KEY vía secretKeyRef)                      │
        └──────────────────────────────────────────────────────────────┘
```

El pipeline **no** despliega en Kubernetes: Minikube corre en una máquina local, inalcanzable desde los runners de GitHub. El paso final lo ejecuta una persona con `kubectl`. Eso hace de esto **Continuous Delivery**, no Continuous Deployment.

## 3. Tecnologías

| Capa | Herramienta |
|---|---|
| Aplicación | Node.js 20 · Express 4.19 |
| Persistencia | JSON en disco (`db.js`), sembrado con 3 productos |
| Pruebas | `node --test` (runner nativo, sin dependencias externas) |
| Contenedor | Docker multi-stage sobre `node:20-alpine` |
| CI/CD | GitHub Actions |
| Seguridad | Trivy `v0.36.0` (fijado por SHA), severidad CRITICAL, bloqueante |
| Registro | GitHub Container Registry (GHCR), paquete público |
| Orquestación | Kubernetes v1.35.1 sobre Minikube (driver docker) |
| Credenciales | Kubernetes Secret + `secretKeyRef` |

## 4. Estructura del repositorio

```
.
├── .github/workflows/ci-cd.yml      Pipeline: build-test → build-push (con Trivy)
├── Dockerfile                       Multi-stage; elimina npm de la imagen final
├── .dockerignore / .gitignore
├── package.json / package-lock.json
├── server.js                        Express: rutas, readiness, detección de API_KEY
├── db.js                            Persistencia JSON + canAccessDb()
├── server.test.js                   13 pruebas automatizadas
├── data/.gitkeep                    Directorio de datos (contenido no versionado)
├── public/
│   ├── index.html                   Interfaz + notas de versión
│   ├── app.js
│   └── styles.css
└── k8s/
    ├── deployment.yaml              Despliegue directo, 4 réplicas
    ├── service.yaml                 Service NodePort
    └── blue-green/
        ├── deployment-blue.yaml     slot=blue,  imagen estable
        ├── deployment-green.yaml    slot=green, imagen nueva
        └── service.yaml             Service único; el selector decide el tráfico
```

## 5. La aplicación

`inventario-app` es un catálogo de productos con interfaz web y API REST. Cada pod muestra qué versión sirve, en qué color y desde qué host — eso es lo que permite *ver* un despliegue ocurriendo.

Toda la configuración entra por variables de entorno, nunca escrita en el código:

| Variable | Efecto | Por defecto |
|---|---|---|
| `PORT` | Puerto de escucha | `3000` |
| `APP_VERSION` | Versión reportada en `/version` | `v1` |
| `APP_COLOR` | Color reportado en `/version` | `blue` |
| `STARTUP_DELAY_SECONDS` | Segundos que la app tarda en declararse lista | `0` |
| `SIMULATE_FAILURE` | Si es `true`, `/health` responde 500 | `false` |
| `API_KEY` | Credencial; solo se publica si está configurada | ausente |

Consecuencia: **la misma imagen** sirve para blue y para green. Lo único que cambia entre entornos es la configuración externa — nunca el artefacto.

## 6. Endpoints

| Método | Ruta | Descripción |
|---|---|---|
| `GET` | `/` | Interfaz web con el catálogo y las notas de versión |
| `GET` | `/health` | Sonda de Kubernetes. `503` mientras arranca, `500` si falla, `200` si está listo |
| `GET` | `/version` | `version`, `color`, `hostname` y `apiKeyConfigured` |
| `GET` | `/api/products` | Lista de productos |
| `GET` | `/api/products/:id` | Un producto (404 si no existe) |
| `POST` | `/api/products` | Crea (400 si falta `name` o `sku`) |
| `PATCH` | `/api/products/:id` | Actualiza |
| `DELETE` | `/api/products/:id` | Elimina (204) |

Respuestas reales del clúster:

```json
GET /health   → {"status":"ok","ready":true}
GET /health   → {"status":"starting","ready":false}     (durante el arranque, HTTP 503)
GET /version  → {"version":"green-2ebe61cc","color":"green",
                 "hostname":"inventario-app-green-6cc7556d5c-lbrkl","apiKeyConfigured":true}
```

`/version` expone `apiKeyConfigured` como **booleano**. Nunca el valor, ni su longitud, prefijo, hash o fragmento.

## 7. Pruebas automatizadas

13 pruebas con el runner nativo de Node (`node --test`), sin frameworks externos:

```
✔ GET /health responde 200 y status ok
✔ GET /version responde con version y color
✔ POST /api/products crea un producto y GET /api/products lo lista
✔ DELETE /api/products/:id elimina el producto
✔ POST /api/products sin name/sku responde 400
✔ STARTUP_DELAY_SECONDS en 0 deja /health listo de inmediato
✔ durante el arranque lento /health responde 503 y no listo
✔ al cumplirse el retraso /health pasa de 503 a 200
✔ un STARTUP_DELAY_SECONDS invalido no rompe la aplicacion
✔ sin API_KEY la aplicacion informa que no esta configurada
✔ con API_KEY la aplicacion informa que esta configurada
✔ ninguna respuesta expone el valor de la credencial
✔ el resto de endpoints responde durante el arranque lento

tests 13 | pass 13 | fail 0
```

Se ejecutan en **tres lugares**: local, dentro del `docker build`, y en GitHub Actions. No es redundancia: es el mismo control situado a distancias distintas de producción, y en cualquiera de los tres detiene el avance.

La prueba de no filtración recorre todas las rutas verificando sobre el cuerpo crudo que la credencial no aparece, y comprueba que `/version` devuelve exactamente cuatro claves —`apiKeyConfigured`, `color`, `hostname`, `version`— lo que descarta cualquier campo derivado añadido por descuido.

## 8. Dockerfile multi-stage

Dos etapas: una prueba, otra ejecuta.

```dockerfile
# --- Etapa 1: dependencias completas y pruebas (fail fast) ---
FROM node:20-alpine AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY server.js db.js server.test.js ./
COPY public/ ./public/
RUN mkdir -p data
RUN npm test          # si falla, el build entero aborta aqui

# --- Etapa 2: imagen final, minima ---
FROM node:20-alpine AS runtime
ENV NODE_ENV=production
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev \
    && npm cache clean --force \
    && rm -rf /usr/local/lib/node_modules/npm \
    && rm -f /usr/local/bin/npm /usr/local/bin/npx
COPY --from=build --chown=node:node /app/server.js /app/db.js ./
COPY --from=build --chown=node:node /app/public/ ./public/
RUN mkdir -p /app/data && chown -R node:node /app/data
USER node
EXPOSE 3000
HEALTHCHECK --interval=10s --timeout=3s --start-period=5s --retries=3 \
  CMD node -e "require('http').get('http://localhost:3000/health', r => process.exit(r.statusCode === 200 ? 0 : 1)).on('error', () => process.exit(1))"
CMD ["node", "server.js"]
```

Decisiones que importan:

- **`COPY --from=build`** en vez de copiar del contexto. No es cosmético: si la etapa `build` no aportara ningún archivo a la imagen final, BuildKit la descartaría por eliminación de etapas muertas y **`npm test` nunca se ejecutaría**. Copiar desde ella la mantiene viva.
- **`server.test.js` no se copia** a la imagen final: el código de pruebas no viaja a producción.
- **`USER node`** (uid 1000): el contenedor no corre como root.
- **npm eliminado** de la imagen final — ver la sección siguiente.

Verificado en la imagen publicada:

```
uid=1000(node) gid=1000(node) groups=1000(node)
npm: AUSENTE
npx: AUSENTE
estado: healthy
```

## 9. Pipeline CI/CD

[`.github/workflows/ci-cd.yml`](.github/workflows/ci-cd.yml) — se dispara con cada `push` a `main`.

```
build-test                        build-push  (needs: build-test)
├─ Checkout                       ├─ Checkout
├─ Configurar Node 20             ├─ Definir referencias de imagen
├─ npm ci                         ├─ Construir imagen local (SIN publicar)
└─ npm test                       ├─ Escanear con Trivy  ◀── barrera bloqueante
                                  ├─ Login en GHCR
                                  ├─ Etiquetar latest
                                  ├─ Publicar etiqueta SHA
                                  ├─ Publicar etiqueta latest
                                  └─ Verificar referencias publicadas
```

Puntos clave:

- **`needs: build-test`** — no se construye nada si las pruebas fallan.
- **La imagen se construye antes de cualquier login.** Se escanea primero y solo se publica si pasa. Una imagen vulnerable jamás llega al registro.
- **`IMAGE_NAME` en minúsculas fijas.** `${{ github.repository }}` devolvería `JosueSaenz2006/Practica-CI-CD` y GHCR rechaza mayúsculas.
- **`BUILD_CREATED` toma la fecha del *commit*, no la del runner** — el mismo commit produce siempre el mismo valor.
- **Trivy fijado por SHA** (`ed142fd0...`), no por etiqueta: las etiquetas de GitHub son mutables.

## 10. Barrera Trivy y CVE real corregida

Trivy escanea con `severity: CRITICAL`, `exit-code: 1`, `ignore-unfixed: false`. Falla el job y detiene la publicación.

**No es teórico. Falló de verdad:**

| | |
|---|---|
| Run fallido | [30025704991](https://github.com/JosueSaenz2006/Practica-CI-CD/actions/runs/30025704991) — commit `d20dec7d`, 2026-07-23T16:34:36Z |
| Vulnerabilidad | `tar 6.2.1` — **CVE-2026-59873** |
| Origen | El `npm` que trae la imagen base `node:20-alpine` |
| Corrección | commit `f342248` — *fix(security): elimina npm vulnerable de la imagen runtime* |

```dockerfile
RUN npm ci --omit=dev \
    && npm cache clean --force \
    && rm -rf /usr/local/lib/node_modules/npm \
    && rm -f /usr/local/bin/npm /usr/local/bin/npx
```

`npm` solo hace falta durante la construcción: el contenedor arranca con `node server.js` y nunca lo invoca. Se elimina **en la misma capa** para que no quede en la imagen final — borrarlo en una capa posterior no lo quitaría del historial.

**Es retirada de superficie de ataque, no exclusión del escaneo.** No hay `.trivyignore`, ni rebaja de severidad, ni `ignore-unfixed: true`. La vulnerabilidad no se silenció: se eliminó el paquete que la traía. Todos los runs posteriores pasan la barrera con el escaneo intacto.

## 11. Publicación en GHCR

Cada build publica dos etiquetas: `:<sha-completo>` (inmutable) y `:latest` (móvil).

**Los despliegues usan siempre el SHA completo, nunca `latest`.** Una etiqueta móvil hace que el mismo manifiesto signifique cosas distintas en momentos distintos; el SHA identifica un artefacto exacto y reproducible.

El paquete es **público**: no se necesita `imagePullSecret` ni `docker login`. Verificado con resolución anónima (token público de GHCR, sin credenciales):

```
tag f5b43b94567701ecc46f15805aa07ba8d36e6c68
  → sha256:e4c0b2910e762c3c2a553dca07d1181a8896b821f0e57f73bbe9f075aa015cb9

tag 2ebe61ccd00bc05bf942d6d172cd5265d200142f
  → sha256:e40a90d19a9eda178504d3fbf013d2526944acd79141fde80a0349b38402528e
```

Los pods reportan exactamente esos digests en su `imageID`.

## 12. Despliegue en Kubernetes

[`k8s/deployment.yaml`](k8s/deployment.yaml) — 4 réplicas con estrategia `RollingUpdate`:

```yaml
spec:
  replicas: 4
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 1     # nunca menos de 3 disponibles
      maxSurge: 1           # nunca más de 5 pods activos
```

[`k8s/service.yaml`](k8s/service.yaml) — `Service` de tipo NodePort, `port 80 → targetPort 3000`, sin `nodePort` fijado (lo asigna Kubernetes).

Balanceo verificado con 40 peticiones desde dentro del clúster contra el ClusterIP:

```
inventario-app-fc49cdcbb-2gvhn → 10
inventario-app-fc49cdcbb-g8g7f →  8
inventario-app-fc49cdcbb-v74z4 → 12
inventario-app-fc49cdcbb-w5mt6 → 10
```

> **Nota metodológica.** `kubectl port-forward service/...` **no** sirve para demostrar balanceo: reenvía a un único pod de respaldo y mantiene esa conexión. Un primer intento dio 40/40 al mismo pod, lo que parecía un fallo de balanceo y no lo era. El balanceo real ocurre en el ClusterIP vía kube-proxy, así que la medición se repitió desde dentro del clúster.

DNS interno resuelto por CoreDNS:

```
inventario-app                           → 10.100.232.220
inventario-app.default.svc.cluster.local → 10.100.232.220
```

## 13. Readiness, liveness y arranque lento

Una aplicación real no está lista en el instante en que su proceso arranca: conecta a bases de datos, carga caché, calienta. `STARTUP_DELAY_SECONDS` simula eso de forma honesta.

```js
function parseStartupDelaySeconds(raw) {
  const seconds = Number(raw);
  if (!Number.isFinite(seconds) || seconds < 0) return 0;   // ausente/inválido/negativo → 0
  return seconds;
}

function createApp() {
  const startupDelayMs = parseStartupDelaySeconds(process.env.STARTUP_DELAY_SECONDS) * 1000;
  const startedAt = Date.now();

  app.get('/health', (req, res) => {
    if (Date.now() - startedAt < startupDelayMs) {
      return res.status(503).json({ status: 'starting', ready: false });
    }
    if (SIMULATE_FAILURE || !db.canAccessDb()) {
      return res.status(500).json({ status: 'error', reason: '...' });
    }
    res.status(200).json({ status: 'ok', ready: true });
  });
```

Se compara una marca de tiempo en cada petición: **no bloquea el event loop**, no usa `sleep`.

Probes calibradas para ese arranque:

```yaml
readinessProbe:                    livenessProbe:
  httpGet: /health:3000              httpGet: /health:3000
  initialDelaySeconds: 1             initialDelaySeconds: 20
  periodSeconds: 2                   periodSeconds: 10
  timeoutSeconds: 1                  timeoutSeconds: 2
  failureThreshold: 10               failureThreshold: 3
```

- Readiness tolera hasta **21 s** (1 + 2×10) sin estar listo, por encima de los 12 s de arranque.
- Liveness empieza a los **20 s**, después del arranque: no reinicia un pod que solo está calentando.

No se añadió `startupProbe`: con esos valores no era necesaria, y habría desplazado la evidencia de readiness que se quería demostrar.

**Ciclo de vida real de un pod, medido cada 300 ms:**

```
18:29:36.875  Pending  NOTready  ausente de Endpoints
18:29:40.703  Running  NOTready  epNOTREADY   ← Running, pero SIN recibir tráfico
18:29:53.487  Running  ready     epREADY      ← incorporado al Service
```

**12.8 s** entre `Running` y `ready` — los 12 s configurados más la latencia de sondeo. `restartCount = 0` durante todo el ciclo. Durante esos 12.8 s las réplicas antiguas cubrieron el 100 % del tráfico y los endpoints listos nunca bajaron de 3.

> **Corrección de método.** El primer monitor marcaba un pod como "en Endpoints" por la mera *presencia* de su IP, y daba positivo incluso para pods no listos. Kubernetes **sí** lista la dirección, pero con `conditions.ready: false`, y kube-proxy no le enruta. La medición se rehízo leyendo `conditions.ready` por dirección; los datos anteriores provienen del monitor corregido.

### Por qué más réplicas no sustituyen a un readiness correcto

Subir `replicas` no arregla un readiness mal configurado: **lo multiplica**. Si la probe declara listo un pod que todavía no puede atender, el Service lo mete en Endpoints y kube-proxy le enruta tráfico que fallará — con 4 réplicas mal configuradas hay 4 destinos rotos en lugar de 1. Cada pod extra consume CPU y memoria sin aportar capacidad útil, y alarga el rollout.

La garantía no es *cuántos* pods hay, sino que **ninguno reciba tráfico hasta que pueda servirlo**. Eso es exactamente lo que muestra la traza: el pod estuvo `Running` 12.8 s sin recibir una sola petición.

## 14. Secret y secretKeyRef

La credencial se creó por entrada estándar, sin pasar por ningún archivo:

```bash
kubectl create secret generic inventario-app-secret \
  --from-literal=API_KEY="$env:INVENTARIO_API_KEY" \
  --dry-run=client -o yaml | kubectl apply -f -
```

Verificación que **no** revela el contenido (el YAML completo se omite a propósito: `data` es Base64 reversible, no cifrado):

```
NAME                    TYPE     DATA   AGE
inventario-app-secret   Opaque   1      ...

Data
====
API_KEY:  32 bytes
```

Consumo en el manifiesto — sin `value:`, sin `stringData:`:

```yaml
- name: API_KEY
  valueFrom:
    secretKeyRef:
      name: inventario-app-secret
      key: API_KEY
```

La aplicación comprueba presencia, nunca contenido:

```js
function isApiKeyConfigured() {
  const apiKey = process.env.API_KEY;
  return typeof apiKey === 'string' && apiKey.trim().length > 0;
}
```

Evidencia en el clúster:

```
kubectl describe pod →
  API_KEY: <set to the key 'API_KEY' in secret 'inventario-app-secret'>  Optional: false

GET /version → {"...","apiKeyConfigured":true}
claves devueltas: version, color, hostname, apiKeyConfigured   (ninguna otra)
```

**La credencial no existe en el repositorio.** Comprobado contra el valor real leído del Secret, sin imprimirlo en ningún momento:

```
git grep en el árbol de trabajo : no encontrado
git log -S en toda la historia  : no encontrado
git grep en todos los commits   : no encontrado
archivos .env versionados       : ninguno
Secret versionado               : no
```

## 15. Rolling Update sin downtime

Actualización de la versión 1 (`blue`) a la versión 2 (`green`) con una **única** operación atómica — nunca `set image` seguido de `set env`, que crearía dos revisiones:

```bash
kubectl patch deployment inventario-app --type=strategic --patch-file patch.json
```

```
DEPLOY_UPDATE_START    : 2026-07-26T17:51:43.323Z
DEPLOY_UPDATE_COMPLETE : 2026-07-26T17:51:55.604Z
Duración: 12.28 s   →   una sola revisión nueva (historial: 1, 2)
```

**Disponibilidad medida** — monitor interno a ~5 req/s contra el ClusterIP:

```
Solicitudes           : 530   (×2 endpoints = 1060 llamadas HTTP)
HTTP 200              : 1060  (100.00 %)
Distinto de 200       : 0
Errores de conexión   : 0
Versiones observadas  : f3422484 (blue), 7577d9b0 (green)
Hostnames observados  : 8  (4 antiguos + 4 nuevos)
```

Solapamiento real: **23 peticiones** en las que ambas versiones respondían por el mismo Service (primera `green` en seq 423, última `blue` en seq 446).

**Comportamiento frente a la estrategia declarada:**

```
Mínimo availableReplicas : 3    →  maxUnavailable=1 (4−1=3)   ✓
Máximo de pods activos   : 5    →  maxSurge=1       (4+1=5)   ✓
```

> **Nota.** Un primer cálculo dio 8 pods, que parecía violar `maxSurge`. No lo era: `kubectl get pods` sigue listando los pods en terminación durante su *graceful shutdown*. Descontándolos, el máximo activo fue exactamente 5.

## 16. Blue-Green

Dos entornos completos y simultáneos, un único Service. El tráfico se cambia **solo** en el selector.

| | blue | green |
|---|---|---|
| Deployment | `inventario-app-blue` | `inventario-app-green` |
| Labels / selector | `app=inventario-app`, `slot=blue` | `app=inventario-app`, `slot=green` |
| Réplicas | 4 | 4 |
| Imagen | `:f5b43b94...` | `:2ebe61cc...` |
| Digest | `sha256:e4c0b291...` | `sha256:e40a90d1...` |
| `APP_VERSION` | `blue-f5b43b94` | `green-2ebe61cc` |

Ambos comparten `STARTUP_DELAY_SECONDS=12`, las mismas probes, los mismos `resources`, el mismo `secretKeyRef` y `containerPort 3000`.

### El Service, invariable

```yaml
selector:
  app: inventario-app
  slot: green          # blue ⟷ green: el único cambio del cutover
```

`clusterIP` y `nodePort` **no se escriben** en el manifiesto, para que al aplicarlo sobre el Service existente se conserven. Confirmado en las 160 muestras del monitor: **un único valor** de cada uno durante toda la operación.

```
ClusterIP = 10.100.232.220     NodePort = 32133     (antes, durante y después)
```

### Green validado antes de recibir tráfico

Esta es la ventaja que Rolling Update no puede ofrecer. Con green ya 4/4 Ready y el Service aún en blue:

```
GREEN consultado DIRECTAMENTE (10.244.0.237:3000, sin pasar por el Service):
  {"version":"green-2ebe61cc","color":"green","apiKeyConfigured":true}
  {"status":"ok","ready":true}
  texto "Version 3"  → encontrado

SERVICE en el mismo instante:
  {"version":"blue-f5b43b94","color":"blue","apiKeyConfigured":true}
  texto "Version 3"  → NO encontrado

Endpoints: .232 .233 .234 .235   (solo blue)
IPs green: .237 .238 .239 .240   (ninguna en Endpoints)
40 GET al Service → 4 pods blue, 0 respuestas green
```

### Cutover, rollback y cutover final

```bash
kubectl patch service inventario-app --type=strategic \
  -p '{"spec":{"selector":{"app":"inventario-app","slot":"green"}}}'
```

| Operación | Inicio (UTC) | Fin (UTC) | Duración |
|---|---|---|---|
| **Cutover** blue → green | 19:00:21.990 | 19:00:22.483 | **493 ms** |
| **Rollback** green → blue | 19:02:04.461 | 19:02:04.887 | **426 ms** |
| **Cutover final** → green | 19:02:39.218 | 19:02:39.632 | **415 ms** |

Ningún Deployment fue modificado en ninguna de las tres operaciones. El monitor de estado registra la transición sin ningún estado intermedio:

```
19:00:05.392  selector=blue   epReady=4  ips=.233 .234 .232 .235
19:00:22.483  selector=green  epReady=4  ips=.240 .239 .238 .237
```

`epReady=4` en todo momento: nunca hubo endpoints vacíos ni parciales.

### Disponibilidad durante toda la maniobra

```
Solicitudes           : 799   (×2 endpoints = 1598 llamadas HTTP)
HTTP 200              : 1598  (100.00 %)
Distinto de 200       : 0
Errores de conexión   : 0
Colores observados    : blue, green
Hostnames             : 4 blue + 4 green

Transiciones de color — exactamente una por cambio de selector:
  seq=  1  18:59:53  blue    ← línea base
  seq=135  19:00:22  green   ← cutover
  seq=603  19:02:04  blue    ← rollback
  seq=762  19:02:39  green   ← cutover final
```

Estado final: Service en **green**, con **blue intacto a 4/4** como respaldo inmediato. Blue no se escaló a cero ni se eliminó — ahí reside el valor de la estrategia.

## 17. Persistencia efímera y recreación de pods

`db.js` escribe en `/app/data/products.json`, dentro del sistema de archivos del contenedor. No hay `volumeMount`, ni `PersistentVolumeClaim`, ni base de datos externa. Consecuencia: **cada pod tiene su propia copia de los datos, y esa copia desaparece cuando el pod se recrea.**

### Procedimiento reproducible

La verificación se hace con `port-forward` **a un pod concreto**, nunca contra el Service. Usar el Service daría resultados ambiguos: reparte cada petición entre las cuatro réplicas, que son independientes entre sí, así que un producto creado en una réplica parecería aparecer y desaparecer de forma intermitente según qué pod respondiera. El `port-forward` a un pod fija el destino y elimina esa ambigüedad — es el mismo comportamiento que en la sección 12 desaconseja usarlo para medir balanceo, aprovechado aquí a favor.

```bash
# 1. Elegir un pod concreto
OLD=$(kubectl get pods -l 'app=inventario-app,slot=green' -o jsonpath='{.items[0].metadata.name}')

# 2. Acceso directo a ese pod (no al Service)
kubectl port-forward pod/$OLD 8090:3000

# 3. Crear un producto desde la interfaz en http://127.0.0.1:8090
#    y comprobarlo en ese mismo pod
curl -s http://127.0.0.1:8090/api/products

# 4. Eliminar ese pod: el ReplicaSet lo repone automaticamente
kubectl delete pod $OLD
kubectl rollout status deployment/inventario-app-green --timeout=180s

# 5. Repetir la consulta contra el pod de reemplazo
NEW=$(kubectl get pods -l 'app=inventario-app,slot=green' -o jsonpath='{.items[0].metadata.name}')
kubectl port-forward pod/$NEW 8090:3000
curl -s http://127.0.0.1:8090/api/products
```

### Producto de prueba

| Campo | Valor |
|---|---|
| Nombre | `Producto temporal de persistencia` |
| SKU | `PERSISTENCIA-20260726-194704` |
| Stock | 7 |
| Precio | 9.99 |
| ID asignado | 4 |

El SKU lleva marca de tiempo para no confundirse con los tres productos del seed.

### Pods implicados

| | Pod anterior | Pod de reemplazo |
|---|---|---|
| Nombre | `inventario-app-green-6cc7556d5c-c2wnp` | `inventario-app-green-6cc7556d5c-8kcl2` |
| UID | `f3e986ff-1397-40b4-98b4-615238d81221` | `d5bdd3db-55e7-4552-8bde-52e1d8c2bec5` |
| IP | `10.244.0.237` | `10.244.0.244` |
| ReplicaSet | `inventario-app-green-6cc7556d5c` | el mismo |
| Imagen | `sha256:e40a90d1...` | la misma |
| restartCount | 0 | 0 |

**UID distinto con el mismo ReplicaSet y la misma imagen:** no es un reinicio del contenedor, es un objeto Pod nuevo con su propio sistema de archivos.

```
DELETE_POD_START  : 2026-07-26T19:50:50.965Z
REPLACEMENT_READY : 2026-07-26T19:51:36.511Z
Duración del reemplazo: 45.5 s
```

### Observación antes / después

**Antes**, en el pod `c2wnp`:

```json
[{"id":2,"name":"Mouse inalambrico","sku":"MOU-002",...},
 {"id":4,"name":"Producto temporal de persistencia","sku":"PERSISTENCIA-20260726-194704","stock":7,"price":9.99}]
```

**Después**, en el pod `8kcl2`:

```json
[{"id":1,"name":"Teclado mecanico","sku":"TEC-001","stock":25,"price":45.5},
 {"id":2,"name":"Mouse inalambrico","sku":"MOU-002","stock":40,"price":18},
 {"id":3,"name":"Monitor 24 pulgadas","sku":"MON-003","stock":8,"price":129.99}]
```

El producto temporal desapareció, y se confirmó en tres consultas espaciadas que no reaparece.

La prueba resultó más concluyente de lo previsto porque el estado del pod `c2wnp` divergía del de la imagen **en las dos direcciones**: tenía un producto añadido (`PERSISTENCIA-...`) y le faltaban dos del seed (`TEC-001` y `MON-003`, eliminados durante la manipulación de la interfaz de ese pod). Tras la recreación, el pod nuevo mostró **exactamente los tres productos del seed con sus ids 1, 2 y 3**: lo añadido se perdió y lo borrado volvió. El estado no se degradó ni se conservó parcialmente — se reconstruyó por completo desde la imagen.

Mientras tanto, los otros tres pods green conservaron sus tres productos del seed y **nunca vieron** el producto temporal, lo que demuestra directamente que las copias son independientes:

```
10.244.0.237  c2wnp   MOU-002, PERSISTENCIA-20260726-194704
10.244.0.238  plxq6   TEC-001, MOU-002, MON-003
10.244.0.239  lbrkl   TEC-001, MOU-002, MON-003
10.244.0.240  qdvc9   TEC-001, MOU-002, MON-003
```

### Explicación

Un contenedor escribe sobre una *writable layer* propia, apilada sobre las capas de solo lectura de la imagen. Esa capa pertenece al contenedor, no al Pod ni al Deployment: cuando el Pod se elimina, se elimina con él. El ReplicaSet crea entonces un Pod nuevo a partir de la misma imagen, con una writable layer vacía, y `db.js` vuelve a sembrar los tres productos porque no encuentra `products.json`.

Durante toda la prueba el Deployment siguió en 4/4 y el Service continuó sirviendo con las otras tres réplicas: la disponibilidad no se vio afectada, solo los datos escritos en ese pod.

**Esto es una limitación deliberada de la práctica, no un defecto a corregir.** La aplicación se diseñó sin estado persistente porque el objetivo es demostrar el ciclo de CI/CD y las estrategias de despliegue. Una aplicación real que necesitara conservar estos datos requeriría un `PersistentVolume` con su `PersistentVolumeClaim` y un `volumeMount`, o —más habitual— una base de datos externa al clúster. Con cuatro réplicas, además, un volumen por pod tampoco bastaría: harían falta almacenamiento compartido (`ReadWriteMany`) o una base de datos única para todas.

## 18. Rolling Update vs Blue-Green

| | Rolling Update | Blue-Green |
|---|---|---|
| Entornos | Uno; los pods se reemplazan dentro del mismo Deployment | Dos completos e independientes, simultáneos |
| Mecanismo | ReplicaSets nuevo/viejo con `maxSurge` / `maxUnavailable` | Selector del Service: `slot: blue` ⟷ `slot: green` |
| Transición | Gradual: 4→3 disponibles, hasta 5 pods activos, **12.28 s** | Atómica: **493 ms**, sin estado intermedio |
| Coexistencia | Temporal y forzada, solo durante el reemplazo | Permanente y deliberada, ambos 4/4 |
| Validación previa | Imposible: el pod nuevo entra en Endpoints al estar Ready | Green validado por completo sin un solo usuario |
| Rollback | `rollout undo` **reconstruye** pods (segundos, contenedores nuevos) | Cambia el selector: **426 ms, 0 pods recreados, 0 reinicios** |
| Coste en recursos | 4–5 pods | 8 pods permanentes (el doble) |
| Cuándo conviene | Cambios rutinarios de bajo riesgo | Versiones que exigen validación en el entorno real antes de exponerse |

La diferencia esencial: en Rolling Update el rollback **reconstruye** los pods; en Blue-Green el entorno anterior sigue vivo e intacto, así que revertir es solo redirigir tráfico. Eso explica los 426 ms frente a segundos — y explica también el precio: mantener el doble de réplicas.

## 19. Métricas DORA

Las métricas se calculan sobre **promociones reales al clúster**, no sobre ejecuciones de GitHub Actions. Un run que construye y publica una imagen no es un despliegue: la imagen solo se convierte en despliegue cuando `kubectl` la promueve y llega a recibir tráfico. Confundir ambas cosas inflaría la frecuencia y falsearía el denominador del change failure rate.

### Clasificación de los eventos

| Categoría | Cantidad | ¿Cuenta como despliegue? |
|---|---|---|
| **A.** Commits | 11 | No |
| **B.** Runs de GitHub Actions | 11 (10 success, 1 failure) | No |
| **C.** Imágenes publicadas en GHCR | 10 | No |
| **D.** Promociones reales a Kubernetes | **6** | **Sí** |
| **E.** Rollbacks planificados de demostración | 1 | No — prueba de recuperación |
| **F.** Fallos bloqueados antes de desplegar | 1 | No — nunca llegó al clúster |

De los 11 commits, cuatro (`4275ba3`, `03761aa`, `0b37d78`, `248cc8b`) son de manifiestos o documentación: generaron imagen pero **ninguna se promovió al clúster**, así que no cuentan.

### Tabla cronológica de promociones reales

| # | Fecha UTC | Versión | Imagen (tag) | Digest | Recurso | Mecanismo | ¿Recibió tráfico? | Resultado | ¿Rollback no planificado? | Frecuencia | Denominador CFR |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 2026-07-23 18:09:35 | v1 blue | `f3422484` | `sha256:187b5647` | `inventario-app` rev 1 | `kubectl apply` (deployment + service) | Sí | Éxito, 4/4 | No | Sí | Sí |
| 2 | 2026-07-26 17:51:43 | v2 green | `7577d9b0` | `sha256:6a20801a` | `inventario-app` rev 2 | `kubectl patch` atómico | Sí | Éxito, 12.28 s, 1060/1060 HTTP 200 | No | Sí | Sí |
| 3 | 2026-07-26 18:12:21 | readiness | `e05a9edb` | `sha256:7e0ad3dd` | `inventario-app` rev 3 | `kubectl patch` atómico | Sí | Éxito, 4/4, 0 reinicios | No | Sí | Sí |
| 4 | 2026-07-26 18:29:36 | secretKeyRef | `f5b43b94` | `sha256:e4c0b291` | `inventario-app` rev 4 | `kubectl apply` | Sí | Éxito, 352/352 HTTP 200 | No | Sí | Sí |
| 5 | 2026-07-26 18:56:24 | blue | `f5b43b94` | `sha256:e4c0b291` | `inventario-app-blue` rev 1 + selector `slot=blue` | `kubectl apply` × 2 | Sí | Éxito, 4/4 | No | Sí | Sí |
| 6 | 2026-07-26 18:58:00 → 19:00:22 | v3 green | `2ebe61cc` | `sha256:e40a90d1` | `inventario-app-green` rev 1 + cutover del selector | `kubectl apply` + `kubectl patch` del selector | Sí (desde el cutover) | Éxito, 493 ms, 1598/1598 HTTP 200 | No | Sí | Sí |

**Eventos excluidos, con su motivo:**

| Evento | Fecha UTC | Categoría | Motivo de exclusión |
|---|---|---|---|
| Run 30025704991 (`d20dec7d`) | 2026-07-23 16:34:36 | F | Trivy bloqueó la publicación por CVE-2026-59873. La imagen nunca se publicó ni se desplegó: no puede fallar en producción algo que no llegó a producción. |
| Rollback green → blue | 2026-07-26 19:02:04 | E | Prueba de recuperación planificada. Green estaba 4/4 Ready y sirviendo correctamente; no hubo defecto que corregir. |
| Cutover final blue → green | 2026-07-26 19:02:39 | E | Restitución del estado tras la prueba anterior, no una versión nueva. |
| Commits `03761aa`, `0b37d78`, `248cc8b` | varias | C | Manifiestos y documentación. Produjeron imagen, pero el Deployment nunca se apuntó a ella. |
| Errores de PowerShell, parseo y monitorización | varias | — | Fallos de método de medición, no del despliegue (ver sección 23). |

### Frecuencia de despliegue

```
Promociones reales          : 6
Ventana de observación      : 2026-07-23T18:09:35Z → 2026-07-26T19:02:39Z  (3.04 días naturales)
Días calendario con actividad: 2  (2026-07-23 y 2026-07-26)

Frecuencia = 6 promociones / 2 días con actividad = 3.0 por día activo
           = 6 promociones / 3.04 días naturales  = 1.97 por día natural
```

Se reportan ambas cifras porque la actividad se concentró en dos jornadas, no se distribuyó de forma uniforme. En la clasificación DORA esto corresponde a la banda **alta** (entre una vez por día y una por semana), con la salvedad de que la ventana es demasiado corta para una clasificación estadísticamente sólida.

### Change failure rate

```
Numerador  : fallos no planificados que exigieron rollback o corrección urgente = 0
Denominador: promociones consideradas (columna "Denominador CFR")              = 6

CFR = 0 / 6 = 0.000 = 0.0 %
```

La cifra vale porque el denominador está definido: seis promociones que llegaron a recibir tráfico. Ninguna requirió revertirse ni corregirse de urgencia. Con seis muestras, el intervalo de confianza es amplio: el 0 % describe esta ventana, no una capacidad demostrada a largo plazo.

**Un matiz importante:** hubo una interrupción real durante la práctica — Docker Desktop se apagó y el clúster quedó detenido tres días; al reiniciarlo, un pod apareció con `lastState.terminated` código 255 y el kubelet lo reinició solo. No entra en el CFR porque fue una caída del entorno anfitrión, no un despliegue defectuoso: ninguna promoción la causó y el Deployment se recuperó a 4/4 sin intervención.

### Lead time for changes

Ambos reconfirmados desde la fecha de *committer* hasta el instante en que la versión recibió tráfico real:

| | Rolling Update | Blue-Green |
|---|---|---|
| Commit | `7577d9b0` | `2ebe61cc` |
| Fecha del commit | 2026-07-26T17:47:57Z | 2026-07-26T18:53:19Z |
| Tráfico real | 2026-07-26T17:51:55.604Z (fin del rollout) | 2026-07-26T19:00:22.483Z (cutover) |
| **Lead time** | **3 m 58 s** (3.98 min) | **7 m 03 s** (7.06 min) |
| Run de CI | [30213344941](https://github.com/JosueSaenz2006/Practica-CI-CD/actions/runs/30213344941) | [30215685794](https://github.com/JosueSaenz2006/Practica-CI-CD/actions/runs/30215685794) |
| Duración de CI | 54 s | 50 s |
| Duración del despliegue | 12.28 s | 493 ms (cutover) |
| Disponibilidad | 100 % (1060/1060) | 100 % (1598/1598) |

Blue-Green tiene mayor lead time porque incluye desplegar green completo y validarlo **antes** de dirigirle tráfico. Ese tiempo extra no es ineficiencia: es exactamente la ventana de validación que la estrategia compra. El cambio de tráfico en sí es 25 veces más rápido que el rolling update.

La primera promoción tuvo un lead time de 63.9 min, muy por encima de las demás. No fue el pipeline: aquel ciclo incluyó una reescritura de historial y varias iteraciones para corregir la CVE.

### Tiempo de restauración del servicio

```
Rollback Blue-Green (cambio de selector): 426 ms, sin recrear pods
```

Es el mejor caso posible porque el entorno anterior seguía vivo. Un `kubectl rollout undo` en el Deployment de Rolling Update habría reconstruido los pods, con un coste del orden de los 12 s medidos en la promoción #2.

## 20. Instalación y ejecución

### Requisitos

```bash
docker info
node -v
kubectl version --client
minikube version
git --version
```

### Local

```bash
npm ci
npm test
npm start
```

### Contenedor

```bash
docker build -t inventario-app:local .
docker run -d --name inventario-demo -p 3000:3000 \
  -e APP_VERSION=local -e APP_COLOR=blue -e STARTUP_DELAY_SECONDS=5 \
  inventario-app:local

curl -s http://localhost:3000/health     # 503 los primeros 5 s, luego 200
curl -s http://localhost:3000/version
docker rm -f inventario-demo
```

### Kubernetes — despliegue directo

```bash
minikube start --driver=docker

kubectl create secret generic inventario-app-secret \
  --from-literal=API_KEY="<credencial>" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml
kubectl rollout status deployment/inventario-app
```

### Kubernetes — Blue-Green

```bash
kubectl apply -f k8s/blue-green/deployment-blue.yaml
kubectl rollout status deployment/inventario-app-blue

kubectl apply -f k8s/blue-green/service.yaml          # selector inicial: slot=blue

kubectl apply -f k8s/blue-green/deployment-green.yaml
kubectl rollout status deployment/inventario-app-green
```

## 21. Comandos para reproducir las evidencias

Secuencia ejecutable que reproduce cada una de las evidencias de la sección 22. Todas las comprobaciones se hacen **desde dentro del clúster**, contra el ClusterIP: `port-forward` no sirve para verificar balanceo (ver nota en la sección 12).

**1 — Estado inicial**

```bash
kubectl get deployment
kubectl get pods -l app=inventario-app -o wide
kubectl get service inventario-app -o wide
```

**2 — Pod de sondeo**

```bash
kubectl run demo --image=curlimages/curl:8.11.1 --restart=Never --command -- sleep 3600
kubectl wait --for=condition=Ready pod/demo --timeout=90s
```

**3 — Endpoints y balanceo**

```bash
kubectl exec demo -- curl -s http://inventario-app.default.svc.cluster.local/version
kubectl exec demo -- sh -c 'for i in $(seq 1 40); do curl -s http://inventario-app.default.svc.cluster.local/version; echo; done'
```

**4 — Readiness: pod arrancando sin recibir tráfico**

```bash
kubectl get pods -l app=inventario-app -w        # 0/1 Running durante ~12 s
kubectl get endpointslice -l kubernetes.io/service-name=inventario-app \
  -o jsonpath='{range .items[*]}{range .endpoints[*]}{.addresses[0]} ready={.conditions.ready}{"\n"}{end}{end}'
```

**5 — Secret sin exponer el valor**

```bash
kubectl describe secret inventario-app-secret
kubectl describe pod <pod> | grep API_KEY
kubectl exec demo -- curl -s http://inventario-app.default.svc.cluster.local/version
```

**6 — Monitor de disponibilidad** (dejar corriendo durante el cutover)

```bash
kubectl exec demo -- sh -c 'while true; do curl -s -o /dev/null -w "%{http_code} " http://inventario-app.default.svc.cluster.local/health; curl -s http://inventario-app.default.svc.cluster.local/version; echo; sleep 0.2; done'
```

**7 — Cutover, rollback y cutover final**

```bash
kubectl patch service inventario-app --type=strategic -p '{"spec":{"selector":{"app":"inventario-app","slot":"green"}}}'
kubectl get service inventario-app -o jsonpath='{.spec.selector}'

kubectl patch service inventario-app --type=strategic -p '{"spec":{"selector":{"app":"inventario-app","slot":"blue"}}}'

kubectl patch service inventario-app --type=strategic -p '{"spec":{"selector":{"app":"inventario-app","slot":"green"}}}'
```

**8 — ClusterIP y NodePort invariables**

```bash
kubectl get service inventario-app -o jsonpath='{.spec.clusterIP}{"  "}{.spec.ports[0].nodePort}'
```

**9 — Limpieza del pod de sondeo**

```bash
kubectl delete pod demo --now
```

## 22. Evidencias verificadas

| # | Evidencia | Resultado |
|---|---|---|
| 1 | 13 pruebas automatizadas | 13 pass / 0 fail |
| 2 | Trivy bloqueó una imagen vulnerable | run 30025704991, CVE-2026-59873 |
| 3 | Corrección sin silenciar el escáner | commit `f342248`, sin `.trivyignore` |
| 4 | Imagen no root, sin npm | `uid=1000(node)`, npm/npx ausentes |
| 5 | Publicación por SHA inmutable | digests resueltos anónimamente |
| 6 | 4 réplicas balanceadas | 40 GET → 4 pods (10/8/12/10) |
| 7 | DNS interno | nombre corto y FQDN → ClusterIP |
| 8 | Readiness: Running sin tráfico | 12.8 s, `epNOTREADY`, 0 reinicios |
| 9 | Secret sin exponerse | `apiKeyConfigured=true`, ausente de Git |
| 10 | Rolling Update sin downtime | 1060/1060 HTTP 200, 0 errores |
| 11 | Rolling Update respeta la estrategia | mín. 3 disponibles, máx. 5 activos |
| 12 | Green validado sin tráfico | directo `green`, Service `blue` |
| 13 | Cutover atómico | 493 ms, sin estado intermedio |
| 14 | Rollback instantáneo | 426 ms, 0 pods recreados |
| 15 | Blue-Green sin downtime | 1598/1598 HTTP 200, 0 errores |
| 16 | ClusterIP y NodePort estables | valor único en 160 muestras |
| 17 | Pipeline verde | 10 de 11 runs; el fallo fue la barrera |
| 18 | Persistencia efímera | producto perdido al recrear el pod; seed restaurado |
| 19 | Copias de datos independientes por pod | 3 pods con seed, 1 con el producto temporal |

## 23. Conclusiones

**El pipeline vale por lo que impide, no por lo que automatiza.** El momento más instructivo de la práctica fue un fallo: Trivy detuvo una imagen con una CVE crítica heredada de la imagen base. Sin esa barrera, la vulnerabilidad habría llegado al registro y al clúster sin que nadie lo notara. La corrección tampoco fue silenciar el aviso, sino eliminar el paquete que lo causaba.

**La disponibilidad la da la readiness probe, no el número de réplicas.** Un pod estuvo 12.8 s `Running` sin recibir una sola petición porque declaraba honestamente que no estaba listo. Multiplicar réplicas sobre un readiness mal configurado solo multiplica los destinos rotos.

**Rolling Update y Blue-Green resuelven problemas distintos.** Rolling Update reemplaza gradualmente y su rollback reconstruye pods. Blue-Green mantiene dos entornos vivos: permite validar la versión nueva en el entorno real antes de exponerla, y revertir en 426 ms sin recrear nada. A cambio exige el doble de recursos permanentes. No es que una sea mejor: es que cuestan cosas distintas.

**Un pod es desechable, y sus datos también.** Un producto creado en un pod desapareció al recrearse ese pod, y el estado volvió exactamente al de la imagen. No es un fallo: es lo que significa que el sistema de archivos de un contenedor sea efímero. Cualquier dato que deba sobrevivir necesita vivir fuera del pod — en un volumen persistente o en una base de datos externa.

**El SHA inmutable es lo que hace reproducible el despliegue.** `latest` haría que el mismo manifiesto significara cosas distintas según cuándo se aplique. Con el SHA, un manifiesto describe un artefacto exacto y verificable por digest.

**Medir es distinto de suponer.** Tres mediciones parecían indicar fallos y ninguna lo era: `port-forward` no balancea, `kubectl get pods` sigue listando pods en terminación, y un endpoint aparece listado con `ready: false` sin recibir tráfico. En los tres casos el método era incorrecto, no el clúster. Las cifras de este documento provienen de las mediciones corregidas.
