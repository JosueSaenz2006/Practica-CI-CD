# Terminal 1 — Guía práctica paso a paso

Formulario de emergencia para una prueba práctica de **Docker, Git, GitHub Actions, Minikube y Kubernetes**.

> Entorno recomendado: **Windows PowerShell**. Cuando aparezca `curl.exe`, úsalo así para evitar el alias de PowerShell.

---

## 0. Reglas antes de empezar

1. Lee todo el enunciado antes de ejecutar comandos.
2. Identifica:
   - nombre de la aplicación;
   - puerto interno de la aplicación;
   - nombre de la imagen;
   - nombre del Deployment;
   - nombre del contenedor dentro del Deployment;
   - ruta de salud, normalmente `/health`.
3. No uses comandos destructivos para “arreglar” un error.
4. Guarda evidencia después de cada etapa.

### Comandos que NO deben usarse durante la prueba

```powershell
# NO ejecutar
# docker system prune
# docker system prune -a
# minikube delete
# wsl --unregister
# git reset --hard
# git clean -fd
# git push --force
```

---

## 1. Abrir y organizar las terminales

Abre cuatro terminales PowerShell:

- **Terminal 1:** aplicación, pruebas y Docker.
- **Terminal 2:** Kubernetes y `kubectl get ... -w`.
- **Terminal 3:** peticiones `curl` y comprobaciones de salud.
- **Terminal 4:** Git, GitHub y GitHub Actions.

En todas, entra al proyecto:

```powershell
cd "RUTA_DEL_PROYECTO"
```

Para esta práctica:

```powershell
cd "C:\Users\josue\Desktop\Escritorio\Universidad\6 Sexto Ciclo\SISTEMAS DISTRIBUIDOS\SEGUNDO INTERCICLO\Practica-CI-CD"
```

Comprueba la ubicación:

```powershell
Get-Location
Get-ChildItem
```

---

## 2. Definir variables de trabajo

Ejecuta en PowerShell:

```powershell
$APP = "inventario-app"
$DEPLOYMENT = "inventario-app"
$CONTAINER = "app"
$SERVICE = "inventario-app"
$PORT = 3000
$IMAGE = "ghcr.io/josuesaenz2006/practica-ci-cd"
$SHA = git rev-parse HEAD
$SHORT_SHA = git rev-parse --short=8 HEAD
$FULL_IMAGE = "${IMAGE}:${SHA}"

$APP
$SHA
$FULL_IMAGE
```

En un examen genérico cambia solo las variables.

---

# PARTE A — APLICACIÓN LOCAL

## 3. Verificar herramientas

```powershell
node --version
npm --version
git --version
docker --version
docker info
kubectl version --client
minikube version
gh --version
```

Si `docker info` falla, abre Docker Desktop y espera hasta que el motor esté activo.

---

## 4. Instalar dependencias y ejecutar pruebas

```powershell
npm ci
npm test
```

Resultado esperado:

```text
tests ...
pass ...
fail 0
```

Si falla:

```powershell
npm test
```

Lee el primer error real. No continúes con Docker hasta que las pruebas pasen.

---

## 5. Ejecutar la aplicación sin Docker

```powershell
$env:PORT = "3000"
$env:APP_VERSION = "local"
$env:APP_COLOR = "blue"
$env:STARTUP_DELAY_SECONDS = "0"
node server.js
```

Deja esa terminal abierta.

En otra terminal:

```powershell
curl.exe -i http://localhost:3000/
curl.exe -i http://localhost:3000/health
curl.exe -i http://localhost:3000/version
curl.exe -i http://localhost:3000/api/products
```

Resultado saludable esperado:

```text
HTTP/1.1 200 OK
```

Detén la aplicación con:

```text
Ctrl + C
```

---

# PARTE B — DOCKER

## 6. Revisar el Dockerfile

Debe existir:

```powershell
Get-Content Dockerfile
```

Puntos obligatorios:

- primera etapa instala dependencias;
- ejecuta `npm test`;
- si las pruebas fallan, el build falla;
- segunda etapa contiene solo lo necesario;
- incluye `public/`;
- expone el puerto correcto;
- ejecuta la aplicación con `CMD`.

---

## 7. Construir la imagen Docker

Construcción local sencilla:

```powershell
docker build -t inventario-app:local .
```

Construcción con SHA:

```powershell
docker build -t $FULL_IMAGE .
```

Verifica:

```powershell
docker images

docker image inspect inventario-app:local
```

Si falla el build, busca la primera línea marcada como error. Las causas frecuentes son:

- archivo faltante en `COPY`;
- `npm test` fallando;
- nombre de archivo incorrecto;
- dependencia no instalada;
- error de sintaxis en Dockerfile.

---

## 8. Ejecutar el contenedor

Primero elimina solo un contenedor anterior con el mismo nombre, si existe:

```powershell
docker rm -f inventario-app-local 2>$null
```

Ejecuta:

```powershell
docker run -d `
  --name inventario-app-local `
  -p 3000:3000 `
  -e PORT=3000 `
  -e APP_VERSION=local-docker `
  -e APP_COLOR=blue `
  -e STARTUP_DELAY_SECONDS=0 `
  inventario-app:local
```

Comprueba:

```powershell
docker ps
docker logs inventario-app-local
docker inspect inventario-app-local --format '{{.State.Status}}'
docker inspect inventario-app-local --format '{{.State.Health.Status}}'
```

---

## 9. Probar la salud del contenedor

```powershell
curl.exe -i http://localhost:3000/
curl.exe -i http://localhost:3000/health
curl.exe -i http://localhost:3000/version
curl.exe -i http://localhost:3000/api/products
```

Solo el código HTTP:

```powershell
curl.exe -s -o NUL -w "%{http_code}`n" http://localhost:3000/health
```

Respuesta JSON formateada en PowerShell:

```powershell
Invoke-RestMethod http://localhost:3000/health | ConvertTo-Json
Invoke-RestMethod http://localhost:3000/version | ConvertTo-Json
```

Entrar al contenedor:

```powershell
docker exec -it inventario-app-local sh
```

Dentro:

```sh
pwd
ls -la
id
exit
```

Detener y retirar solo este contenedor:

```powershell
docker stop inventario-app-local
docker rm inventario-app-local
```

---

## 10. Probar arranque lento

```powershell
docker rm -f inventario-app-delay 2>$null

docker run -d `
  --name inventario-app-delay `
  -p 3000:3000 `
  -e STARTUP_DELAY_SECONDS=10 `
  inventario-app:local
```

Consulta repetida:

```powershell
1..15 | ForEach-Object {
  $code = curl.exe -s -o NUL -w "%{http_code}" http://localhost:3000/health
  Write-Host "segundo $_ -> HTTP $code"
  Start-Sleep -Seconds 1
}
```

Esperado:

- al inicio: `503`;
- después del retraso: `200`.

Limpieza:

```powershell
docker rm -f inventario-app-delay
```

---

# PARTE C — GIT Y GITHUB

## 11. Revisar Git antes de modificar

```powershell
git status
git branch --show-current
git log --oneline -5
git remote -v
```

Crear una rama durante una práctica, si el docente lo pide:

```powershell
git switch -c practica-examen
```

Volver a `main`:

```powershell
git switch main
```

---

## 12. Guardar cambios en Git

Revisa exactamente qué cambió:

```powershell
git status
git diff
git diff --check
```

Añade archivos específicos, nunca todo a ciegas:

```powershell
git add Dockerfile
git add .github/workflows/ci-cd.yml
git add k8s/deployment.yaml k8s/service.yaml
```

Verifica el staging:

```powershell
git diff --cached --name-only
git diff --cached --check
```

Commit:

```powershell
git commit -m "feat: implementa despliegue de la practica"
```

Push:

```powershell
git push origin main
```

En una rama:

```powershell
git push -u origin practica-examen
```

---

## 13. Crear repositorio desde comandos

Solo si todavía no existe un repositorio remoto:

```powershell
gh auth status

gh repo create NOMBRE_REPOSITORIO `
  --public `
  --source=. `
  --remote=origin `
  --push
```

Comprobar repositorio:

```powershell
gh repo view --web
```

---

## 14. Ejecutar y revisar GitHub Actions desde terminal

El workflow corre automáticamente al hacer push a `main`.

Lista de runs:

```powershell
gh run list --workflow ci-cd.yml --limit 10
```

Ver datos útiles:

```powershell
gh run list `
  --workflow ci-cd.yml `
  --limit 5 `
  --json databaseId,status,conclusion,headSha,displayTitle
```

Ver un run:

```powershell
gh run view RUN_ID
```

Seguirlo hasta terminar:

```powershell
gh run watch RUN_ID
```

Ver logs:

```powershell
gh run view RUN_ID --log
```

Ver solo logs fallidos:

```powershell
gh run view RUN_ID --log-failed
```

Ejecutar manualmente, si el workflow tiene `workflow_dispatch`:

```powershell
gh workflow run ci-cd.yml --ref main
```

Abrir Actions en navegador:

```powershell
gh run view RUN_ID --web
```

---

# PARTE D — MINIKUBE Y KUBERNETES

## 15. Iniciar Minikube

Usa el perfil existente:

```powershell
minikube status
minikube start --driver=docker
```

Comprobar contexto:

```powershell
kubectl config current-context
kubectl cluster-info
kubectl get nodes
```

Resultado esperado:

```text
minikube   Ready
```

---

## 16. Crear el Secret sin versionar la credencial

```powershell
kubectl create secret generic inventario-app-secret `
  --from-literal=API_KEY="credencial-ficticia-de-prueba" `
  --dry-run=client -o yaml | kubectl apply -f -
```

Comprobar sin mostrar el valor:

```powershell
kubectl describe secret inventario-app-secret
```

Nunca ejecutar para una evidencia pública:

```powershell
# No mostrar el contenido real del Secret
# kubectl get secret inventario-app-secret -o yaml
```

---

## 17. Desplegar Deployment y Service

```powershell
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml
```

Esperar rollout:

```powershell
kubectl rollout status deployment/inventario-app --timeout=180s
```

Ver estado:

```powershell
kubectl get deployments
kubectl get replicasets
kubectl get pods -o wide
kubectl get services
kubectl get endpoints
kubectl get endpointslices
```

---

## 18. Vigilar pods durante un despliegue

En Terminal 2:

```powershell
kubectl get pods -l app=inventario-app -w
```

Interpretación:

- `Pending`: Kubernetes todavía prepara el pod.
- `Running 0/1`: proceso activo, pero no Ready.
- `Running 1/1`: listo para recibir tráfico.
- `ImagePullBackOff`: no pudo descargar la imagen.
- `CrashLoopBackOff`: el proceso inicia y se cae repetidamente.

Detén el modo watch con:

```text
Ctrl + C
```

---

## 19. Acceder al Service

Obtener URL de Minikube:

```powershell
minikube service inventario-app --url
```

Guardar URL:

```powershell
$URL = minikube service inventario-app --url
$URL
```

Probar:

```powershell
curl.exe -i "$URL/"
curl.exe -i "$URL/health"
curl.exe -i "$URL/version"
curl.exe -i "$URL/api/products"
```

Alternativa con port-forward al Service:

```powershell
kubectl port-forward service/inventario-app 8080:80
```

En otra terminal:

```powershell
curl.exe -i http://localhost:8080/health
```

> `port-forward` sirve para acceder, pero no es una prueba fiable del balanceo entre pods.

---

## 20. Probar salud desde dentro del clúster

Crear un pod temporal de sondeo:

```powershell
kubectl run curl-test `
  --image=curlimages/curl:8.10.1 `
  --restart=Never `
  --command -- sleep 3600
```

Esperar:

```powershell
kubectl wait --for=condition=Ready pod/curl-test --timeout=120s
```

Comprobar salud:

```powershell
kubectl exec curl-test -- curl -i http://inventario-app/health
kubectl exec curl-test -- curl -s http://inventario-app/version
kubectl exec curl-test -- curl -s http://inventario-app/api/products
```

Solo código HTTP:

```powershell
kubectl exec curl-test -- curl -s -o /dev/null -w "%{http_code}`n" http://inventario-app/health
```

Eliminar únicamente el pod temporal:

```powershell
kubectl delete pod curl-test
```

---

## 21. Verificar readiness y endpoints

Pods listos:

```powershell
kubectl get pods -l app=inventario-app
```

Detalles del probe:

```powershell
kubectl describe deployment inventario-app
kubectl describe pod NOMBRE_POD
```

EndpointSlice con condición Ready:

```powershell
kubectl get endpointslice `
  -l kubernetes.io/service-name=inventario-app `
  -o jsonpath='{range .items[*]}{range .endpoints[*]}{.addresses[0]} ready={.conditions.ready}{"\n"}{end}{end}'
```

Un pod con `ready=false` no debe recibir tráfico normal del Service.

---

## 22. Probar auto-healing

Elige un pod:

```powershell
$POD = kubectl get pods -l app=inventario-app -o jsonpath='{.items[0].metadata.name}'
$POD
```

Bórralo:

```powershell
kubectl delete pod $POD
```

Observa cómo el Deployment crea otro:

```powershell
kubectl get pods -l app=inventario-app -w
```

Conclusión esperada:

- el pod borrado desaparece;
- el ReplicaSet crea un reemplazo;
- el Deployment vuelve al número deseado de réplicas.

---

## 23. Escalar el Deployment

```powershell
kubectl scale deployment/inventario-app --replicas=5
kubectl rollout status deployment/inventario-app
kubectl get pods -l app=inventario-app
```

Volver a cuatro:

```powershell
kubectl scale deployment/inventario-app --replicas=4
```

---

# PARTE E — ROLLING UPDATE Y ROLLBACK

## 24. Actualizar una imagen

Primero consulta el nombre del contenedor:

```powershell
kubectl get deployment inventario-app `
  -o jsonpath='{.spec.template.spec.containers[*].name}'
```

Actualizar imagen:

```powershell
kubectl set image deployment/inventario-app `
  app=ghcr.io/josuesaenz2006/practica-ci-cd:ETIQUETA_NUEVA
```

Seguir rollout:

```powershell
kubectl rollout status deployment/inventario-app --timeout=180s
kubectl rollout history deployment/inventario-app
kubectl get pods -l app=inventario-app -o wide
```

Ver imagen desplegada:

```powershell
kubectl get deployment inventario-app `
  -o jsonpath='{.spec.template.spec.containers[0].image}'
```

---

## 25. Simular una imagen inexistente

Solo en un ejercicio controlado:

```powershell
kubectl set image deployment/inventario-app `
  app=ghcr.io/josuesaenz2006/practica-ci-cd:etiqueta-que-no-existe
```

Diagnóstico:

```powershell
kubectl get pods
kubectl describe pod NOMBRE_POD
kubectl rollout status deployment/inventario-app --timeout=60s
kubectl rollout history deployment/inventario-app
```

Esperado:

```text
ImagePullBackOff
```

Rollback:

```powershell
kubectl rollout undo deployment/inventario-app
kubectl rollout status deployment/inventario-app --timeout=180s
kubectl get pods
```

A una revisión concreta:

```powershell
kubectl rollout undo deployment/inventario-app --to-revision=NUMERO
```

Verifica salud después del rollback:

```powershell
$URL = minikube service inventario-app --url
curl.exe -i "$URL/health"
curl.exe -i "$URL/version"
```

---

# PARTE F — BLUE-GREEN

## 26. Desplegar blue y green

```powershell
kubectl apply -f k8s/blue-green/deployment-blue.yaml
kubectl apply -f k8s/blue-green/service.yaml
kubectl rollout status deployment/inventario-app-blue --timeout=180s

kubectl apply -f k8s/blue-green/deployment-green.yaml
kubectl rollout status deployment/inventario-app-green --timeout=180s
```

Ver:

```powershell
kubectl get deployments
kubectl get pods -l app=inventario-app --show-labels
kubectl get service inventario-app -o jsonpath='{.spec.selector}'
```

---

## 27. Cutover blue → green

Selector actual:

```powershell
kubectl get service inventario-app -o jsonpath='{.spec.selector}'
```

Enviar tráfico a green:

```powershell
kubectl patch service inventario-app `
  --type=merge `
  -p '{"spec":{"selector":{"app":"inventario-app","slot":"green"}}}'
```

Verificar:

```powershell
kubectl get service inventario-app -o jsonpath='{.spec.selector}'
```

Rollback a blue:

```powershell
kubectl patch service inventario-app `
  --type=merge `
  -p '{"spec":{"selector":{"app":"inventario-app","slot":"blue"}}}'
```

Concepto clave:

- no se reconstruyen pods;
- solo cambia el selector del Service;
- blue debe permanecer disponible para rollback rápido.

---

# PARTE G — DIAGNÓSTICO RÁPIDO

## 28. Cuando algo falla, usa este orden

```powershell
kubectl get pods
kubectl get deployment
kubectl get service
kubectl get endpoints
kubectl describe pod NOMBRE_POD
kubectl logs NOMBRE_POD
kubectl logs NOMBRE_POD --previous
kubectl get events --sort-by=.metadata.creationTimestamp
```

### ImagePullBackOff

```powershell
kubectl describe pod NOMBRE_POD
```

Revisa:

- imagen y etiqueta;
- paquete público o privado;
- credenciales;
- errores de descarga.

### CrashLoopBackOff

```powershell
kubectl logs NOMBRE_POD
kubectl logs NOMBRE_POD --previous
kubectl describe pod NOMBRE_POD
```

### Pod Running 0/1

```powershell
kubectl describe pod NOMBRE_POD
kubectl logs NOMBRE_POD
```

Revisa readiness, ruta `/health`, puerto y tiempo de arranque.

### Service no responde

```powershell
kubectl get pods --show-labels
kubectl get service inventario-app -o yaml
kubectl get endpoints inventario-app
kubectl describe service inventario-app
```

Comprueba:

- selector del Service = labels de los pods;
- `targetPort` = puerto real del contenedor;
- pods Ready;
- endpoints no vacíos.

---

# PARTE H — SALUD DE LA APLICACIÓN

## 29. Checklist de salud

### Local

```powershell
curl.exe -s -o NUL -w "%{http_code}`n" http://localhost:3000/health
```

### Contenedor

```powershell
docker ps
docker logs inventario-app-local
docker inspect inventario-app-local --format '{{.State.Health.Status}}'
```

### Kubernetes

```powershell
kubectl get pods
kubectl get deployment
kubectl get endpoints
kubectl rollout status deployment/inventario-app
```

### HTTP desde dentro del clúster

```powershell
kubectl run health-check `
  --rm -it `
  --restart=Never `
  --image=curlimages/curl:8.10.1 `
  -- curl -i http://inventario-app/health
```

### Respuesta esperada

```text
HTTP 200
{"status":"ok","ready":true}
```

Estados:

| Código | Interpretación |
|---:|---|
| 200 | Aplicación saludable y lista |
| 503 | Aplicación arrancando o no lista |
| 500 | Falla interna simulada o real |
| 404 | Ruta incorrecta |
| Sin conexión | Puerto, Service, pod o proceso incorrecto |

---

# PARTE I — SIMULACRO DE 20 MINUTOS

## 30. Orden exacto para resolver una práctica

```powershell
# 1. Entrar al proyecto
cd "RUTA_DEL_PROYECTO"

# 2. Revisar archivos y Git
Get-ChildItem
git status

# 3. Probar aplicación
npm ci
npm test

# 4. Construir imagen
docker build -t inventario-app:examen .

# 5. Ejecutar y probar
docker run -d --name inventario-examen -p 3000:3000 inventario-app:examen
curl.exe -i http://localhost:3000/health

# 6. Iniciar clúster
minikube start --driver=docker
kubectl get nodes

# 7. Aplicar manifiestos
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml
kubectl rollout status deployment/inventario-app

# 8. Verificar
kubectl get pods
kubectl get service
kubectl get endpoints

# 9. Actualizar imagen
kubectl set image deployment/inventario-app app=IMAGEN:NUEVA
kubectl rollout status deployment/inventario-app

# 10. Diagnosticar o revertir
kubectl get pods
kubectl rollout history deployment/inventario-app
kubectl rollout undo deployment/inventario-app
```

---

## 31. Evidencia mínima que debes guardar

1. `npm test` aprobado.
2. `docker build` exitoso.
3. `docker ps` con contenedor activo.
4. `curl /health` con HTTP 200.
5. GitHub Actions en verde.
6. Imagen publicada.
7. `kubectl rollout status` exitoso.
8. Pods Ready.
9. Service con endpoints.
10. Actualización y rollback funcionando.

---

## 32. Frases que debes poder explicar

- **Imagen:** plantilla inmutable usada para crear contenedores.
- **Contenedor:** instancia en ejecución de una imagen.
- **Pod:** unidad mínima desplegable de Kubernetes.
- **Deployment:** mantiene el número deseado de pods y gestiona rollouts.
- **Service:** ofrece un punto estable y distribuye tráfico hacia pods.
- **Readiness:** decide si un pod puede recibir tráfico.
- **Liveness:** decide si Kubernetes debe reiniciar el contenedor.
- **Rolling Update:** reemplaza pods gradualmente.
- **Rollback:** vuelve a una revisión anterior.
- **Blue-Green:** dos entornos simultáneos; el Service decide cuál recibe tráfico.
- **Fail-fast:** detener el proceso en cuanto una verificación falla.
- **Continuous Delivery:** la imagen queda lista, pero una persona promueve a Kubernetes.
- **Continuous Deployment:** el pipeline despliega automáticamente.

---

**Regla final:** ante un fallo, no adivines. Ejecuta `get`, luego `describe`, luego `logs`, corrige una sola causa y vuelve a verificar.