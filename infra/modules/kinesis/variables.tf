
variable "project_name" {
  description = "Nombre del proyecto"
  type        = string
  default     = "data-platform"
}

variable "environment" {
  description = "Entorno de despliegue"
  type        = string
}

variable "s3_bucket_name" {
  description = "Bucket S3 existente del Data Lake"
  type        = string
}

variable "shard_count" {
  description = "Cantidad de shards provisionados"
  type        = number
  default     = 2

  validation {
    condition     = var.shard_count >= 2
    error_message = "El checkpoint requiere al menos 2 shards."
  }
}

variable "tags" {
  description = "Etiquetas comunes"
  type        = map(string)
  default     = {}
}
