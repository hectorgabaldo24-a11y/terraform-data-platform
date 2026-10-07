resource "aws_s3_bucket" "data_platform" {
  bucket = "${var.project_name}-${var.environment}-bucket"
}