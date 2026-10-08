variable "name_prefix" {
  description = "Prefijo de nombres de los recursos, p. ej. data-platform-dev"
  type        = string
}

variable "data_bucket_arn" {
  description = "ARN del bucket S3 del data lake al que accede el rol de procesamiento"
  type        = string
}

variable "data_prefix" {
  description = "Prefijo (sin barra inicial ni final) del bucket al que se limita el rol de procesamiento"
  type        = string

  validation {
    condition     = length(var.data_prefix) > 0 && !startswith(var.data_prefix, "/") && !endswith(var.data_prefix, "/") && !strcontains(var.data_prefix, "*")
    error_message = "data_prefix no puede estar vacío, ni empezar/terminar con '/', ni contener '*'."
  }
}

variable "kinesis_stream_arns" {
  description = "ARNs de streams de Kinesis que el rol de procesamiento puede leer (vacío hasta el módulo de streaming)"
  type        = list(string)
  default     = []
}

variable "audit_trusted_principal_arns" {
  description = "ARNs de principals autorizados a asumir el rol de auditoría. Si es vacío se confía en el root de la cuenta"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags adicionales aplicados a los recursos del módulo"
  type        = map(string)
  default     = {}
}
