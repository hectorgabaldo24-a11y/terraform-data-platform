data "aws_caller_identity" "current" {}

locals {
  name_prefix = "${var.project_name}-${var.environment}"

  # Los nombres de bucket S3 son globales: se agrega el ID de cuenta para evitar colisiones.
  data_bucket_name = "${local.name_prefix}-${data.aws_caller_identity.current.account_id}-bucket"

  tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# Bucket del data lake (lo consumirán los módulos de streaming).
resource "aws_s3_bucket" "data_platform" {
  bucket = local.data_bucket_name
}

resource "aws_s3_bucket_server_side_encryption_configuration" "data_platform" {
  bucket = aws_s3_bucket.data_platform.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "data_platform" {
  bucket = aws_s3_bucket.data_platform.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "data_platform" {
  bucket = aws_s3_bucket.data_platform.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Rechaza cualquier acceso al bucket que no use TLS.
data "aws_iam_policy_document" "data_platform_tls" {
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.data_platform.arn, "${aws_s3_bucket.data_platform.arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "data_platform_tls" {
  bucket = aws_s3_bucket.data_platform.id
  policy = data.aws_iam_policy_document.data_platform_tls.json

  depends_on = [aws_s3_bucket_public_access_block.data_platform]
}

module "network" {
  source = "../../modules/network"

  name_prefix             = local.name_prefix
  vpc_cidr                = var.vpc_cidr
  az_count                = var.az_count
  s3_endpoint_bucket_arns = [aws_s3_bucket.data_platform.arn]
}

module "identity" {
  source = "../../modules/identity"

  name_prefix     = local.name_prefix
  data_bucket_arn = aws_s3_bucket.data_platform.arn
  data_prefix     = var.data_prefix

  # Permitir que el rol de procesamiento lea nuestro stream.
  kinesis_stream_arns = [module.kinesis.stream_arn]

  service_linked_role_services = var.service_linked_role_services
}

# Ingesta (Pre-entrega 2): Kinesis Data Stream + Firehose -> S3 (bronze).
module "kinesis" {
  source = "../../modules/kinesis"

  project_name   = var.project_name
  environment    = var.environment
  s3_bucket_name = aws_s3_bucket.data_platform.id

  shard_count = 2

  tags = local.tags
}

# Procesamiento en tiempo real (Pre-entrega 4): Managed Service for Apache Flink.
module "flink" {
  source = "../../modules/flink"

  project_name = var.project_name
  environment  = var.environment
  aws_region   = var.region

  stream_name = module.kinesis.stream_name

  # Reutiliza el rol de procesamiento de identity (ya tiene la lectura de Kinesis).
  execution_role_arn  = module.identity.processing_role_arn
  execution_role_name = module.identity.processing_role_name

  artifact_bucket     = aws_s3_bucket.data_platform.id
  artifact_local_path = "${path.root}/../../flink-app/flink-app.zip"

  # Paralelismo 2 = un slot por shard del stream -> 2 KPUs de procesamiento.
  parallelism         = var.flink_parallelism
  parallelism_per_kpu = 1
  autoscaling_enabled = false

  watermark_delay_seconds = var.flink_watermark_delay_seconds
  start_application       = var.flink_start_application

  # Fuera de la VPC: la VPC del módulo network no tiene NAT ni endpoints de
  # Kinesis/CloudWatch Logs, así que el job no podría alcanzar esos servicios.
  private_subnet_ids = []
  security_group_ids = []

  tags = local.tags

  # La política de lectura de Kinesis del rol vive en identity: debe existir
  # antes de que el job arranque.
  depends_on = [module.identity]
}

