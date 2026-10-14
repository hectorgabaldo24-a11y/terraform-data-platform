output "processing_role_arn" {
  description = "ARN del rol de ejecución para procesamiento (Lambda/Flink)"
  value       = aws_iam_role.processing.arn
}

output "processing_role_name" {
  description = "Nombre del rol de ejecución para procesamiento"
  value       = aws_iam_role.processing.name
}

output "audit_role_arn" {
  description = "ARN del rol de auditoría de solo lectura"
  value       = aws_iam_role.audit.arn
}

output "service_linked_role_arns" {
  description = "ARNs de los Service-Linked Roles creados, por servicio"
  value       = { for service, role in aws_iam_service_linked_role.this : service => role.arn }
}
