/* Versión de Terraform, providers y backend remoto (S3 + DynamoDB). */
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # Los backends no admiten variables. Los nombres deben coincidir con los
  # creados en bootstrap/.
  backend "s3" {
    bucket         = "data-platform-tfstate-hector-659500704179"
    key            = "data-platform/dev/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "data-platform-tfstate-lock"
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = local.tags
  }
}
