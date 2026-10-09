# Las 4 funciones comparten un único paquete (lambdas/src) y se distinguen por el handler.
# El runtime nodejs20.x ya incluye el AWS SDK v3, así que no hay que instalar dependencias.
data "archive_file" "src" {
  type        = "zip"
  source_dir  = "${var.lambda_source_root}/src"
  output_path = "${path.root}/.build/${local.name}-lambdas.zip"
}

resource "aws_cloudwatch_log_group" "lambda" {
  for_each = local.functions

  name              = "/aws/lambda/${local.name}-${each.key}"
  retention_in_days = var.log_retention_days
}

resource "aws_lambda_function" "this" {
  for_each = local.functions

  function_name    = "${local.name}-${each.key}"
  description      = each.value.description
  role             = aws_iam_role.lambda[each.key].arn
  runtime          = "nodejs20.x"
  handler          = "${each.key}.handler"
  architectures    = ["x86_64"]
  memory_size      = each.value.memory
  timeout          = each.value.timeout
  filename         = data.archive_file.src.output_path
  source_code_hash = data.archive_file.src.output_base64sha256

  environment {
    variables = {
      TABLE_RUTAS       = aws_dynamodb_table.rutas.name
      TABLE_INCIDENTES  = aws_dynamodb_table.incidentes.name
      TABLE_USUARIOS    = aws_dynamodb_table.usuarios.name
      QUEUE_URL         = aws_sqs_queue.incidentes.url
      TOPIC_ARN         = aws_sns_topic.alertas.arn
      INCIDENT_TTL_DAYS = tostring(var.incident_ttl_days)
    }
  }

  # Las ENI se reparten en las dos subredes privadas (AZ-a y AZ-b).
  vpc_config {
    subnet_ids         = aws_subnet.private[*].id
    security_group_ids = [aws_security_group.lambda.id]
  }

  depends_on = [
    aws_cloudwatch_log_group.lambda,
    aws_iam_role_policy_attachment.basic,
    aws_iam_role_policy_attachment.vpc,
    aws_iam_role_policy.consulta,
    aws_iam_role_policy.empresa,
    aws_iam_role_policy.incidentes,
    aws_iam_role_policy.notificador,
    aws_vpc_endpoint.dynamodb,
    aws_vpc_endpoint.sqs,
    aws_vpc_endpoint.sns,
  ]
}

# SQS -> notificador (lotes de 5, reintentos por mensaje).
resource "aws_lambda_event_source_mapping" "notificador" {
  event_source_arn        = aws_sqs_queue.incidentes.arn
  function_name           = aws_lambda_function.this["notificador"].arn
  batch_size              = 5
  function_response_types = ["ReportBatchItemFailures"]
  enabled                 = true
}
