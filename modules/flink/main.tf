locals {
  application_name = "${var.project_name}-${var.environment}-flink"
  artifact_key     = "flink/app/flink-app.zip"
  use_vpc          = length(var.private_subnet_ids) > 0

  common_tags = merge(var.tags, {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  })
}

# ---------------------------------------------------------------------------
# Logs de la aplicación
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "flink" {
  name              = "/aws/kinesis-analytics/${local.application_name}"
  retention_in_days = var.log_retention_days

  tags = local.common_tags
}

resource "aws_cloudwatch_log_stream" "flink" {
  name           = "application"
  log_group_name = aws_cloudwatch_log_group.flink.name
}

# ---------------------------------------------------------------------------
# Artefacto: ZIP con main.py + lib/pyflink-dependencies.jar (flink-app/build.ps1)
# ---------------------------------------------------------------------------
resource "aws_s3_object" "flink_application" {
  bucket = var.artifact_bucket
  key    = local.artifact_key
  source = var.artifact_local_path

  # Si cambia el ZIP cambia el hash y Terraform sube una versión nueva,
  # lo que a su vez actualiza la aplicación.
  source_hash  = filemd5(var.artifact_local_path)
  content_type = "application/zip"

  tags = local.common_tags
}

# ---------------------------------------------------------------------------
# Aplicación Managed Service for Apache Flink
# ---------------------------------------------------------------------------
resource "aws_kinesisanalyticsv2_application" "flink" {
  name                   = local.application_name
  description            = "Agregaciones por ventana y detección de picos por cliente (PyFlink)"
  runtime_environment    = "FLINK-1_19"
  service_execution_role = var.execution_role_arn

  start_application = var.start_application

  application_configuration {
    application_code_configuration {
      code_content_type = "ZIPFILE"

      code_content {
        s3_content_location {
          bucket_arn     = "arn:aws:s3:::${var.artifact_bucket}"
          file_key       = aws_s3_object.flink_application.key
          object_version = aws_s3_object.flink_application.version_id
        }
      }
    }

    # Snapshots: estado durable al detener/actualizar la aplicación.
    application_snapshot_configuration {
      snapshots_enabled = true
    }

    run_configuration {
      application_restore_configuration {
        application_restore_type = "RESTORE_FROM_LATEST_SNAPSHOT"
      }

      flink_run_configuration {
        allow_non_restored_state = false
      }
    }

    environment_properties {
      # Le indica a Managed Flink que es una aplicación Python y dónde está el conector.
      property_group {
        property_group_id = "kinesis.analytics.flink.run.options"
        property_map = {
          python  = "main.py"
          jarfile = "lib/pyflink-dependencies.jar"
        }
      }

      # Configuración de negocio que lee main.py.
      property_group {
        property_group_id = "FlinkApplicationProperties"
        property_map = {
          "aws.region"              = var.aws_region
          "input.stream.name"       = var.stream_name
          "input.stream.initpos"    = var.stream_initial_position
          "output.s3.path"          = "s3://${var.artifact_bucket}/${var.output_prefix}/"
          "watermark.delay.seconds" = tostring(var.watermark_delay_seconds)
          "source.idle.timeout"     = "30 s"
        }
      }
    }

    flink_application_configuration {
      # Checkpoints periódicos en el almacenamiento durable (S3) administrado
      # por el servicio: ante una falla el job se reanuda desde el último.
      checkpoint_configuration {
        configuration_type            = "CUSTOM"
        checkpointing_enabled         = true
        checkpoint_interval           = var.checkpoint_interval_ms
        min_pause_between_checkpoints = var.min_pause_between_checkpoints_ms
      }

      monitoring_configuration {
        configuration_type = "CUSTOM"
        log_level          = "INFO"
        metrics_level      = "APPLICATION"
      }

      # KPUs asignadas = ceil(parallelism / parallelism_per_kpu) (+1 KPU de orquestación que cobra el servicio).
      parallelism_configuration {
        configuration_type   = "CUSTOM"
        parallelism          = var.parallelism
        parallelism_per_kpu  = var.parallelism_per_kpu
        auto_scaling_enabled = var.autoscaling_enabled
      }
    }

    dynamic "vpc_configuration" {
      for_each = local.use_vpc ? [1] : []

      content {
        subnet_ids         = var.private_subnet_ids
        security_group_ids = var.security_group_ids
      }
    }
  }

  cloudwatch_logging_options {
    log_stream_arn = aws_cloudwatch_log_stream.flink.arn
  }

  tags = local.common_tags

  # El servicio valida el acceso a S3 y CloudWatch al crear la aplicación.
  depends_on = [aws_iam_role_policy_attachment.flink_access]
}
