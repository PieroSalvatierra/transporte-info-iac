locals {
  # Rutas del API. auth = false => consulta pública (sin iniciar sesión).
  api_routes = {
    "GET /rutas"          = { fn = "consulta", auth = false }
    "GET /rutas/{rutaId}" = { fn = "consulta", auth = false }
    "GET /incidentes"     = { fn = "consulta", auth = false }
    "GET /favoritos"      = { fn = "consulta", auth = true }
    "PUT /favoritos"      = { fn = "consulta", auth = true }
    "POST /rutas"         = { fn = "empresa", auth = true }
    "PUT /rutas/{rutaId}" = { fn = "empresa", auth = true }
    "POST /incidentes"    = { fn = "incidentes", auth = true }
  }

  api_functions = toset(["consulta", "empresa", "incidentes"])
}

resource "aws_apigatewayv2_api" "this" {
  name          = "${local.name}-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = concat(["https://${aws_cloudfront_distribution.frontend.domain_name}"], var.extra_cors_origins)
    allow_methods = ["GET", "POST", "PUT", "OPTIONS"]
    allow_headers = ["content-type", "authorization"]
    max_age       = 300
  }
}

# Valida el token JWT de Cognito antes de invocar la Lambda.
resource "aws_apigatewayv2_authorizer" "cognito" {
  api_id           = aws_apigatewayv2_api.this.id
  name             = "cognito-jwt"
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]

  jwt_configuration {
    audience = [aws_cognito_user_pool_client.web.id]
    issuer   = "https://cognito-idp.${local.region}.amazonaws.com/${aws_cognito_user_pool.this.id}"
  }
}

resource "aws_apigatewayv2_integration" "this" {
  for_each = local.api_functions

  api_id                 = aws_apigatewayv2_api.this.id
  integration_type       = "AWS_PROXY"
  integration_method     = "POST"
  integration_uri        = aws_lambda_function.this[each.key].invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "this" {
  for_each = local.api_routes

  api_id             = aws_apigatewayv2_api.this.id
  route_key          = each.key
  target             = "integrations/${aws_apigatewayv2_integration.this[each.value.fn].id}"
  authorization_type = each.value.auth ? "JWT" : "NONE"
  authorizer_id      = each.value.auth ? aws_apigatewayv2_authorizer.cognito.id : null
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.this.id
  name        = "$default"
  auto_deploy = true

  default_route_settings {
    throttling_rate_limit  = var.api_throttling_rate_limit
    throttling_burst_limit = var.api_throttling_burst_limit
  }

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.apigw.arn
    format = jsonencode({
      requestId        = "$context.requestId"
      ip               = "$context.identity.sourceIp"
      requestTime      = "$context.requestTime"
      routeKey         = "$context.routeKey"
      status           = "$context.status"
      responseLength   = "$context.responseLength"
      authorizerError  = "$context.authorizer.error"
      integrationError = "$context.integrationErrorMessage"
    })
  }

  depends_on = [aws_apigatewayv2_route.this]
}

resource "aws_cloudwatch_log_group" "apigw" {
  name              = "/aws/apigateway/${local.name}"
  retention_in_days = var.log_retention_days
}

resource "aws_lambda_permission" "apigw" {
  for_each = local.api_functions

  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.this[each.key].function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/*/*"
}
