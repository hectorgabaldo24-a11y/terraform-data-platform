output "data_bucket_name" {
  description = "Nombre del bucket del data lake"
  value       = aws_s3_bucket.data_platform.id
}

output "vpc_id" {
  description = "ID de la VPC de datos"
  value       = module.network.vpc_id
}

output "private_subnet_ids" {
  description = "IDs de las subredes privadas"
  value       = module.network.private_subnet_ids
}

output "processing_role_arn" {
  description = "ARN del rol de ejecución para procesamiento (Lambda/Flink)"
  value       = module.identity.processing_role_arn
}

output "audit_role_arn" {
  description = "ARN del rol de auditoría de solo lectura"
  value       = module.identity.audit_role_arn
}

output "service_linked_role_arns" {
  description = "ARNs de los Service-Linked Roles creados, por servicio"
  value       = module.identity.service_linked_role_arns
}

output "kinesis_stream_name" {
  description = "Nombre del Kinesis Data Stream de ingesta"
  value       = module.kinesis.stream_name
}

output "flink_application_name" {
  description = "Nombre de la aplicación Managed Flink"
  value       = module.flink.application_name
}

output "flink_application_status" {
  description = "Estado de la aplicación Managed Flink"
  value       = module.flink.application_status
}

output "lakehouse_database" {
  description = "Base de datos del Glue Data Catalog"
  value       = module.lakehouse.database_name
}

output "lakehouse_table" {
  description = "Tabla Iceberg escrita por Flink"
  value       = module.lakehouse.table_name
}

output "lakehouse_table_location" {
  description = "Ubicación S3 de la tabla Iceberg (data/ y metadata/)"
  value       = module.lakehouse.table_location
}

output "athena_workgroup" {
  description = "Workgroup de Athena para consultar el lakehouse"
  value       = module.lakehouse.athena_workgroup
}

output "flink_log_group_name" {
  description = "Grupo de logs de CloudWatch de la aplicación Flink"
  value       = module.flink.log_group_name
}
