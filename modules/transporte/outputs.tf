output "account_id" {
  description = "ID de la cuenta AWS donde se desplegó (útil para las evidencias)."
  value       = local.account_id
}

output "region" {
  value = local.region
}

output "web_url" {
  description = "URL pública de la web (CloudFront)."
  value       = "https://${aws_cloudfront_distribution.frontend.domain_name}"
}

output "api_url" {
  description = "URL base del API."
  value       = aws_apigatewayv2_api.this.api_endpoint
}

output "login_url" {
  description = "Pantalla de inicio de sesión (Cognito)."
  value       = "https://${aws_cognito_user_pool_domain.this.domain}.auth.${local.region}.amazoncognito.com/login?client_id=${aws_cognito_user_pool_client.web.id}&response_type=token&scope=openid+email+profile&redirect_uri=https://${aws_cloudfront_distribution.frontend.domain_name}/"
}

output "user_pool_id" {
  value = aws_cognito_user_pool.this.id
}

output "user_pool_client_id" {
  value = aws_cognito_user_pool_client.web.id
}

output "vpc_id" {
  value = aws_vpc.this.id
}

output "tables" {
  value = {
    rutas      = aws_dynamodb_table.rutas.name
    incidentes = aws_dynamodb_table.incidentes.name
    usuarios   = aws_dynamodb_table.usuarios.name
  }
}

output "queue_url" {
  value = aws_sqs_queue.incidentes.url
}

output "dlq_url" {
  value = aws_sqs_queue.dlq.url
}

output "alerts_topic_arn" {
  value = aws_sns_topic.alertas.arn
}

output "frontend_bucket" {
  value = aws_s3_bucket.frontend.id
}
