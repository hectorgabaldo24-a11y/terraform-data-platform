data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Clave KMS administrada con la que está cifrado el stream (alias/aws/kinesis).
data "aws_kms_alias" "kinesis" {
  name = "alias/aws/kinesis"
}

locals {
  account_id      = data.aws_caller_identity.current.account_id
  region          = data.aws_region.current.region
  glue_arn_prefix = "arn:aws:glue:${local.region}:${local.account_id}"
}

# ---------------------------------------------------------------------------
# Red: el workgroup no es público. Sólo acepta conexiones al 5439 desde la
# VPC; las consultas de operación y analítica van por la Redshift Data API
# (HTTPS + IAM), que no necesita abrir la red.
# ---------------------------------------------------------------------------
resource "aws_security_group" "redshift" {
  name        = "${var.name_prefix}-redshift"
  description = "Redshift Serverless: 5439 solo desde la VPC de datos"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = "${var.name_prefix}-redshift" })
}

resource "aws_vpc_security_group_ingress_rule" "redshift_from_vpc" {
  security_group_id = aws_security_group.redshift.id
  description       = "Clientes SQL dentro de la VPC"
  ip_protocol       = "tcp"
  from_port         = 5439
  to_port           = 5439
  cidr_ipv4         = var.vpc_cidr
}

resource "aws_vpc_security_group_egress_rule" "redshift_to_vpc" {
  security_group_id = aws_security_group.redshift.id
  description       = "Salida solo dentro de la VPC"
  ip_protocol       = "-1"
  cidr_ipv4         = var.vpc_cidr
}

# ---------------------------------------------------------------------------
# Redshift Serverless: namespace (datos, usuarios, roles IAM) + workgroup (cómputo)
# ---------------------------------------------------------------------------
resource "aws_redshiftserverless_namespace" "this" {
  namespace_name = "${var.name_prefix}-analytics"
  db_name        = var.database_name
  admin_username = var.admin_username

  # Redshift genera la contraseña y la guarda (y rota) en Secrets Manager:
  # no aparece en el código ni en el state de Terraform.
  manage_admin_password = true

  # IAM_ROLE default en el SQL = este rol. Es el único rol asociado.
  iam_roles            = [aws_iam_role.redshift_service.arn]
  default_iam_role_arn = aws_iam_role.redshift_service.arn

  log_exports = ["userlog", "connectionlog", "useractivitylog"]

  tags = var.tags
}

resource "aws_redshiftserverless_workgroup" "this" {
  workgroup_name = "${var.name_prefix}-analytics"
  namespace_name = aws_redshiftserverless_namespace.this.namespace_name
  base_capacity  = var.base_capacity

  subnet_ids          = var.subnet_ids
  security_group_ids  = [aws_security_group.redshift.id]
  publicly_accessible = false

  # Sin enhanced VPC routing, Redshift llega a Kinesis, Glue y S3 por la red
  # administrada de AWS. Con true harían falta endpoints de interfaz para
  # Kinesis y Glue en la VPC (no tiene NAT).
  enhanced_vpc_routing = false

  config_parameter {
    parameter_key   = "require_ssl"
    parameter_value = "true"
  }

  # Corta consultas desbocadas (p. ej. un JOIN sin filtro contra el lakehouse).
  config_parameter {
    parameter_key   = "max_query_execution_time"
    parameter_value = "900"
  }

  tags = var.tags
}

# Tope de gasto: al superar las RPU-horas del día el workgroup se desactiva.
resource "aws_redshiftserverless_usage_limit" "daily_compute" {
  resource_arn  = aws_redshiftserverless_workgroup.this.arn
  usage_type    = "serverless-compute"
  amount        = var.max_rpu_hours_per_day
  period        = "daily"
  breach_action = "deactivate"
}

# ---------------------------------------------------------------------------
# Refresco programado de la vista materializada del stream.
# AUTO REFRESH de Redshift no permite fijar la cadencia y, en Serverless,
# mantiene el cómputo activo de forma continua. Con el scheduler la latencia
# queda acotada (1 minuto) y el refresco se puede apagar desde tfvars.
# ---------------------------------------------------------------------------
resource "aws_scheduler_schedule" "refresh_stream_mv" {
  name        = "${var.name_prefix}-redshift-refresh-stream"
  description = "REFRESH de la vista materializada de Kinesis en Redshift"
  state       = var.refresh_schedule_enabled ? "ENABLED" : "DISABLED"

  schedule_expression = var.refresh_schedule_expression

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = "arn:aws:scheduler:::aws-sdk:redshiftdata:executeStatement"
    role_arn = aws_iam_role.refresh.arn

    # Sin SecretArn: la Data API autentica con el rol IAM del scheduler.
    input = jsonencode({
      WorkgroupName = aws_redshiftserverless_workgroup.this.workgroup_name
      Database      = var.database_name
      Sql           = var.refresh_sql
    })

    retry_policy {
      maximum_retry_attempts       = 0
      maximum_event_age_in_seconds = 60
    }
  }
}

# ---------------------------------------------------------------------------
# Monitoreo: Kinesis (entrada y antigüedad del iterador) + cómputo de Redshift
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_dashboard" "streaming_analytics" {
  dashboard_name = "${var.name_prefix}-streaming-analytics"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "Kinesis: registros entrantes y leídos"
          region = local.region
          view   = "timeSeries"
          stat   = "Sum"
          period = 60
          metrics = [
            ["AWS/Kinesis", "IncomingRecords", "StreamName", var.kinesis_stream_name],
            [".", "GetRecords.Records", ".", "."],
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title   = "Kinesis: antigüedad del iterador (lag de los consumidores)"
          region  = local.region
          view    = "timeSeries"
          stat    = "Maximum"
          period  = 60
          metrics = [["AWS/Kinesis", "GetRecords.IteratorAgeMilliseconds", "StreamName", var.kinesis_stream_name]]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          title   = "Redshift Serverless: RPUs en uso"
          region  = local.region
          view    = "timeSeries"
          stat    = "Average"
          period  = 60
          metrics = [["AWS/Redshift-Serverless", "ComputeCapacity", "Workgroup", aws_redshiftserverless_workgroup.this.workgroup_name]]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          title   = "Redshift Serverless: segundos de cómputo"
          region  = local.region
          view    = "timeSeries"
          stat    = "Sum"
          period  = 300
          metrics = [["AWS/Redshift-Serverless", "ComputeSeconds", "Workgroup", aws_redshiftserverless_workgroup.this.workgroup_name]]
        }
      },
    ]
  })
}
