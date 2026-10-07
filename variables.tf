/* 
en el ejercicio me piden 3 variables 
region	string	us-east-1
project_name	string	data-platform
environment	string	dev
*/

variable "region" {
  description = "Región de AWS donde se desplegará la infraestructura"
  type        = string
}

variable "project_name" {
  description = "Nombre del proyecto"
  type        = string
}

variable "environment" {
  description = "Ambiente de despliegue"
  type        = string
}