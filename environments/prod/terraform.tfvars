region       = "us-east-1"
project_name = "data-platform"
environment  = "prod"
vpc_cidr     = "10.1.0.0/16"
az_count     = 3
data_prefix  = "streaming"

# Lake Formation permite un único Service-Linked Role por cuenta y ya lo crea dev
service_linked_role_services = []
