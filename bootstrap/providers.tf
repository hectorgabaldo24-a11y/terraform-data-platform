/* Versión de Terraform y provider. Este módulo usa estado LOCAL a propósito:
   crea el backend remoto que usan los demás entornos. */
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
