/*
Backend remoto: state en S3 (cifrado SSE) con locking en DynamoDB.
Los backends no admiten variables: los nombres deben coincidir con los
recursos creados en bootstrap/ (ver README, paso 1).
*/
terraform {
  backend "s3" {
    bucket         = "data-platform-tfstate-hector-659500704179"
    key            = "data-platform/dev/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "data-platform-tfstate-lock"
  }
}
