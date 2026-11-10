output "namespace_name" {
  description = "Namespace de Redshift Serverless"
  value       = aws_redshiftserverless_namespace.this.namespace_name
}

output "workgroup_name" {
  description = "Workgroup de Redshift Serverless (parámetro --workgroup-name de la Data API)"
  value       = aws_redshiftserverless_workgroup.this.workgroup_name
}

output "workgroup_arn" {
  description = "ARN del workgroup"
  value       = aws_redshiftserverless_workgroup.this.arn
}

output "endpoint" {
  description = "Endpoint JDBC/ODBC (sólo alcanzable desde la VPC)"
  value       = "${aws_redshiftserverless_workgroup.this.endpoint[0].address}:${aws_redshiftserverless_workgroup.this.endpoint[0].port}"
}

output "database_name" {
  description = "Base de datos del namespace"
  value       = var.database_name
}

output "admin_secret_arn" {
  description = "Secreto de Secrets Manager con la contraseña del administrador (administrado por Redshift)"
  value       = aws_redshiftserverless_namespace.this.admin_password_secret_arn
}

output "service_role_arn" {
  description = "Rol IAM que asume Redshift para Kinesis y el lakehouse (IAM_ROLE default)"
  value       = aws_iam_role.redshift_service.arn
}

output "analyst_role_arn" {
  description = "Rol IAM de analistas (credenciales temporales, rol de base de datos analytics_role)"
  value       = aws_iam_role.analyst.arn
}

output "refresh_role_name" {
  description = "Rol IAM del refresco programado; en Redshift es el usuario IAMR:<nombre>"
  value       = aws_iam_role.refresh.name
}

output "dashboard_name" {
  description = "Dashboard de CloudWatch de la capa streaming-analítica"
  value       = aws_cloudwatch_dashboard.streaming_analytics.dashboard_name
}
