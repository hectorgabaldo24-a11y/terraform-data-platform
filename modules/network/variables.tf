variable "name_prefix" {
  description = "Prefijo de nombres de los recursos, p. ej. data-platform-dev"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR de la VPC"
  type        = string

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr debe ser un bloque CIDR válido."
  }
}

variable "az_count" {
  description = "Cantidad de zonas de disponibilidad (una subred privada por AZ, mínimo 2)"
  type        = number
  default     = 2

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 6
    error_message = "az_count debe estar entre 2 y 6."
  }
}

variable "subnet_newbits" {
  description = "Bits adicionales sobre el prefijo de la VPC para calcular cada subred (/16 + 8 = /24)"
  type        = number
  default     = 8
}

variable "tags" {
  description = "Tags adicionales aplicados a los recursos del módulo"
  type        = map(string)
  default     = {}
}
