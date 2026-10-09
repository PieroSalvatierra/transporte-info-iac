# Prueba de humo del entorno desplegado (útil como evidencia para el PDF).
# Uso:  .\scripts\probar.ps1 -Env dev      (antes ejecuta crear-usuarios.ps1)
param(
  [ValidateSet("dev","qa","prod")] [string]$Env = "dev",
  [string]$Password = "Transporte2026"
)
$ErrorActionPreference = "Stop"
$root = Join-Path $PSScriptRoot ".."
$api = terraform -chdir="$root/envs/$Env" output -raw api_url
$client = terraform -chdir="$root/envs/$Env" output -raw user_pool_client_id
$pool = terraform -chdir="$root/envs/$Env" output -raw user_pool_id
$region = $pool.Split("_")[0]
$web = terraform -chdir="$root/envs/$Env" output -raw web_url

function Get-Token($email) {
  aws cognito-idp initiate-auth --region $region --auth-flow USER_PASSWORD_AUTH --client-id $client `
    --auth-parameters "USERNAME=$email,PASSWORD=$Password" --query AuthenticationResult.IdToken --output text
}

Write-Host "`n== 1. Consulta pública SIN sesión: GET /rutas" -ForegroundColor Cyan
$rutas = (Invoke-RestMethod "$api/rutas").rutas
$rutas | Select-Object rutaId, nombre, estado | Format-Table
$rutaId = $rutas[0].rutaId

Write-Host "== 2. Sin token, publicar es rechazado (401)" -ForegroundColor Cyan
try { Invoke-RestMethod -Method Post "$api/incidentes" -ContentType "application/json" -Body "{}" } catch { Write-Host "Rechazado: $($_.Exception.Response.StatusCode.value__)" }

Write-Host "`n== 3. Conductor reporta un incidente (POST /incidentes)" -ForegroundColor Cyan
$tc = Get-Token "conductor.$Env@ejemplo.pe"
$body = @{ rutaId = $rutaId; tipo = "congestion"; descripcion = "Tráfico lento por obra en la vía"; ubicacion = "Av. Larco" } | ConvertTo-Json
Invoke-RestMethod -Method Post "$api/incidentes" -Headers @{ Authorization = $tc } -ContentType "application/json" -Body $body | ConvertTo-Json

Write-Host "`n== 4. Un pasajero NO puede reportar (403)" -ForegroundColor Cyan
$tp = Get-Token "pasajero.$Env@ejemplo.pe"
try { Invoke-RestMethod -Method Post "$api/incidentes" -Headers @{ Authorization = $tp } -ContentType "application/json" -Body $body } catch { Write-Host "Rechazado: $($_.Exception.Response.StatusCode.value__)" }

Write-Host "`n== 5. Cualquiera ve el incidente SIN sesión: GET /incidentes" -ForegroundColor Cyan
(Invoke-RestMethod "$api/incidentes?ruta=$rutaId").incidentes | Select-Object ts, tipo, descripcion | Format-Table

Write-Host "== Web: $web" -ForegroundColor Green
