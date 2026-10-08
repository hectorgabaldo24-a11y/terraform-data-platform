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
