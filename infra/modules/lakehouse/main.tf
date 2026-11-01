data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  warehouse_path = "s3://${var.bucket_name}/${var.warehouse_prefix}"
  # Misma convención de rutas que usa GlueCatalog: <warehouse>/<db>.db/<tabla>
  database_location = "${local.warehouse_path}/${var.database_name}.db"
  table_location    = "${local.database_location}/${var.table_name}"

  glue_arn_prefix = "arn:aws:glue:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}"
}

# ---------------------------------------------------------------------------
# Catálogo: base de datos del Glue Data Catalog (metastore central)
# ---------------------------------------------------------------------------
resource "aws_glue_catalog_database" "lakehouse_db" {
  name         = var.database_name
  description  = "Lakehouse de la plataforma de datos: tablas Apache Iceberg escritas por Managed Flink"
  location_uri = local.database_location

  tags = var.tags
}

# ---------------------------------------------------------------------------
# Tabla Iceberg (formato v2) con esquema y particionado gobernados por Terraform.
# Glue escribe el primer metadata.json en la ubicación de la tabla; a partir de
# ahí cada checkpoint de Flink agrega un snapshot y actualiza metadata_location.
# ---------------------------------------------------------------------------
resource "aws_glue_catalog_table" "ventanas_clientes" {
  name          = var.table_name
  database_name = aws_glue_catalog_database.lakehouse_db.name
  description   = "Métricas por cliente y ventana de 1 minuto (event time) con estado acumulado y alertas"

  open_table_format_input {
    iceberg_input {
      metadata_operation = "CREATE"
      version            = "2"

      iceberg_table_input {
        location = local.table_location

        schema {
          schema_id = 0
          type      = "struct"

          fields {
            id       = 1
            name     = "window_start"
            type     = jsonencode("timestamp")
            required = false
            doc      = "Inicio de la ventana (UTC)"
          }
          fields {
            id       = 2
            name     = "window_end"
            type     = jsonencode("timestamp")
            required = false
            doc      = "Fin de la ventana (UTC)"
          }
          fields {
            id       = 3
            name     = "cliente_id"
            type     = jsonencode("string")
            required = false
          }
          fields {
            id       = 4
            name     = "total_operaciones"
            type     = jsonencode("long")
            required = false
          }
          fields {
            id       = 5
            name     = "cantidad_compras"
            type     = jsonencode("long")
            required = false
          }
          fields {
            id       = 6
            name     = "importe_total_compras"
            type     = jsonencode("double")
            required = false
          }
          fields {
            id       = 7
            name     = "importe_promedio_compras"
            type     = jsonencode("double")
            required = false
          }
          fields {
            id       = 8
            name     = "ventanas_procesadas"
            type     = jsonencode("long")
            required = false
            doc      = "ValueState: ventanas acumuladas del cliente"
          }
          fields {
            id       = 9
            name     = "importe_acumulado"
            type     = jsonencode("double")
            required = false
            doc      = "ValueState: importe histórico de compras del cliente"
          }
          fields {
            id       = 10
            name     = "variacion_pct"
            type     = jsonencode("double")
            required = false
            doc      = "Variación contra la ventana anterior del cliente"
          }
          fields {
            id       = 11
            name     = "alerta"
            type     = jsonencode("string")
            required = false
            doc      = "PICO_COMPRAS o null"
          }
        }

        # Particionado oculto por día del inicio de ventana (ver README: partition pruning).
        partition_spec {
          spec_id = 0

          fields {
            field_id  = 1000
            name      = "window_start_day"
            source_id = 1
            transform = "day"
          }
        }

        properties = {
          "write.format.default"                       = "parquet"
          "write.parquet.compression-codec"            = "zstd"
          "write.metadata.delete-after-commit.enabled" = "true"
          "write.metadata.previous-versions-max"       = "100"
          "commit.retry.num-retries"                   = "10"
        }
      }
    }
  }

  # Después de la creación, Iceberg es el dueño de la metadata: cada commit de
  # Flink cambia metadata_location y las columnas en Glue. Sin esto, Terraform
  # intentaría "revertir" esos cambios y desincronizaría la tabla.
  # La evolución de esquema se hace con Iceberg (ALTER TABLE en Athena), no recreando.
  lifecycle {
    ignore_changes = [parameters, storage_descriptor, table_type, open_table_format_input]
  }
}

# ---------------------------------------------------------------------------
# Athena: workgroup para consultar la tabla (engine v3 soporta Iceberg)
# ---------------------------------------------------------------------------
resource "aws_athena_workgroup" "lakehouse" {
  name          = "${var.name_prefix}-lakehouse"
  description   = "Consultas SQL sobre las tablas Iceberg de lakehouse_db"
  force_destroy = true

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true

    engine_version {
      selected_engine_version = "Athena engine version 3"
    }

    result_configuration {
      output_location = "s3://${var.bucket_name}/athena-results/"

      encryption_configuration {
        encryption_option = "SSE_S3"
      }
    }
  }

  tags = var.tags
}
