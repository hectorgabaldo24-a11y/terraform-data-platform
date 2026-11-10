variable "name_prefix" {
  description = "Prefijo de nombres de los recursos, p. ej. data-platform-dev"
  type        = string
}

# ---------------------------------------------------------------------------
# Red
# ---------------------------------------------------------------------------
variable "vpc_id" {
  description = "VPC donde se crean las ENIs del workgroup (módulo network)"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR de la VPC: único origen permitido hacia el puerto 5439"
  type        = string
}

variable "subnet_ids" {
  description = "Subredes privadas del workgroup (Redshift Serverless exige al menos 3, en AZs distintas)"
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 3
    error_message = "Redshift Serverless necesita al menos 3 subredes en 3 zonas de disponibilidad distintas."
  }
}

# ---------------------------------------------------------------------------
# Redshift Serverless
# ---------------------------------------------------------------------------
variable "database_name" {
  description = "Base de datos inicial del namespace"
  type        = string
  default     = "analytics"
}

variable "admin_username" {
  description = "Usuario administrador (su contraseña la genera y rota Redshift en Secrets Manager)"
  type        = string
  default     = "rsadmin"
}

variable "base_capacity" {
  description = "RPUs base del workgroup (8 es el mínimo con todas las funcionalidades; se cobra solo mientras hay consultas)"
  type        = number
  default     = 8

  validation {
    condition     = var.base_capacity >= 8 && var.base_capacity % 8 == 0
    error_message = "base_capacity debe ser múltiplo de 8 y al menos 8."
  }
}

variable "max_rpu_hours_per_day" {
  description = "Tope diario de RPU-horas; al superarlo el workgroup deja de aceptar consultas hasta el día siguiente (control de costos)"
  type        = number
  default     = 16
}

# ---------------------------------------------------------------------------
# Orígenes de datos
# ---------------------------------------------------------------------------
variable "kinesis_stream_arn" {
  description = "ARN del Kinesis Data Stream que Redshift ingiere con Streaming Ingestion"
  type        = string
}

variable "kinesis_stream_name" {
  description = "Nombre del stream (sólo para el dashboard de CloudWatch)"
  type        = string
}

variable "glue_database_name" {
  description = "Base del Glue Data Catalog con las tablas Iceberg (módulo lakehouse)"
  type        = string
}

variable "lakehouse_bucket_name" {
  description = "Bucket del data lake donde vive el warehouse de Iceberg"
  type        = string
}

variable "lakehouse_prefix" {
  description = "Prefijo S3 del warehouse de Iceberg (sin barras al inicio ni al final)"
  type        = string
}

# ---------------------------------------------------------------------------
# Refresco y acceso
# ---------------------------------------------------------------------------
variable "refresh_schedule_enabled" {
  description = "true activa el refresco programado de la vista materializada del stream (mantiene el workgroup activo: costo por RPU)"
  type        = bool
  default     = false
}

variable "refresh_schedule_expression" {
  description = "Cadencia del refresco (EventBridge Scheduler). 1 minuto equilibra latencia y carga del workgroup"
  type        = string
  default     = "rate(1 minute)"
}

variable "refresh_sql" {
  description = "Sentencia que ejecuta el scheduler en cada disparo"
  type        = string
  default     = "CALL ops.sp_refrescar_stream()"
}

variable "analytics_db_role" {
  description = "Rol de base de datos (RBAC de Redshift) que se otorga al rol IAM de analistas"
  type        = string
  default     = "analytics_role"
}

variable "analyst_trusted_principal_arns" {
  description = "Principals que pueden asumir el rol IAM de analistas. Vacío = cualquier identidad IAM de la cuenta con permiso sts:AssumeRole"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Etiquetas"
  type        = map(string)
  default     = {}
}
