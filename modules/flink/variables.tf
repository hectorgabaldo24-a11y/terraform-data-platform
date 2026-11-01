variable "project_name" {
  description = "Nombre del proyecto"
  type        = string
}

variable "environment" {
  description = "Entorno"
  type        = string
}

variable "aws_region" {
  description = "Región del stream de Kinesis (la usa el conector de la aplicación)"
  type        = string
}

variable "stream_name" {
  description = "Nombre del Kinesis Data Stream de entrada"
  type        = string
}

variable "stream_initial_position" {
  description = "Desde dónde empieza a leer la aplicación la primera vez: LATEST o TRIM_HORIZON"
  type        = string
  default     = "LATEST"

  validation {
    condition     = contains(["LATEST", "TRIM_HORIZON"], var.stream_initial_position)
    error_message = "stream_initial_position debe ser LATEST o TRIM_HORIZON."
  }
}

variable "execution_role_arn" {
  description = "ARN del rol de ejecución reutilizado desde el módulo identity"
  type        = string
}

variable "execution_role_name" {
  description = "Nombre del rol IAM de ejecución de Managed Flink"
  type        = string
}

variable "artifact_bucket" {
  description = "Bucket donde se guardan el ZIP de la aplicación y los resultados"
  type        = string
}

variable "artifact_local_path" {
  description = "Ruta local del ZIP generado por flink-app/build.ps1"
  type        = string
}

variable "output_prefix" {
  description = "Prefijo S3 (sin barras al inicio ni al final) donde la aplicación escribe los agregados"
  type        = string
  default     = "flink/resultados"
}

variable "parallelism" {
  description = "Paralelismo inicial del job. Con parallelism_per_kpu = 1 equivale a la cantidad de KPUs de procesamiento"
  type        = number
  default     = 2

  validation {
    condition     = var.parallelism >= 1
    error_message = "parallelism debe ser al menos 1."
  }
}

variable "parallelism_per_kpu" {
  description = "Tareas paralelas por KPU (1 KPU = 1 vCPU y 4 GB de memoria)"
  type        = number
  default     = 1
}

variable "autoscaling_enabled" {
  description = "Permite que el servicio aumente el paralelismo según la carga"
  type        = bool
  default     = false
}

variable "checkpoint_interval_ms" {
  description = "Intervalo entre checkpoints en milisegundos"
  type        = number
  default     = 60000
}

variable "min_pause_between_checkpoints_ms" {
  description = "Pausa mínima entre el fin de un checkpoint y el inicio del siguiente"
  type        = number
  default     = 5000
}

variable "watermark_delay_seconds" {
  description = "Retraso tolerado por el watermark (eventos fuera de orden)"
  type        = number
  default     = 30
}

variable "start_application" {
  description = "Si es true, Terraform deja la aplicación en ejecución (genera costo por KPU-hora)"
  type        = bool
  default     = false
}

variable "log_retention_days" {
  description = "Días de retención de los logs de la aplicación"
  type        = number
  default     = 7
}

variable "private_subnet_ids" {
  description = "Subredes privadas para ejecutar Flink dentro de la VPC. Vacío = fuera de la VPC (acceso a endpoints públicos de AWS)"
  type        = list(string)
  default     = []
}

variable "security_group_ids" {
  description = "Security Groups para la conexión a la VPC (solo si private_subnet_ids no está vacío)"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Etiquetas"
  type        = map(string)
  default     = {}
}
