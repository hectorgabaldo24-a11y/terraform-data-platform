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

# Poner en true solo al cambiar la topología del job (p. ej. al migrar el sink de JSON a
# Iceberg en la Pre-entrega 5): descarta el estado de operadores que ya no existen.
flink_allow_non_restored_state = false
