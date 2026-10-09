data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

# Un rol por función (mínimo privilegio).
resource "aws_iam_role" "lambda" {
  for_each = local.functions

  name               = "${local.name}-${each.key}-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy_attachment" "basic" {
  for_each = local.functions

  role       = aws_iam_role.lambda[each.key].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "vpc" {
  for_each = local.functions

  role       = aws_iam_role.lambda[each.key].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# consulta: lee rutas/incidentes, gestiona favoritos y la suscripción SNS del usuario.
resource "aws_iam_role_policy" "consulta" {
  name = "consulta"
  role = aws_iam_role.lambda["consulta"].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "LeerRutasEIncidentes"
        Effect = "Allow"
        Action = ["dynamodb:GetItem", "dynamodb:Query", "dynamodb:Scan"]
        Resource = [
          aws_dynamodb_table.rutas.arn,
          aws_dynamodb_table.incidentes.arn,
          "${aws_dynamodb_table.incidentes.arn}/index/*"
        ]
      },
      {
        Sid      = "FavoritosDelUsuario"
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:PutItem"]
        Resource = aws_dynamodb_table.usuarios.arn
      },
      {
        Sid      = "SuscribirAlertas"
        Effect   = "Allow"
        Action   = ["sns:Subscribe", "sns:ListSubscriptionsByTopic"]
        Resource = aws_sns_topic.alertas.arn
      },
      {
        Sid      = "AjustarSuscripcion"
        Effect   = "Allow"
        Action   = ["sns:SetSubscriptionAttributes", "sns:Unsubscribe"]
        Resource = "${aws_sns_topic.alertas.arn}:*"
      }
    ]
  })
}

# empresa: crea y actualiza rutas.
resource "aws_iam_role_policy" "empresa" {
  name = "empresa"
  role = aws_iam_role.lambda["empresa"].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:PutItem"]
        Resource = aws_dynamodb_table.rutas.arn
      }
    ]
  })
}

# incidentes: valida la ruta, guarda el incidente y publica el evento en SQS.
resource "aws_iam_role_policy" "incidentes" {
  name = "incidentes"
  role = aws_iam_role.lambda["incidentes"].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ValidarRuta"
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem"]
        Resource = aws_dynamodb_table.rutas.arn
      },
      {
        Sid      = "GuardarIncidente"
        Effect   = "Allow"
        Action   = ["dynamodb:PutItem"]
        Resource = aws_dynamodb_table.incidentes.arn
      },
      {
        Sid      = "PublicarEvento"
        Effect   = "Allow"
        Action   = ["sqs:SendMessage"]
        Resource = aws_sqs_queue.incidentes.arn
      }
    ]
  })
}

# notificador: consume SQS y publica en SNS.
resource "aws_iam_role_policy" "notificador" {
  name = "notificador"
  role = aws_iam_role.lambda["notificador"].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ConsumirCola"
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:ChangeMessageVisibility"
        ]
        Resource = aws_sqs_queue.incidentes.arn
      },
      {
        Sid      = "PublicarAviso"
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = aws_sns_topic.alertas.arn
      }
    ]
  })
}
