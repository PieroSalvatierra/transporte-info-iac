# Guía de evidencias para el PDF de entrega

El PDF debe llevar, con **fecha/hora visible** y **datos de la cuenta** (ID de cuenta y usuario/rol en la esquina superior derecha de la consola):

## 1. Cuenta y despliegue
- [ ] `aws sts get-caller-identity` (terminal): muestra Account y Arn.
- [ ] `terraform apply` terminado: `Apply complete! Resources: N added` + `terraform output`.
- [ ] Repetir por cada entorno desplegado (DEV, QA, PROD) o, como mínimo, `terraform plan` de cada carpeta.

## 2. Consola AWS (región us-east-2, ID de cuenta visible)
- [ ] VPC: subredes, NAT Gateways, Internet Gateway y **Endpoints** (DynamoDB, SQS, SNS) — o el *Resource map*.
- [ ] CloudFront (distribución) + S3 del frontend (+ WAF solo si `enable_waf = true`).
- [ ] Cognito: User pool, grupos (pasajero, conductor, empresa) y usuarios.
- [ ] API Gateway: rutas y autorizador JWT.
- [ ] Lambda: las 4 funciones (pestaña VPC y variables de entorno).
- [ ] DynamoDB: 3 tablas y los items de ejemplo (Explore items).
- [ ] SQS: cola y DLQ (redrive = 3). SNS: topics.
- [ ] IAM: los 4 roles. CloudWatch: log groups y alarmas.

## 3. Funcionamiento
- [ ] La web abierta en `web_url` mostrando rutas **sin iniciar sesión**.
- [ ] Inicio de sesión de conductor y reporte de un incidente.
- [ ] Inicio de sesión de empresa y ruta publicada.
- [ ] Salida de `scripts\probar.ps1` (200 público, 401 sin token, 201 conductor, 403 pasajero).
- [ ] Item del incidente en DynamoDB y logs de `notificador` en CloudWatch (y el correo de aviso, si lo configuraste).

## 4. Enlace y destrucción
- [ ] URL del repositorio con este README.md: `https://github.com/<usuario>/<repo>`
- [ ] `terraform destroy` terminado: `Destroy complete! Resources: N destroyed.` (por cada entorno).
- [ ] Consola mostrando que ya no existen VPC / NAT / CloudFront / tablas / Lambdas.

Consejo: incluye en cada captura la barra superior de la consola (ID de cuenta) y ordénalas como en esta lista.
