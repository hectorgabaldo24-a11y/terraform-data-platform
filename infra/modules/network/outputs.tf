output "vpc_id" {
  description = "ID de la VPC"
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "CIDR de la VPC"
  value       = aws_vpc.this.cidr_block
}

output "private_subnet_ids" {
  description = "IDs de las subredes privadas (una por AZ)"
  value       = [for s in aws_subnet.private : s.id]
}

output "private_route_table_ids" {
  description = "IDs de las tablas de rutas privadas"
  value       = [for rt in aws_route_table.private : rt.id]
}

output "s3_endpoint_id" {
  description = "ID del S3 Gateway Endpoint"
  value       = aws_vpc_endpoint.s3.id
}
