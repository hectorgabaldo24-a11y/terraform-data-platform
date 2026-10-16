
locals {
  stream_name = "${var.project_name}-${var.environment}-events"
  firehose_name = "${var.project_name}-${var.environment}-bronze"

  common_tags = merge(var.tags, {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  })
}

# 1. Kinesis Data Stream
resource "aws_kinesis_stream" "events" {
  name             = local.stream_name
  retention_period = 24
  shard_count      = var.shard_count
  stream_mode_details {
    stream_mode = "PROVISIONED"
  }

  encryption_type = "KMS"
  kms_key_id      = "alias/aws/kinesis"

  tags = local.common_tags
}

# 2. Rol IAM que asumirá Firehose
resource "aws_iam_role" "firehose" {
  name = "${local.firehose_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "firehose.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = local.common_tags
}

# 3. Permisos de lectura de Kinesis y escritura en S3

# 3. Permisos mínimos de Firehose para Kinesis, S3, CloudWatch y KMS
resource "aws_iam_role_policy" "firehose" {
  name = "${local.firehose_name}-policy"
  role = aws_iam_role.firehose.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Sid    = "ReadKinesisStream"
        Effect = "Allow"

        Action = [
          "kinesis:DescribeStream",
          "kinesis:DescribeStreamSummary",
          "kinesis:GetRecords",
          "kinesis:GetShardIterator",
          "kinesis:ListShards"
        ]

        Resource = aws_kinesis_stream.events.arn
      },
      {
        Sid    = "WriteToS3"
        Effect = "Allow"

        Action = [
          "s3:AbortMultipartUpload",
          "s3:GetBucketLocation",
          "s3:GetObject",
          "s3:ListBucket",
          "s3:ListBucketMultipartUploads",
          "s3:PutObject"
        ]

        Resource = [
          "arn:aws:s3:::${var.s3_bucket_name}",
          "arn:aws:s3:::${var.s3_bucket_name}/*"
        ]
      },
      {
        Sid    = "WriteFirehoseLogs"
        Effect = "Allow"

        Action = [
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]

        Resource = aws_cloudwatch_log_stream.firehose.arn
      },
      {
        Sid    = "DecryptKinesisRecords"
        Effect = "Allow"

        Action = [
          "kms:Decrypt",
          "kms:DescribeKey"
        ]

        Resource = "arn:aws:kms:us-east-1:659500704179:key/0b65c0fc-23e4-4786-b969-68eff02df69c"
      }
    ]
  })
}

# 4. Grupo y stream de logs para Firehose
resource "aws_cloudwatch_log_group" "firehose" {
  name              = "/aws/kinesisfirehose/${local.firehose_name}"
  retention_in_days = 7
  tags              = local.common_tags
}

resource "aws_cloudwatch_log_stream" "firehose" {
  name           = "S3Delivery"
  log_group_name = aws_cloudwatch_log_group.firehose.name
}

# 5. Firehose consume Kinesis y entrega los datos a S3
resource "aws_kinesis_firehose_delivery_stream" "bronze" {
  name        = local.firehose_name
  destination = "extended_s3"

  kinesis_source_configuration {
    kinesis_stream_arn = aws_kinesis_stream.events.arn
    role_arn           = aws_iam_role.firehose.arn
  }

  extended_s3_configuration {
    role_arn   = aws_iam_role.firehose.arn
    bucket_arn = "arn:aws:s3:::${var.s3_bucket_name}"

    prefix = "ingesta/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/"
    error_output_prefix = "errores/!{firehose:error-output-type}/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/"

    buffering_size     = 5
    buffering_interval = 60

    compression_format = "GZIP"

    cloudwatch_logging_options {
      enabled         = true
      log_group_name  = aws_cloudwatch_log_group.firehose.name
      log_stream_name = aws_cloudwatch_log_stream.firehose.name
    }
  }

  depends_on = [aws_iam_role_policy.firehose]
  tags       = local.common_tags
}

# 6. Alarma de exceso de escritura en Kinesis
resource "aws_cloudwatch_metric_alarm" "write_throttle" {
  alarm_name          = "${local.stream_name}-write-throttle"
  alarm_description   = "Kinesis supera su capacidad de escritura"
  namespace           = "AWS/Kinesis"
  metric_name         = "WriteProvisionedThroughputExceeded"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"

  dimensions = {
    StreamName = aws_kinesis_stream.events.name
  }

  treat_missing_data = "notBreaching"
  tags               = local.common_tags
}

# 7. Alarma de exceso de lectura en Kinesis
resource "aws_cloudwatch_metric_alarm" "read_throttle" {
  alarm_name          = "${local.stream_name}-read-throttle"
  alarm_description   = "Kinesis supera su capacidad de lectura"
  namespace           = "AWS/Kinesis"
  metric_name         = "ReadProvisionedThroughputExceeded"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"

  dimensions = {
    StreamName = aws_kinesis_stream.events.name
  }

  treat_missing_data = "notBreaching"
  tags               = local.common_tags
}
