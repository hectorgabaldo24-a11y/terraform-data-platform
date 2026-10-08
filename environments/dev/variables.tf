variable "region" {
  description = "Región de AWS donde se desplegará la infraestructura"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Nombre del proyecto"
  type        = string
}

variable "environment" {
  description = "Ambiente de despliegue"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment debe ser dev, staging o prod."
  }
}

variable "vpc_cidr" {
  description = "CIDR de la VPC de datos"
  type        = string
}

variable "az_count" {
  description = "Cantidad de zonas de disponibilidad / subredes privadas"
  type        = number
  default     = 2
}

variable "data_prefix" {
  description = "Prefijo del bucket del data lake al que puede acceder el rol de procesamiento"
  type        = string
  default     = "streaming"
}
