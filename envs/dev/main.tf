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
  #   key    = "transporte-info/dev/terraform.tfstate"
  #   region = "us-east-2"
  # }
}

provider "aws" {
  # Región permitida por la cuenta (la SCP de la organización bloquea us-east-1).
  region = var.region

  default_tags {
    tags = {
      Project     = "transporte-info"
      Environment = "dev"
      ManagedBy   = "terraform"
    }
  }
}

module "transporte" {
  source = "../../modules/transporte"

  environment = "dev"

  # Red (cada entorno usa un rango distinto)
  vpc_cidr             = "10.0.0.0/16"
  public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnet_cidrs = ["10.0.11.0/24", "10.0.12.0/24"]
  single_nat_gateway   = true

  # Aplicación
  incident_ttl_days = 3
  demo_data         = true

  # API / seguridad / observabilidad
  api_throttling_rate_limit  = 50
  api_throttling_burst_limit = 100
  enable_waf                 = var.enable_waf
  log_retention_days         = 7
  alarm_email                = var.alarm_email

  lambda_source_root   = "${path.root}/../../lambdas"
  frontend_source_root = "${path.root}/../../frontend"
}
