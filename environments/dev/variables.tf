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

variable "service_linked_role_services" {
  description = "Servicios AWS para los que se crea un Service-Linked Role (plano de control)"
  type        = set(string)
  default     = []
}

variable "flink_parallelism" {
  description = "Paralelismo de la aplicación Managed Flink (con 1 tarea por KPU equivale a las KPUs de procesamiento)"
  type        = number
  default     = 2
}

variable "flink_watermark_delay_seconds" {
  description = "Tolerancia del watermark a eventos fuera de orden, en segundos"
  type        = number
  default     = 30
}

variable "flink_start_application" {
  description = "true deja la aplicación Flink en ejecución tras el apply (costo por KPU-hora); false la deja en READY"
  type        = bool
  default     = false
}
