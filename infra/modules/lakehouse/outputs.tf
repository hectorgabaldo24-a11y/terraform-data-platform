output "database_name" {
  description = "Base de datos del Glue Data Catalog"
  value       = aws_glue_catalog_database.lakehouse_db.name
}

output "table_name" {
  description = "Tabla Iceberg de métricas por ventana"
  value       = aws_glue_catalog_table.ventanas_clientes.name
}

output "warehouse_path" {
  description = "Ruta S3 del warehouse de Iceberg (propiedad 'warehouse' del catálogo)"
  value       = local.warehouse_path
}

output "table_location" {
  description = "Ubicación S3 de la tabla (contiene data/ y metadata/)"
  value       = local.table_location
}

output "athena_workgroup" {
  description = "Workgroup de Athena para consultar el lakehouse"
  value       = aws_athena_workgroup.lakehouse.name
}

output "writer_policy_arn" {
  description = "Política IAM adjunta al rol escritor"
  value       = aws_iam_policy.lakehouse_writer.arn
}
