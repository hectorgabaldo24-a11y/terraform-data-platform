output "state_bucket" {
  description = "Bucket S3 del backend"
  value       = aws_s3_bucket.state.id
}

output "lock_table" {
  description = "Tabla DynamoDB de locking"
  value       = aws_dynamodb_table.lock.name
}
