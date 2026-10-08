locals {
  name_prefix = "${var.project_name}-${var.environment}"

  tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# Bucket del data lake (lo consumirán los módulos de streaming).
resource "aws_s3_bucket" "data_platform" {
  bucket = "${local.name_prefix}-bucket"
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

module "network" {
  source = "../../modules/network"

  name_prefix = local.name_prefix
  vpc_cidr    = var.vpc_cidr
  az_count    = var.az_count
}

module "identity" {
  source = "../../modules/identity"

  name_prefix     = local.name_prefix
  data_bucket_arn = aws_s3_bucket.data_platform.arn
  data_prefix     = var.data_prefix
}
