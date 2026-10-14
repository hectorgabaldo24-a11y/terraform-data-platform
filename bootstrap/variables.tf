variable "region" {
  description = "Región de AWS donde se crea el backend"
  type        = string
  default     = "us-east-1"
}

variable "state_bucket_name" {
  description = "Nombre (globalmente único) del bucket S3 del tfstate. Debe coincidir con el bucket de backend.tf en cada entorno"
  type        = string
}

variable "lock_table_name" {
  description = "Nombre de la tabla DynamoDB usada para el state locking"
  type        = string
  default     = "data-platform-tfstate-lock"
}
