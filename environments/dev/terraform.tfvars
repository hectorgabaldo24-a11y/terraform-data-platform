region       = "us-east-1"
project_name = "data-platform"
environment  = "dev"
vpc_cidr     = "10.0.0.0/16"
az_count     = 2
data_prefix  = "streaming"
# Service-Linked Role del plano de control para el Lakehouse (Lake Formation)
service_linked_role_services = ["lakeformation.amazonaws.com"]

# Managed Flink (Pre-entrega 4)
flink_parallelism             = 2
flink_watermark_delay_seconds = 30
flink_start_application       = false
