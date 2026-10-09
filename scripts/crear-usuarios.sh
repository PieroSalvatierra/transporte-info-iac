#!/usr/bin/env bash
# Crea 3 usuarios de prueba en Cognito (pasajero, conductor, empresa).
# Uso: ./scripts/crear-usuarios.sh dev
set -euo pipefail
ENV="${1:-dev}"; PASS="${2:-Transporte2026}"
POOL=$(terraform -chdir="$(dirname "$0")/../envs/$ENV" output -raw user_pool_id)
REGION="${POOL%%_*}"   # us-east-2_xxxx -> us-east-2
for G in pasajero conductor empresa; do
  EMAIL="$G.$ENV@ejemplo.pe"
  aws cognito-idp admin-create-user --region $REGION --user-pool-id "$POOL" --username "$EMAIL" \
    --user-attributes Name=email,Value="$EMAIL" Name=email_verified,Value=true --message-action SUPPRESS >/dev/null 2>&1 || true
  aws cognito-idp admin-set-user-password --region $REGION --user-pool-id "$POOL" --username "$EMAIL" --password "$PASS" --permanent
  aws cognito-idp admin-add-user-to-group --region $REGION --user-pool-id "$POOL" --username "$EMAIL" --group-name "$G"
  echo "OK  $EMAIL -> grupo $G"
done
echo "Contraseña de los 3 usuarios: $PASS"
