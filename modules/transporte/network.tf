# ── VPC ──────────────────────────────────────────────────────────────────────
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${local.name}-vpc" }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = { Name = "${local.name}-igw" }
}

# ── Subredes ─────────────────────────────────────────────────────────────────
resource "aws_subnet" "public" {
  count = 2

  vpc_id                  = aws_vpc.this.id
  availability_zone       = local.azs[count.index]
  cidr_block              = var.public_subnet_cidrs[count.index]
  map_public_ip_on_launch = false

  tags = { Name = "${local.name}-public-${count.index == 0 ? "a" : "b"}" }
}

resource "aws_subnet" "private" {
  count = 2

  vpc_id            = aws_vpc.this.id
  availability_zone = local.azs[count.index]
  cidr_block        = var.private_subnet_cidrs[count.index]

  tags = { Name = "${local.name}-private-${count.index == 0 ? "a" : "b"}" }
}

# ── NAT Gateways ─────────────────────────────────────────────────────────────
resource "aws_eip" "nat" {
  count  = local.nat_n
  domain = "vpc"

  tags = { Name = "${local.name}-nat-eip-${count.index == 0 ? "a" : "b"}" }

  depends_on = [aws_internet_gateway.this]
}

resource "aws_nat_gateway" "this" {
  count = local.nat_n

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = { Name = "${local.name}-nat-${count.index == 0 ? "a" : "b"}" }

  depends_on = [aws_internet_gateway.this]
}

# ── Rutas ────────────────────────────────────────────────────────────────────
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = { Name = "${local.name}-public-rt" }
}

resource "aws_route_table_association" "public" {
  count = 2

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  count  = 2
  vpc_id = aws_vpc.this.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this[var.single_nat_gateway ? 0 : count.index].id
  }

  tags = { Name = "${local.name}-private-rt-${count.index == 0 ? "a" : "b"}" }
}

resource "aws_route_table_association" "private" {
  count = 2

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# ── Security Groups ──────────────────────────────────────────────────────────
resource "aws_security_group" "lambda" {
  name        = "${local.name}-sg-lambda"
  description = "Lambdas: sin entrada; salida 443 solo hacia los endpoints"
  vpc_id      = aws_vpc.this.id

  tags = { Name = "${local.name}-sg-lambda" }
}

resource "aws_security_group" "vpce" {
  name        = "${local.name}-sg-vpce"
  description = "Endpoints de interfaz (SQS y SNS): 443 solo desde las Lambdas"
  vpc_id      = aws_vpc.this.id

  tags = { Name = "${local.name}-sg-vpce" }
}

resource "aws_vpc_security_group_egress_rule" "lambda_to_dynamodb" {
  security_group_id = aws_security_group.lambda.id
  description       = "HTTPS al Gateway Endpoint de DynamoDB"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  prefix_list_id    = aws_vpc_endpoint.dynamodb.prefix_list_id
}

resource "aws_vpc_security_group_egress_rule" "lambda_to_vpce" {
  security_group_id            = aws_security_group.lambda.id
  description                  = "HTTPS a los Interface Endpoints (SQS y SNS)"
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  referenced_security_group_id = aws_security_group.vpce.id
}

resource "aws_vpc_security_group_ingress_rule" "vpce_from_lambda" {
  security_group_id            = aws_security_group.vpce.id
  description                  = "443 desde las Lambdas"
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  referenced_security_group_id = aws_security_group.lambda.id
}

# ── VPC Endpoints ────────────────────────────────────────────────────────────
resource "aws_vpc_endpoint" "dynamodb" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${local.region}.dynamodb"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = aws_route_table.private[*].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "SoloTablasDelProyecto"
        Effect    = "Allow"
        Principal = "*"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Query",
          "dynamodb:Scan",
          "dynamodb:BatchGetItem"
        ]
        Resource = [
          aws_dynamodb_table.rutas.arn,
          aws_dynamodb_table.incidentes.arn,
          "${aws_dynamodb_table.incidentes.arn}/index/*",
          aws_dynamodb_table.usuarios.arn
        ]
      }
    ]
  })

  tags = { Name = "${local.name}-vpce-dynamodb" }
}

resource "aws_vpc_endpoint" "sqs" {
  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${local.region}.sqs"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpce.id]
  private_dns_enabled = true

  tags = { Name = "${local.name}-vpce-sqs" }
}

resource "aws_vpc_endpoint" "sns" {
  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${local.region}.sns"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpce.id]
  private_dns_enabled = true

  tags = { Name = "${local.name}-vpce-sns" }
}
