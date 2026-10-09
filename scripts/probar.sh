#!/usr/bin/env bash
# Prueba de humo del entorno desplegado. Uso: ./scripts/probar.sh dev  (requiere jq y haber ejecutado crear-usuarios.sh)
set -euo pipefail
ENV="${1:-dev}"; PASS="${2:-Transporte2026}"; D="$(dirname "$0")/../envs/$ENV"
API=$(terraform -chdir="$D" output -raw api_url); CLIENT=$(terraform -chdir="$D" output -raw user_pool_client_id)
POOL=$(terraform -chdir="$D" output -raw user_pool_id); REGION="${POOL%%_*}"
tok() { aws cognito-idp initiate-auth --region "$REGION" --auth-flow USER_PASSWORD_AUTH --client-id "$CLIENT" \
  --auth-parameters "USERNAME=$1,PASSWORD=$PASS" --query AuthenticationResult.IdToken --output text; }
echo "== 1. GET /rutas (sin sesión)"; curl -s "$API/rutas" | jq '.rutas[] | {rutaId,nombre,estado}'
RID=$(curl -s "$API/rutas" | jq -r '.rutas[0].rutaId')
echo "== 2. POST /incidentes sin token"; curl -s -o /dev/null -w "HTTP %{http_code}\n" -X POST "$API/incidentes" -d '{}'
echo "== 3. Conductor reporta"; curl -s -X POST "$API/incidentes" -H "authorization: $(tok conductor.$ENV@ejemplo.pe)" -H 'content-type: application/json' \
  -d "{\"rutaId\":\"$RID\",\"tipo\":\"congestion\",\"descripcion\":\"Tráfico lento por obra\",\"ubicacion\":\"Av. Larco\"}" | jq
echo "== 4. Pasajero NO puede reportar"; curl -s -o /dev/null -w "HTTP %{http_code}\n" -X POST "$API/incidentes" -H "authorization: $(tok pasajero.$ENV@ejemplo.pe)" \
  -H 'content-type: application/json' -d "{\"rutaId\":\"$RID\",\"tipo\":\"otro\",\"descripcion\":\"prueba prueba\"}"
echo "== 5. GET /incidentes (sin sesión)"; curl -s "$API/incidentes?ruta=$RID" | jq '.incidentes[] | {ts,tipo,descripcion}'
