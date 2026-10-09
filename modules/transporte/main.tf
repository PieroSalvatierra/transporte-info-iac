terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  name       = "${var.project}-${var.environment}"
  azs        = slice(data.aws_availability_zones.available.names, 0, 2)
  nat_n      = var.single_nat_gateway ? 1 : 2
  region     = data.aws_region.current.name
  account_id = data.aws_caller_identity.current.account_id

  # Funciones: las 3 del API + el notificador (consume SQS).
  functions = {
    consulta    = { memory = 256, timeout = 15, description = "Consulta pública de rutas e incidentes y rutas favoritas" }
    empresa     = { memory = 256, timeout = 15, description = "Las empresas publican y actualizan rutas e información" }
    incidentes  = { memory = 256, timeout = 15, description = "Los conductores reportan incidentes" }
    notificador = { memory = 256, timeout = 30, description = "Avisa por SNS a quienes siguen la ruta del incidente" }
  }

  user_groups = {
    pasajero  = "Pasajeros con sesión"
    conductor = "Conductores: pueden reportar incidentes"
    empresa   = "Empresas de transporte: pueden publicar rutas"
  }
}
