# ── SQS: eventos de incidentes ───────────────────────────────────────────────
resource "aws_sqs_queue" "dlq" {
  name                      = "${local.name}-incidentes-dlq"
  message_retention_seconds = 14 * 24 * 3600
  sqs_managed_sse_enabled   = true
}

resource "aws_sqs_queue" "incidentes" {
  name                       = "${local.name}-incidentes-queue"
  visibility_timeout_seconds = local.functions.notificador.timeout * 6
  message_retention_seconds  = 24 * 3600
  receive_wait_time_seconds  = 20
  sqs_managed_sse_enabled    = true

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 3
  })
}

# ── SNS ──────────────────────────────────────────────────────────────────────
# Avisos a pasajeros (cada suscripción filtra por las rutas favoritas).
resource "aws_sns_topic" "alertas" {
  name         = "${local.name}-alertas-rutas"
  display_name = "Alertas de transporte"
}

# Alarmas para el equipo.
resource "aws_sns_topic" "alarmas" {
  name = "${local.name}-alarmas"
}

resource "aws_sns_topic_subscription" "alarmas_email" {
  count = var.alarm_email == "" ? 0 : 1

  topic_arn = aws_sns_topic.alarmas.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}
