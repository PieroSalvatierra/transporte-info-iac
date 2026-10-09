# Hay mensajes en la DLQ: un incidente falló 3 veces al notificarse.
resource "aws_cloudwatch_metric_alarm" "dlq" {
  alarm_name          = "${local.name}-dlq-mensajes"
  alarm_description   = "Hay mensajes en la DLQ de incidentes (fallaron 3 intentos)."
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = aws_sqs_queue.dlq.name
  }

  alarm_actions = [aws_sns_topic.alarmas.arn]
}

# Errores en cualquiera de las 4 Lambdas.
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  for_each = local.functions

  alarm_name          = "${local.name}-${each.key}-errores"
  alarm_description   = "La Lambda ${each.key} registró errores."
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.this[each.key].function_name
  }

  alarm_actions = [aws_sns_topic.alarmas.arn]
}
