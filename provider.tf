/* definimos qué versión de Terraform usamos y qué proveedor vamos a utilizar.*/
terraform {
  required_version = ">= 1.5.0" //Terraform debe ser 1.5.0 o superior.

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0" // provider oficial de AWS
    }
  }
}

provider "aws" {
  region = var.region
}