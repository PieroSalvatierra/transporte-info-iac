# Crea 3 usuarios de prueba en Cognito (pasajero, conductor, empresa) para el entorno indicado.
# Uso:  .\scripts\crear-usuarios.ps1 -Env dev
param(
  [ValidateSet("dev","qa","prod")] [string]$Env = "dev",
  [string]$Password = "Transporte2026"
)
$ErrorActionPreference = "Stop"
$root = Join-Path $PSScriptRoot ".."
$pool = terraform -chdir="$root/envs/$Env" output -raw user_pool_id
$region = $pool.Split("_")[0]   # us-east-2_xxxx -> us-east-2

$users = @(
  @{ email = "pasajero.$Env@ejemplo.pe";  group = "pasajero"  },
  @{ email = "conductor.$Env@ejemplo.pe"; group = "conductor" },
  @{ email = "empresa.$Env@ejemplo.pe";   group = "empresa"   }
)
foreach ($u in $users) {
  aws cognito-idp admin-create-user --region $region --user-pool-id $pool --username $u.email `
    --user-attributes Name=email,Value=$($u.email) Name=email_verified,Value=true --message-action SUPPRESS 2>$null | Out-Null
  aws cognito-idp admin-set-user-password --region $region --user-pool-id $pool --username $u.email --password $Password --permanent
  aws cognito-idp admin-add-user-to-group --region $region --user-pool-id $pool --username $u.email --group-name $u.group
  Write-Host "OK  $($u.email)  ->  grupo $($u.group)"
}
Write-Host "`nContraseña de los 3 usuarios: $Password"
