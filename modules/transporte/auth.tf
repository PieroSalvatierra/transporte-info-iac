# ── Cognito: pasajeros, conductores y empresas ───────────────────────────────
resource "aws_cognito_user_pool" "this" {
  name                     = "${local.name}-users"
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_uppercase = true
    require_numbers   = true
    require_symbols   = false
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  # Cualquiera puede registrarse como pasajero. Los grupos conductor/empresa
  # solo los asigna un administrador (scripts/crear-usuarios).
  admin_create_user_config {
    allow_admin_create_user_only = false
  }
}

resource "aws_cognito_user_group" "this" {
  for_each = local.user_groups

  name         = each.key
  description  = each.value
  user_pool_id = aws_cognito_user_pool.this.id
}

resource "aws_cognito_user_pool_client" "web" {
  name         = "${local.name}-web"
  user_pool_id = aws_cognito_user_pool.this.id

  generate_secret                      = false
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["implicit"]
  allowed_oauth_scopes                 = ["openid", "email", "profile"]
  supported_identity_providers         = ["COGNITO"]
  prevent_user_existence_errors        = "ENABLED"

  callback_urls = concat(["https://${aws_cloudfront_distribution.frontend.domain_name}/"], [for o in var.extra_cors_origins : "${o}/"])
  logout_urls   = concat(["https://${aws_cloudfront_distribution.frontend.domain_name}/"], [for o in var.extra_cors_origins : "${o}/"])

  # USER_PASSWORD_AUTH permite obtener un token por CLI para probar el API.
  explicit_auth_flows = [
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
  ]

  id_token_validity      = 60
  access_token_validity  = 60
  refresh_token_validity = 7

  token_validity_units {
    id_token      = "minutes"
    access_token  = "minutes"
    refresh_token = "days"
  }
}

# Pantalla de inicio de sesión alojada por Cognito.
resource "aws_cognito_user_pool_domain" "this" {
  domain       = "${local.name}-${local.account_id}"
  user_pool_id = aws_cognito_user_pool.this.id
}
