
output "stream_name" {
  description = "Nombre del Kinesis Data Stream"
  value       = aws_kinesis_stream.events.name
}

output "stream_arn" {
  description = "ARN del Kinesis Data Stream"
  value       = aws_kinesis_stream.events.arn
}

output "firehose_name" {
  description = "Nombre del delivery stream"
  value       = aws_kinesis_firehose_delivery_stream.bronze.name
}

output "firehose_arn" {
  description = "ARN del delivery stream"
  value       = aws_kinesis_firehose_delivery_stream.bronze.arn
}
