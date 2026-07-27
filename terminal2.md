# Terminal 2 — Formulario rápido de comandos

Hoja de consulta para una prueba práctica. Está organizada para encontrar un comando en segundos.

> Sintaxis principal: **Windows PowerShell**.

---

# 1. VARIABLES ÚTILES

```powershell
$APP = "inventario-app"
$DEPLOYMENT = "inventario-app"
$CONTAINER = "app"
$SERVICE = "inventario-app"
$IMAGE = "ghcr.io/josuesaenz2006/practica-ci-cd"
$SHA = git rev-parse HEAD
$SHORT_SHA = git rev-parse --short=8 HEAD
$FULL_IMAGE = "${IMAGE}:${SHA}"
```

---

# 2. GIT — COMANDOS ESENCIALES

## Estado e historial

```powershell
git status
git branch --show-current
git log --oneline -10
git remote -v
git diff
git diff --check
```

## Staging y commit

```powershell
git add ARCHIVO
git add ARCHIVO1 ARCHIVO2
git diff --cached --name-only
git diff --cached --check
git commit -m "tipo: mensaje"
```

## Push y pull

```powershell
git pull --ff-only origin main
git push origin main
```

## Ramas

```powershell
git switch -c nombre-rama
git switch main
git branch
git push -u origin nombre-rama
```

## Descartar solo un archivo no deseado

```powershell
git restore ARCHIVO
```

> No usar `git reset --hard`, `git clean -fd` ni `git push --force` durante la prueba.

---

# 3. GITHUB CLI

## Autenticación y repositorio

```powershell
gh auth status
gh repo view
gh repo view --web
```

## Crear repositorio público desde una carpeta

```powershell
gh repo create NOMBRE `
  --public `
  --source=. `
  --remote=origin `
  --push
```

## GitHub Actions

```powershell
gh run list --workflow ci-cd.yml --limit 10
gh run view RUN_ID
gh run watch RUN_ID
gh run view RUN_ID --log
gh run view RUN_ID --log-failed
gh run view RUN_ID --web
gh workflow run ci-cd.yml --ref main
```

## Datos compactos de Actions

```powershell
gh run list `
  --workflow ci-cd.yml `
  --limit 5 `
  --json databaseId,status,conclusion,headSha,displayTitle
```

---

# 4. NPM Y NODE

```powershell
node --version
npm --version
npm ci
npm test
npm start
node server.js
```

Variables temporales:

```powershell
$env:PORT = "3000"
$env:APP_VERSION = "local"
$env:APP_COLOR = "blue"
$env:STARTUP_DELAY_SECONDS = "0"
node server.js
```

---

# 5. DOCKER — IMÁGENES

## Información

```powershell
docker --version
docker info
docker images
docker image ls
docker image inspect IMAGEN:TAG
```

## Construir

```powershell
docker build -t mi-app:v1 .
docker build --no-cache -t mi-app:v1 .
docker build -t $FULL_IMAGE .
```

> Usa `--no-cache` solo cuando necesites comprobar que el build completo funciona desde cero.

## Etiquetar

```powershell
docker tag mi-app:v1 usuario/mi-app:v1
docker tag mi-app:v1 ghcr.io/usuario/mi-app:v1
```

## Publicar

```powershell
docker login ghcr.io
docker push ghcr.io/usuario/mi-app:v1
```

No escribas tokens directamente en archivos.

---

# 6. DOCKER — CONTENEDORES

## Ejecutar

```powershell
docker run -d --name mi-app -p 8080:3000 mi-app:v1
```

Con variables:

```powershell
docker run -d `
  --name mi-app `
  -p 8080:3000 `
  -e PORT=3000 `
  -e APP_VERSION=v1 `
  -e APP_COLOR=blue `
  mi-app:v1
```

## Estado

```powershell
docker ps
docker ps -a
docker inspect mi-app
docker inspect mi-app --format '{{.State.Status}}'
docker inspect mi-app --format '{{.State.Health.Status}}'
```

## Logs

```powershell
docker logs mi-app
docker logs -f mi-app
docker logs --tail 50 mi-app
```

## Entrar al contenedor

```powershell
docker exec -it mi-app sh
```

## Ciclo de vida

```powershell
docker stop mi-app
docker start mi-app
docker restart mi-app
docker rm mi-app
docker rm -f mi-app
```

## Copiar archivo

```powershell
docker cp ARCHIVO mi-app:/ruta/destino
docker cp mi-app:/ruta/archivo .
```

---

# 7. DOCKER — REDES Y PUERTOS

```powershell
docker port mi-app
docker network ls
docker network inspect bridge
```

Recordatorio:

```text
-p PUERTO_HOST:PUERTO_CONTENEDOR
-p 8080:3000
```

El usuario accede a `8080`; la aplicación escucha en `3000` dentro del contenedor.

---

# 8. MINIKUBE

```powershell
minikube version
minikube status
minikube start --driver=docker
minikube pause
minikube unpause
minikube dashboard
minikube ip
minikube service NOMBRE_SERVICE --url
```

> No usar `minikube delete` para resolver una falla de la prueba.

---

# 9. KUBECTL — INFORMACIÓN GENERAL

```powershell
kubectl version --client
kubectl config current-context
kubectl cluster-info
kubectl get nodes
kubectl get namespaces
kubectl get all
```

Cambiar namespace temporalmente:

```powershell
kubectl config set-context --current --namespace=NAMESPACE
```

Volver a default:

```powershell
kubectl config set-context --current --namespace=default
```

---

# 10. KUBECTL — APLICAR YAML

```powershell
kubectl apply -f archivo.yaml
kubectl apply -f carpeta/
kubectl diff -f archivo.yaml
```

Validar sintaxis del lado del cliente:

```powershell
kubectl apply --dry-run=client -f archivo.yaml
```

Ver YAML activo:

```powershell
kubectl get deployment inventario-app -o yaml
kubectl get service inventario-app -o yaml
```

---

# 11. PODS

## Listar

```powershell
kubectl get pods
kubectl get pods -o wide
kubectl get pods --show-labels
kubectl get pods -l app=inventario-app
kubectl get pods -l app=inventario-app -w
```

## Describir y logs

```powershell
kubectl describe pod NOMBRE_POD
kubectl logs NOMBRE_POD
kubectl logs -f NOMBRE_POD
kubectl logs NOMBRE_POD --previous
```

Si hay varios contenedores:

```powershell
kubectl logs NOMBRE_POD -c NOMBRE_CONTENEDOR
```

## Ejecutar comando dentro del pod

```powershell
kubectl exec -it NOMBRE_POD -- sh
kubectl exec NOMBRE_POD -- env
kubectl exec NOMBRE_POD -- ls -la /app
```

## Eliminar un pod para probar auto-healing

```powershell
kubectl delete pod NOMBRE_POD
kubectl get pods -w
```

---

# 12. DEPLOYMENTS

```powershell
kubectl get deployments
kubectl describe deployment inventario-app
kubectl get replicasets
kubectl rollout status deployment/inventario-app
kubectl rollout history deployment/inventario-app
```

## Escalar

```powershell
kubectl scale deployment/inventario-app --replicas=5
kubectl scale deployment/inventario-app --replicas=4
```

## Cambiar imagen

```powershell
kubectl set image deployment/inventario-app `
  app=ghcr.io/usuario/mi-app:v2
```

## Consultar imagen actual

```powershell
kubectl get deployment inventario-app `
  -o jsonpath='{.spec.template.spec.containers[0].image}'
```

## Reiniciar rollout sin cambiar imagen

```powershell
kubectl rollout restart deployment/inventario-app
kubectl rollout status deployment/inventario-app
```

## Rollback

```powershell
kubectl rollout undo deployment/inventario-app
kubectl rollout undo deployment/inventario-app --to-revision=2
```

---

# 13. SERVICES

```powershell
kubectl get services
kubectl get svc
kubectl describe service inventario-app
kubectl get service inventario-app -o wide
kubectl get service inventario-app -o yaml
kubectl get endpoints
kubectl get endpoints inventario-app
kubectl get endpointslices
```

## URL de Minikube

```powershell
minikube service inventario-app --url
```

## Port-forward

```powershell
kubectl port-forward service/inventario-app 8080:80
kubectl port-forward deployment/inventario-app 8080:3000
kubectl port-forward pod/NOMBRE_POD 8080:3000
```

> Port-forward sirve para acceder directamente. Para comprobar balanceo real, consulta el ClusterIP desde dentro del clúster.

---

# 14. CONFIGMAP

Crear:

```powershell
kubectl create configmap app-config `
  --from-literal=APP_COLOR=green
```

Ver:

```powershell
kubectl get configmap
kubectl describe configmap app-config
```

Referencia YAML:

```yaml
env:
  - name: APP_COLOR
    valueFrom:
      configMapKeyRef:
        name: app-config
        key: APP_COLOR
```

---

# 15. SECRET

Crear sin guardarlo en Git:

```powershell
kubectl create secret generic app-secret `
  --from-literal=API_KEY="valor-ficticio"
```

Forma idempotente:

```powershell
kubectl create secret generic app-secret `
  --from-literal=API_KEY="valor-ficticio" `
  --dry-run=client -o yaml | kubectl apply -f -
```

Comprobar sin mostrar el valor:

```powershell
kubectl get secrets
kubectl describe secret app-secret
```

Referencia YAML:

```yaml
env:
  - name: API_KEY
    valueFrom:
      secretKeyRef:
        name: app-secret
        key: API_KEY
```

---

# 16. HEALTH CHECKS — HTTP

## Local o Docker

```powershell
curl.exe -i http://localhost:3000/health
curl.exe -i http://localhost:3000/version
curl.exe -i http://localhost:3000/api/products
```

Solo HTTP code:

```powershell
curl.exe -s -o NUL -w "%{http_code}`n" http://localhost:3000/health
```

JSON en PowerShell:

```powershell
Invoke-RestMethod http://localhost:3000/health | ConvertTo-Json
Invoke-RestMethod http://localhost:3000/version | ConvertTo-Json
```

## Desde Minikube

```powershell
$URL = minikube service inventario-app --url
curl.exe -i "$URL/health"
curl.exe -i "$URL/version"
```

## Desde dentro del clúster

```powershell
kubectl run health-check `
  --rm -it `
  --restart=Never `
  --image=curlimages/curl:8.10.1 `
  -- curl -i http://inventario-app/health
```

## Monitor continuo

```powershell
while ($true) {
  $code = curl.exe -s -o NUL -w "%{http_code}" "$URL/health"
  Write-Host "$(Get-Date -Format HH:mm:ss) HTTP $code"
  Start-Sleep -Milliseconds 500
}
```

Salir:

```text
Ctrl + C
```

---

# 17. READINESS Y LIVENESS

Ver estado Ready:

```powershell
kubectl get pods
kubectl describe pod NOMBRE_POD
```

EndpointSlice:

```powershell
kubectl get endpointslice `
  -l kubernetes.io/service-name=inventario-app `
  -o jsonpath='{range .items[*]}{range .endpoints[*]}{.addresses[0]} ready={.conditions.ready}{"\n"}{end}{end}'
```

Fragmento YAML:

```yaml
readinessProbe:
  httpGet:
    path: /health
    port: 3000
  initialDelaySeconds: 1
  periodSeconds: 2

livenessProbe:
  httpGet:
    path: /health
    port: 3000
  initialDelaySeconds: 20
  periodSeconds: 10
```

Diferencia:

- **Readiness:** recibe tráfico o no.
- **Liveness:** Kubernetes reinicia o no el contenedor.

---

# 18. ROLLING UPDATE

```powershell
kubectl set image deployment/inventario-app `
  app=ghcr.io/usuario/mi-app:v2

kubectl rollout status deployment/inventario-app
kubectl rollout history deployment/inventario-app
kubectl get pods -w
```

Estrategia YAML:

```yaml
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxUnavailable: 1
    maxSurge: 1
```

---

# 19. BLUE-GREEN

## Aplicar

```powershell
kubectl apply -f k8s/blue-green/deployment-blue.yaml
kubectl apply -f k8s/blue-green/deployment-green.yaml
kubectl apply -f k8s/blue-green/service.yaml
```

## Estado

```powershell
kubectl get deployments
kubectl get pods --show-labels
kubectl get service inventario-app -o jsonpath='{.spec.selector}'
```

## Cutover a green

```powershell
kubectl patch service inventario-app `
  --type=merge `
  -p '{"spec":{"selector":{"app":"inventario-app","slot":"green"}}}'
```

## Rollback a blue

```powershell
kubectl patch service inventario-app `
  --type=merge `
  -p '{"spec":{"selector":{"app":"inventario-app","slot":"blue"}}}'
```

---

# 20. DIAGNÓSTICO — ORDEN CORRECTO

Ejecuta siempre:

```powershell
kubectl get pods
kubectl get deployments
kubectl get services
kubectl get endpoints
kubectl describe pod NOMBRE_POD
kubectl logs NOMBRE_POD
kubectl logs NOMBRE_POD --previous
kubectl get events --sort-by=.metadata.creationTimestamp
```

---

# 21. ERRORES FRECUENTES

## ImagePullBackOff

```powershell
kubectl describe pod NOMBRE_POD
```

Revisar:

- nombre de imagen;
- tag existente;
- permisos del registro;
- Internet;
- `imagePullSecret`.

## CrashLoopBackOff

```powershell
kubectl logs NOMBRE_POD
kubectl logs NOMBRE_POD --previous
kubectl describe pod NOMBRE_POD
```

## Running 0/1

```powershell
kubectl describe pod NOMBRE_POD
kubectl logs NOMBRE_POD
```

Revisar readiness, puerto y `/health`.

## Service sin endpoints

```powershell
kubectl get pods --show-labels
kubectl get service inventario-app -o yaml
kubectl get endpoints inventario-app
```

Causa típica: selector del Service no coincide con labels del pod.

## Connection refused

Revisar:

```powershell
kubectl logs NOMBRE_POD
kubectl get service
kubectl get endpoints
kubectl describe pod NOMBRE_POD
```

Causas:

- proceso no escucha;
- `targetPort` incorrecto;
- pod no Ready;
- aplicación escucha solo en `localhost`;
- Service sin endpoints.

## YAML inválido

```powershell
kubectl apply --dry-run=client -f archivo.yaml
kubectl apply -f archivo.yaml
```

Revisar indentación con espacios, no tabuladores.

---

# 22. MANIFIESTOS MÍNIMOS

## Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mi-app
spec:
  replicas: 3
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 1
      maxSurge: 1
  selector:
    matchLabels:
      app: mi-app
  template:
    metadata:
      labels:
        app: mi-app
    spec:
      containers:
        - name: app
          image: usuario/mi-app:v1
          ports:
            - containerPort: 3000
          readinessProbe:
            httpGet:
              path: /health
              port: 3000
          livenessProbe:
            httpGet:
              path: /health
              port: 3000
```

## Service

```yaml
apiVersion: v1
kind: Service
metadata:
  name: mi-app
spec:
  type: NodePort
  selector:
    app: mi-app
  ports:
    - port: 80
      targetPort: 3000
```

---

# 23. WORKFLOW MÍNIMO DE GITHUB ACTIONS

```yaml
name: CI/CD

on:
  push:
    branches: [main]
  workflow_dispatch:

jobs:
  build-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: "20"
          cache: npm
      - run: npm ci
      - run: npm test

  build-push:
    needs: build-test
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
    steps:
      - uses: actions/checkout@v4
      - run: docker build -t ghcr.io/usuario/mi-app:${{ github.sha }} .
      - uses: docker/login-action@v4
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      - run: docker push ghcr.io/usuario/mi-app:${{ github.sha }}
```

Conceptos:

- `needs: build-test`: fail-fast.
- `${{ github.sha }}`: etiqueta ligada al commit.
- `GITHUB_TOKEN`: autenticación del workflow.
- `packages: write`: permiso para publicar en GHCR.

---

# 24. TABLA DE DECISIÓN RÁPIDA

| Síntoma | Primer comando | Segundo comando |
|---|---|---|
| Imagen no descarga | `kubectl describe pod` | revisar image/tag |
| Pod se reinicia | `kubectl logs --previous` | `kubectl describe pod` |
| Pod 0/1 | `kubectl describe pod` | revisar readiness |
| Service no responde | `kubectl get endpoints` | comparar selector/labels |
| Rollout trabado | `kubectl rollout status` | `kubectl get pods` |
| App local falla | `npm test` | `node server.js` |
| Contenedor falla | `docker logs` | `docker inspect` |
| Actions falla | `gh run view --log-failed` | corregir primer error |
| Versión dañada | `kubectl rollout history` | `kubectl rollout undo` |

---

# 25. FLUJO DE MEMORIA

```text
APP LOCAL
npm ci → npm test → node server.js → curl /health

DOCKER
docker build → docker run → docker ps → docker logs → curl

GITHUB
git add → git commit → git push → gh run list → gh run watch

KUBERNETES
minikube start → kubectl apply → kubectl get → rollout status → curl

DIAGNÓSTICO
get → describe → logs → events → corregir → verificar

ACTUALIZACIÓN
set image → rollout status → health → history → undo si falla
```

---

# 26. RESPUESTAS CORTAS DE TEORÍA

- **Imagen:** plantilla inmutable.
- **Contenedor:** instancia ejecutándose.
- **Pod:** unidad mínima desplegable en Kubernetes.
- **Deployment:** mantiene réplicas y administra actualizaciones.
- **Service:** dirección estable y balanceo hacia pods.
- **ConfigMap:** configuración no sensible.
- **Secret:** configuración sensible.
- **Readiness:** controla entrada al tráfico.
- **Liveness:** controla reinicio.
- **Rolling Update:** cambio gradual de pods.
- **Blue-Green:** dos entornos paralelos y cambio de selector.
- **Canary:** porcentaje pequeño de tráfico hacia la versión nueva.
- **Fail-fast:** detener el flujo en el primer fallo.
- **Continuous Delivery:** promoción final manual.
- **Continuous Deployment:** promoción final automática.

---

**Regla de oro:** no ejecutes veinte comandos al azar. Obtén el estado, identifica la causa, cambia una sola cosa y vuelve a medir.