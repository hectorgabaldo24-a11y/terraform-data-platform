/*
Bootstrap del backend remoto. Se ejecuta UNA sola vez, con estado local,
antes de inicializar environments/dev. Crea:
  - Bucket S3 versionado, cifrado (SSE) y sin acceso público para el tfstate.
  - Tabla DynamoDB para el state locking.
*/
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  description = "Región de AWS donde se crea el backend"
  type        = string
  default     = "us-east-1"
}

variable "state_bucket_name" {
  description = "Nombre (globalmente único) del bucket S3 del tfstate"
  type        = string
  default     = "data-platform-tfstate-hector-659500704179"
}

variable "lock_table_name" {
  description = "Nombre de la tabla DynamoDB usada para el state locking"
  type        = string
  default     = "data-platform-tfstate-lock"
}

resource "aws_s3_bucket" "state" {
  bucket = var.state_bucket_name

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket = aws_s3_bucket.state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_dynamodb_table" "lock" {
  name         = var.lock_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }
}

output "state_bucket" {
  description = "Bucket S3 del backend"
  value       = aws_s3_bucket.state.id
}

output "lock_table" {
  description = "Tabla DynamoDB de locking"
  value       = aws_dynamodb_table.lock.name
}
