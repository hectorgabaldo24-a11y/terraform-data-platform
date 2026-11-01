variable "name_prefix" {
  description = "Prefijo de nombres de los recursos, p. ej. data-platform-dev"
  type        = string
}

variable "bucket_name" {
  description = "Bucket S3 del data lake donde vive el warehouse de Iceberg (debe tener versionado habilitado)"
  type        = string
}

variable "warehouse_prefix" {
  description = "Prefijo S3 (sin barras al inicio ni al final) del warehouse de Iceberg"
  type        = string
  default     = "lakehouse"

  validation {
    condition     = length(var.warehouse_prefix) > 0 && !startswith(var.warehouse_prefix, "/") && !endswith(var.warehouse_prefix, "/")
    error_message = "warehouse_prefix no puede estar vacío ni empezar/terminar con '/'."
  }
}

variable "database_name" {
  description = "Nombre de la base de datos del Glue Data Catalog"
  type        = string
  default     = "lakehouse_db"
}

variable "table_name" {
  description = "Nombre de la tabla Iceberg con las métricas por ventana"
  type        = string
  default     = "ventanas_clientes"
}

variable "writer_role_name" {
  description = "Rol IAM que escribe en la tabla (rol de ejecución de Managed Flink)"
  type        = string
}

variable "tags" {
  description = "Etiquetas"
  type        = map(string)
  default     = {}
}
