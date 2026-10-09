variable "region" {
  type    = string
  default = "us-east-2"
}

variable "alarm_email" {
  description = "Correo para las alarmas (opcional)."
  type        = string
  default     = ""
}

variable "enable_waf" {
  description = "WAF de CloudFront. Solo funciona si la cuenta permite us-east-1 (el scope CLOUDFRONT existe únicamente ahí)."
  type        = bool
  default     = false
}
