# ===========================================================================
# IAM de la capa analítica (Pre-entrega 6)
#
# 1. redshift-service-role: lo asume Redshift (IAM_ROLE default en el SQL)
#      - Streaming Ingestion: lectura del stream de Kinesis + KMS (stream cifrado)
#      - Lakehouse: lectura del Glue Data Catalog y de los archivos Iceberg en S3
# 2. redshift-analyst-role: lo asumen las personas de analítica. Se conecta con
#    credenciales temporales (GetCredentials) y el tag RedshiftDbRoles le otorga
#    el rol de base de datos analytics_role: sin contraseñas de base de datos.
# 3. redshift-refresh-role: lo asume EventBridge Scheduler para refrescar la
#    vista materializada del stream a través de la Redshift Data API.
# ===========================================================================

data "aws_iam_policy_document" "redshift_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["redshift.amazonaws.com", "redshift-serverless.amazonaws.com"]
    }

    # Sólo Redshift actuando en nombre de esta cuenta (evita el "confused deputy").
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

resource "aws_iam_role" "redshift_service" {
  name               = "${var.name_prefix}-redshift-service-role"
  description        = "Rol que asume Redshift Serverless para leer Kinesis (streaming ingestion) y el lakehouse Iceberg"
  assume_role_policy = data.aws_iam_policy_document.redshift_assume.json

  tags = var.tags
}

data "aws_iam_policy_document" "redshift_service" {
  # --- Streaming Ingestion -------------------------------------------------
  statement {
    sid    = "ReadKinesisStream"
    effect = "Allow"
    actions = [
      "kinesis:DescribeStream",
      "kinesis:DescribeStreamSummary",
      "kinesis:GetShardIterator",
      "kinesis:GetRecords",
      "kinesis:ListShards",
    ]
    resources = [var.kinesis_stream_arn]
  }

  # CREATE EXTERNAL SCHEMA ... FROM KINESIS lista los streams de la cuenta.
  # ListStreams no admite restricción por recurso.
  statement {
    sid       = "ListKinesisStreams"
    effect    = "Allow"
    actions   = ["kinesis:ListStreams"]
    resources = ["*"]
  }

  # El stream usa SSE-KMS con la clave administrada aws/kinesis: Redshift
  # descifra los registros sólo a través del servicio Kinesis.
  statement {
    sid       = "DecryptKinesisRecords"
    effect    = "Allow"
    actions   = ["kms:Decrypt"]
    resources = [data.aws_kms_alias.kinesis.target_key_arn]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["kinesis.${local.region}.amazonaws.com"]
    }
  }

  # --- Lakehouse (EXTERNAL SCHEMA sobre el Glue Data Catalog) ---------------
  # Sólo lectura: Redshift consulta las tablas Iceberg, no hace commits.
  statement {
    sid    = "ReadGlueCatalog"
    effect = "Allow"
    actions = [
      "glue:GetDatabase",
      "glue:GetDatabases",
      "glue:GetTable",
      "glue:GetTables",
      "glue:GetPartition",
      "glue:GetPartitions",
      "glue:BatchGetPartition",
    ]
    resources = [
      "${local.glue_arn_prefix}:catalog",
      "${local.glue_arn_prefix}:database/${var.glue_database_name}",
      "${local.glue_arn_prefix}:table/${var.glue_database_name}/*",
    ]
  }

  statement {
    sid       = "ListLakehousePrefix"
    effect    = "Allow"
    actions   = ["s3:ListBucket", "s3:GetBucketLocation"]
    resources = ["arn:aws:s3:::${var.lakehouse_bucket_name}"]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = [var.lakehouse_prefix, "${var.lakehouse_prefix}/*"]
    }
  }

  statement {
    sid       = "ReadLakehouseObjects"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["arn:aws:s3:::${var.lakehouse_bucket_name}/${var.lakehouse_prefix}/*"]
  }
}

resource "aws_iam_role_policy" "redshift_service" {
  name   = "${var.name_prefix}-redshift-streaming-lakehouse"
  role   = aws_iam_role.redshift_service.id
  policy = data.aws_iam_policy_document.redshift_service.json
}

# ---------------------------------------------------------------------------
# Rol IAM de analistas -> rol de base de datos analytics_role
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "analyst_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = length(var.analyst_trusted_principal_arns) > 0 ? var.analyst_trusted_principal_arns : ["arn:aws:iam::${local.account_id}:root"]
    }
  }
}

resource "aws_iam_role" "analyst" {
  name               = "${var.name_prefix}-redshift-analyst"
  description        = "Analistas: consultan Redshift con credenciales IAM temporales y el rol de base de datos ${var.analytics_db_role}"
  assume_role_policy = data.aws_iam_policy_document.analyst_assume.json

  # Redshift Serverless lee este tag al emitir credenciales (GetCredentials) y
  # asigna al usuario IAMR:<rol> los roles de base de datos listados.
  tags = merge(var.tags, { RedshiftDbRoles = var.analytics_db_role })
}

data "aws_iam_policy_document" "analyst" {
  statement {
    sid       = "GetTemporaryDbCredentials"
    effect    = "Allow"
    actions   = ["redshift-serverless:GetCredentials"]
    resources = [aws_redshiftserverless_workgroup.this.arn]
  }

  statement {
    sid    = "RunQueriesWithDataApi"
    effect = "Allow"
    actions = [
      "redshift-data:ExecuteStatement",
      "redshift-data:BatchExecuteStatement",
    ]
    resources = [aws_redshiftserverless_workgroup.this.arn]
  }

  # Estas acciones operan sobre las sentencias del propio usuario; el condition
  # impide ver o cancelar consultas de otras identidades.
  statement {
    sid    = "ReadOwnStatements"
    effect = "Allow"
    actions = [
      "redshift-data:DescribeStatement",
      "redshift-data:GetStatementResult",
      "redshift-data:GetStatementResultV2",
      "redshift-data:CancelStatement",
      "redshift-data:ListStatements",
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "redshift-data:statement-owner-iam-userid"
      values   = ["$${aws:userid}"]
    }
  }
}

resource "aws_iam_role_policy" "analyst" {
  name   = "${var.name_prefix}-redshift-analyst-access"
  role   = aws_iam_role.analyst.id
  policy = data.aws_iam_policy_document.analyst.json
}

# ---------------------------------------------------------------------------
# Rol del refresco programado (EventBridge Scheduler -> Redshift Data API)
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "scheduler_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["scheduler.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

resource "aws_iam_role" "refresh" {
  name               = "${var.name_prefix}-redshift-refresh"
  description        = "EventBridge Scheduler: refresca la vista materializada del stream vía Data API"
  assume_role_policy = data.aws_iam_policy_document.scheduler_assume.json

  # El usuario de base de datos IAMR:<rol> recibe sólo el rol stream_refresher,
  # que únicamente puede ejecutar el procedimiento de refresco.
  tags = merge(var.tags, { RedshiftDbRoles = "stream_refresher" })
}

data "aws_iam_policy_document" "refresh" {
  statement {
    sid       = "GetTemporaryDbCredentials"
    effect    = "Allow"
    actions   = ["redshift-serverless:GetCredentials"]
    resources = [aws_redshiftserverless_workgroup.this.arn]
  }

  statement {
    sid       = "RunRefresh"
    effect    = "Allow"
    actions   = ["redshift-data:ExecuteStatement"]
    resources = [aws_redshiftserverless_workgroup.this.arn]
  }
}

resource "aws_iam_role_policy" "refresh" {
  name   = "${var.name_prefix}-redshift-refresh"
  role   = aws_iam_role.refresh.id
  policy = data.aws_iam_policy_document.refresh.json
}
