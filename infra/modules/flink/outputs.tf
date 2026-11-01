output "application_name" {
  description = "Nombre de la aplicación Managed Flink"
  value       = aws_kinesisanalyticsv2_application.flink.name
}

output "application_arn" {
  description = "ARN de la aplicación Managed Flink"
  value       = aws_kinesisanalyticsv2_application.flink.arn
}

output "application_version_id" {
  description = "Versión actual de la aplicación"
  value       = aws_kinesisanalyticsv2_application.flink.version_id
}

output "application_status" {
  description = "Estado de la aplicación (READY, RUNNING, ...)"
  value       = aws_kinesisanalyticsv2_application.flink.status
}

output "application_code_s3_key" {
  description = "Ubicación del ZIP de la aplicación en S3"
  value       = aws_s3_object.flink_application.key
}

output "log_group_name" {
  description = "Grupo de logs de CloudWatch de la aplicación"
  value       = aws_cloudwatch_log_group.flink.name
}
