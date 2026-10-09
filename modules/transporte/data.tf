# ── DynamoDB ─────────────────────────────────────────────────────────────────
# Rutas publicadas por las empresas.
resource "aws_dynamodb_table" "rutas" {
  name         = "${local.name}-rutas"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "rutaId"

  attribute {
    name = "rutaId"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }
}

# Incidentes reportados (se borran solos con TTL).
resource "aws_dynamodb_table" "incidentes" {
  name         = "${local.name}-incidentes"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "rutaId"
  range_key    = "ts"

  attribute {
    name = "rutaId"
    type = "S"
  }

  attribute {
    name = "ts"
    type = "S"
  }

  attribute {
    name = "estado"
    type = "S"
  }

  # Últimos incidentes activos de todas las rutas.
  global_secondary_index {
    name            = "estado-ts"
    hash_key        = "estado"
    range_key       = "ts"
    projection_type = "ALL"
  }

  ttl {
    attribute_name = "expiraEn"
    enabled        = true
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }
}

# Rutas favoritas de cada pasajero con sesión.
resource "aws_dynamodb_table" "usuarios" {
  name         = "${local.name}-usuarios"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "userId"

  attribute {
    name = "userId"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }
}

# ── Datos de ejemplo ─────────────────────────────────────────────────────────
locals {
  demo_rutas = {
    "R-DEMO-01" = {
      nombre  = "Trujillo Centro - Huanchaco"
      empresa = "Transportes Demo Norte"
      origen  = "Plaza de Armas"
      destino = "Huanchaco"
      horario = "05:30 - 22:00 · cada 10 min"
      tarifa  = "S/ 1.50"
      paradas = ["Plaza de Armas", "Av. España", "Óvalo Larco", "Av. Larco", "Huanchaco"]
    }
    "R-DEMO-02" = {
      nombre  = "Víctor Larco - Mall Plaza"
      empresa = "Transportes Demo Norte"
      origen  = "Víctor Larco"
      destino = "Mall Plaza"
      horario = "06:00 - 21:30 · cada 12 min"
      tarifa  = "S/ 1.30"
      paradas = ["Víctor Larco", "Av. Larco", "Av. Mansiche", "Mall Plaza"]
    }
    "R-DEMO-03" = {
      nombre  = "La Esperanza - Centro"
      empresa = "Empresa Demo Sur"
      origen  = "La Esperanza"
      destino = "Plaza de Armas"
      horario = "05:00 - 23:00 · cada 8 min"
      tarifa  = "S/ 1.50"
      paradas = ["La Esperanza", "Av. Túpac Amaru", "Av. Vallejo", "Plaza de Armas"]
    }
  }
}

resource "aws_dynamodb_table_item" "demo_rutas" {
  for_each = var.demo_data ? local.demo_rutas : {}

  table_name = aws_dynamodb_table.rutas.name
  hash_key   = aws_dynamodb_table.rutas.hash_key

  item = jsonencode({
    rutaId    = { S = each.key }
    nombre    = { S = each.value.nombre }
    empresa   = { S = each.value.empresa }
    empresaId = { S = "demo" }
    origen    = { S = each.value.origen }
    destino   = { S = each.value.destino }
    horario   = { S = each.value.horario }
    tarifa    = { S = each.value.tarifa }
    estado    = { S = "operativa" }
    paradas   = { L = [for p in each.value.paradas : { S = p }] }
    updatedAt = { S = "2026-01-01T00:00:00.000Z" }
  })
}
