variable "project" {
  description = "Prefijo del proyecto usado en los nombres de los recursos."
  type        = string
  default     = "transporte-info"
}

variable "environment" {
  description = "Entorno de despliegue: dev, qa o prod."
  type        = string

  validation {
    condition     = contains(["dev", "qa", "prod"], var.environment)
    error_message = "environment debe ser dev, qa o prod."
  }
}

# ── Red ──────────────────────────────────────────────────────────────────────
variable "vpc_cidr" {
  description = "CIDR de la VPC."
  type        = string
}

variable "public_subnet_cidrs" {
  description = "CIDRs de las subredes públicas (una por AZ, 2 AZ)."
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "CIDRs de las subredes privadas (una por AZ, 2 AZ)."
  type        = list(string)
}

variable "single_nat_gateway" {
  description = "true = un solo NAT Gateway (ahorro, usado en DEV). false = uno por AZ (alta disponibilidad)."
  type        = bool
  default     = false
}

# ── Código ───────────────────────────────────────────────────────────────────
variable "lambda_source_root" {
  description = "Ruta a la carpeta lambdas/ (contiene src/ con las 4 funciones)."
  type        = string
}

variable "frontend_source_root" {
  description = "Ruta a la carpeta frontend/ (index.html, app.js, styles.css)."
  type        = string
}

# ── Aplicación ───────────────────────────────────────────────────────────────
variable "incident_ttl_days" {
  description = "Días que un incidente permanece visible antes de expirar (TTL de DynamoDB)."
  type        = number
  default     = 7
}

variable "demo_data" {
  description = "Carga 3 rutas de ejemplo en DynamoDB para poder probar la web."
  type        = bool
  default     = true
}

variable "extra_cors_origins" {
  description = "Orígenes adicionales permitidos (por ejemplo http://localhost:8080 para desarrollo)."
  type        = list(string)
  default     = []
}

variable "api_throttling_rate_limit" {
  description = "Solicitudes por segundo permitidas en el API."
  type        = number
  default     = 1000
}

variable "api_throttling_burst_limit" {
  type    = number
  default = 2000
}

# ── Seguridad / observabilidad ───────────────────────────────────────────────
variable "enable_waf" {
  description = "Asocia un AWS WAF (reglas administradas + límite por IP) a CloudFront."
  type        = bool
  default     = true
}

variable "waf_rate_limit" {
  description = "Máximo de solicitudes por IP cada 5 minutos antes de bloquear."
  type        = number
  default     = 2000
}

variable "log_retention_days" {
  type    = number
  default = 14
}

variable "alarm_email" {
  description = "Correo que recibirá las alarmas (opcional; hay que confirmar la suscripción SNS)."
  type        = string
  default     = ""
}
