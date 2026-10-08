terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

data "aws_caller_identity" "current" {}

locals {
  audit_principals = length(var.audit_trusted_principal_arns) > 0 ? var.audit_trusted_principal_arns : ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
}

# ---------------------------------------------------------------------------
# Rol de ejecución para procesamiento de datos (Lambda / Managed Flink)
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "processing_assume" {
  statement {
    sid     = "ProcessingServicesAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com", "kinesisanalytics.amazonaws.com"]
    }

    # Evita el confused deputy: solo servicios de esta cuenta.
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_iam_role" "processing" {
  name               = "${var.name_prefix}-processing-role"
  description        = "Rol de ejecucion para Lambda/Flink con acceso acotado al data lake"
  assume_role_policy = data.aws_iam_policy_document.processing_assume.json

  tags = var.tags
}

data "aws_iam_policy_document" "processing_s3" {
  statement {
    sid       = "ListBucketPrefixOnly"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [var.data_bucket_arn]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = [var.data_prefix, "${var.data_prefix}/*"]
    }
  }

  statement {
    sid       = "ReadWriteObjectsInPrefix"
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:PutObject"]
    resources = ["${var.data_bucket_arn}/${var.data_prefix}/*"]
  }
}

resource "aws_iam_policy" "processing_s3" {
  name        = "${var.name_prefix}-processing-s3"
  description = "s3:ListBucket, GetObject y PutObject restringidos a un prefijo"
  policy      = data.aws_iam_policy_document.processing_s3.json

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "processing_s3" {
  role       = aws_iam_role.processing.name
  policy_arn = aws_iam_policy.processing_s3.arn
}

# Permisos de lectura de Kinesis para Flink; solo se crean si hay streams definidos.
data "aws_iam_policy_document" "processing_kinesis" {
  count = length(var.kinesis_stream_arns) > 0 ? 1 : 0

  statement {
    sid    = "ReadFromKinesisStreams"
    effect = "Allow"
    actions = [
      "kinesis:DescribeStream",
      "kinesis:DescribeStreamSummary",
      "kinesis:GetRecords",
      "kinesis:GetShardIterator",
      "kinesis:ListShards",
      "kinesis:SubscribeToShard",
    ]
    resources = var.kinesis_stream_arns
  }
}

resource "aws_iam_role_policy" "processing_kinesis" {
  count = length(var.kinesis_stream_arns) > 0 ? 1 : 0

  name   = "${var.name_prefix}-processing-kinesis-read"
  role   = aws_iam_role.processing.id
  policy = data.aws_iam_policy_document.processing_kinesis[0].json
}

# ---------------------------------------------------------------------------
# Rol del plano de control: solo lectura para auditoría
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "audit_assume" {
  statement {
    sid     = "AuditorsAssumeRoleWithMFA"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = local.audit_principals
    }

    condition {
      test     = "Bool"
      variable = "aws:MultiFactorAuthPresent"
      values   = ["true"]
    }
  }
}

resource "aws_iam_role" "audit" {
  name               = "${var.name_prefix}-audit-readonly-role"
  description        = "Rol de plano de control con permisos de solo lectura para auditoria"
  assume_role_policy = data.aws_iam_policy_document.audit_assume.json

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "audit_readonly" {
  role       = aws_iam_role.audit.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}
