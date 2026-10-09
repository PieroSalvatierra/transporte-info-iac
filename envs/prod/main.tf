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

  # Estado local por defecto (cada entorno tiene su propio terraform.tfstate).
  # Para estado remoto, crea un bucket S3 y descomenta:
  # backend "s3" {
  #   bucket = "<tu-bucket-de-estado>"
  #   key    = "transporte-info/prod/terraform.tfstate"
  #   region = "us-east-2"
  # }
}

provider "aws" {
  # Región permitida por la cuenta (la SCP de la organización bloquea us-east-1).
  region = var.region

  default_tags {
    tags = {
      Project     = "transporte-info"
      Environment = "prod"
      ManagedBy   = "terraform"
    }
  }
}

module "transporte" {
  source = "../../modules/transporte"

  environment = "prod"

  # Red (cada entorno usa un rango distinto)
  vpc_cidr             = "10.2.0.0/16"
  public_subnet_cidrs  = ["10.2.1.0/24", "10.2.2.0/24"]
  private_subnet_cidrs = ["10.2.11.0/24", "10.2.12.0/24"]
  single_nat_gateway   = false

  # Aplicación
  incident_ttl_days = 14
  demo_data         = true

  # API / seguridad / observabilidad
  api_throttling_rate_limit  = 2000
  api_throttling_burst_limit = 4000
  enable_waf                 = var.enable_waf
  log_retention_days         = 30
  alarm_email                = var.alarm_email

  lambda_source_root   = "${path.root}/../../lambdas"
  frontend_source_root = "${path.root}/../../frontend"
}
