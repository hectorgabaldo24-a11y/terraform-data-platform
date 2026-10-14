# Plan output — environments/prod (demostración de reuso)

`terraform plan` de `environments/prod`, que reutiliza **sin modificarlos** los módulos `network` e `identity`. Solo cambian la `key` del backend y `terraform.tfvars`.

**Resultado: `Plan: 22 to add, 0 to change, 0 to destroy.` — sin errores.**

## Procedencia (cómo verificar que corresponde al código actual)

| Dato | Valor |
|------|-------|
| Fecha de ejecución | 2026-10-13 22:24 -0300 |
| Comando | `cd environments/prod && terraform plan -no-color` |
| Commit base | `a266a0b` (árbol de trabajo limpio) |
| Terraform | Terraform v1.16.5 |
| Cuenta AWS | `659500704179` (`us-east-1`) |
| `apply` | **No ejecutado.** Es un `plan`: no se creó ningún recurso |

Hashes del código planificado (no cambian con commits que solo tocan documentación):

```text
modules            0bd0b7adc45b
environments/prod     6d4aa36510d6
bootstrap          d1997fc2dea6
```

Verificación: `git rev-parse HEAD:modules HEAD:environments/prod HEAD:bootstrap` debe devolver estos hashes (en los primeros 12 caracteres). Si difieren, el código cambió después de este plan y hay que volver a ejecutarlo.

## Salida completa

```text

Warning: Deprecated Parameter

The parameter "dynamodb_table" is deprecated. Use parameter "use_lockfile"
instead.
Acquiring state lock. This may take a few moments...
module.network.data.aws_availability_zones.available: Reading...
module.identity.data.aws_caller_identity.current: Reading...
module.network.data.aws_region.current: Reading...
module.network.data.aws_region.current: Read complete after 0s [id=us-east-1]
module.identity.data.aws_caller_identity.current: Read complete after 1s [id=659500704179]
module.identity.data.aws_iam_policy_document.audit_assume: Reading...
module.identity.data.aws_iam_policy_document.processing_assume: Reading...
module.identity.data.aws_iam_policy_document.audit_assume: Read complete after 0s [id=2797766587]
module.identity.data.aws_iam_policy_document.processing_assume: Read complete after 0s [id=1449445080]
module.network.data.aws_availability_zones.available: Read complete after 1s [id=us-east-1]

Terraform used the selected providers to generate the following execution
plan. Resource actions are indicated with the following symbols:
  + create
 <= read (data resources)

Terraform will perform the following actions:

  # data.aws_iam_policy_document.data_platform_tls will be read during apply
  # (config refers to values not yet known)
 <= data "aws_iam_policy_document" "data_platform_tls" {
      + id            = (known after apply)
      + json          = (known after apply)
      + minified_json = (known after apply)

      + statement {
          + actions   = [
              + "s3:*",
            ]
          + effect    = "Deny"
          + resources = [
              + (known after apply),
              + (known after apply),
            ]
          + sid       = "DenyInsecureTransport"

          + condition {
              + test     = "Bool"
              + values   = [
                  + "false",
                ]
              + variable = "aws:SecureTransport"
            }

          + principals {
              + identifiers = [
                  + "*",
                ]
              + type        = "*"
            }
        }
    }

  # aws_s3_bucket.data_platform will be created
  + resource "aws_s3_bucket" "data_platform" {
      + acceleration_status         = (known after apply)
      + acl                         = (known after apply)
      + arn                         = (known after apply)
      + bucket                      = "data-platform-prod-bucket"
      + bucket_domain_name          = (known after apply)
      + bucket_namespace            = (known after apply)
      + bucket_prefix               = (known after apply)
      + bucket_region               = (known after apply)
      + bucket_regional_domain_name = (known after apply)
      + force_destroy               = false
      + hosted_zone_id              = (known after apply)
      + id                          = (known after apply)
      + object_lock_enabled         = (known after apply)
      + policy                      = (known after apply)
      + region                      = "us-east-1"
      + request_payer               = (known after apply)
      + tags_all                    = {
          + "Environment" = "prod"
          + "ManagedBy"   = "terraform"
          + "Project"     = "data-platform"
        }
      + website_domain              = (known after apply)
      + website_endpoint            = (known after apply)

      + cors_rule (known after apply)

      + grant (known after apply)

      + lifecycle_rule (known after apply)

      + logging (known after apply)

      + object_lock_configuration (known after apply)

      + replication_configuration (known after apply)

      + server_side_encryption_configuration (known after apply)

      + versioning (known after apply)

      + website (known after apply)
    }

  # aws_s3_bucket_policy.data_platform_tls will be created
  + resource "aws_s3_bucket_policy" "data_platform_tls" {
      + bucket = (known after apply)
      + id     = (known after apply)
      + policy = (known after apply)
      + region = "us-east-1"
    }

  # aws_s3_bucket_public_access_block.data_platform will be created
  + resource "aws_s3_bucket_public_access_block" "data_platform" {
      + block_public_acls       = true
      + block_public_policy     = true
      + bucket                  = (known after apply)
      + id                      = (known after apply)
      + ignore_public_acls      = true
      + region                  = "us-east-1"
      + restrict_public_buckets = true
    }

  # aws_s3_bucket_server_side_encryption_configuration.data_platform will be created
  + resource "aws_s3_bucket_server_side_encryption_configuration" "data_platform" {
      + bucket = (known after apply)
      + id     = (known after apply)
      + region = "us-east-1"

      + rule {
          + blocked_encryption_types = (known after apply)
          + bucket_key_enabled       = (known after apply)

          + apply_server_side_encryption_by_default {
              + kms_master_key_id = (known after apply)
              + sse_algorithm     = "AES256"
            }
        }
    }

  # aws_s3_bucket_versioning.data_platform will be created
  + resource "aws_s3_bucket_versioning" "data_platform" {
      + bucket = (known after apply)
      + id     = (known after apply)
      + region = "us-east-1"

      + versioning_configuration {
          + mfa_delete = (known after apply)
          + status     = "Enabled"
        }
    }

  # module.identity.data.aws_iam_policy_document.processing_s3 will be read during apply
  # (config refers to values not yet known)
 <= data "aws_iam_policy_document" "processing_s3" {
      + id            = (known after apply)
      + json          = (known after apply)
      + minified_json = (known after apply)

      + statement {
          + actions   = [
              + "s3:ListBucket",
            ]
          + effect    = "Allow"
          + resources = [
              + (known after apply),
            ]
          + sid       = "ListBucketPrefixOnly"

          + condition {
              + test     = "StringLike"
              + values   = [
                  + "streaming",
                  + "streaming/*",
                ]
              + variable = "s3:prefix"
            }
        }
      + statement {
          + actions   = [
              + "s3:GetObject",
              + "s3:PutObject",
            ]
          + effect    = "Allow"
          + resources = [
              + (known after apply),
            ]
          + sid       = "ReadWriteObjectsInPrefix"
        }
    }

  # module.identity.aws_iam_policy.processing_s3 will be created
  + resource "aws_iam_policy" "processing_s3" {
      + arn              = (known after apply)
      + attachment_count = (known after apply)
      + description      = "s3:ListBucket, GetObject y PutObject restringidos a un prefijo"
      + id               = (known after apply)
      + name             = "data-platform-prod-processing-s3"
      + name_prefix      = (known after apply)
      + path             = "/"
      + policy           = (known after apply)
      + policy_id        = (known after apply)
      + tags_all         = {
          + "Environment" = "prod"
          + "ManagedBy"   = "terraform"
          + "Project"     = "data-platform"
        }
    }

  # module.identity.aws_iam_role.audit will be created
  + resource "aws_iam_role" "audit" {
      + arn                   = (known after apply)
      + assume_role_policy    = jsonencode(
            {
              + Statement = [
                  + {
                      + Action    = "sts:AssumeRole"
                      + Condition = {
                          + Bool = {
                              + "aws:MultiFactorAuthPresent" = "true"
                            }
                        }
                      + Effect    = "Allow"
                      + Principal = {
                          + AWS = "arn:aws:iam::659500704179:root"
                        }
                      + Sid       = "AuditorsAssumeRoleWithMFA"
                    },
                ]
              + Version   = "2012-10-17"
            }
        )
      + create_date           = (known after apply)
      + description           = "Rol de plano de control con permisos de solo lectura para auditoria"
      + force_detach_policies = false
      + id                    = (known after apply)
      + managed_policy_arns   = (known after apply)
      + max_session_duration  = 3600
      + name                  = "data-platform-prod-audit-readonly-role"
      + name_prefix           = (known after apply)
      + path                  = "/"
      + tags_all              = {
          + "Environment" = "prod"
          + "ManagedBy"   = "terraform"
          + "Project"     = "data-platform"
        }
      + unique_id             = (known after apply)

      + inline_policy (known after apply)
    }

  # module.identity.aws_iam_role.processing will be created
  + resource "aws_iam_role" "processing" {
      + arn                   = (known after apply)
      + assume_role_policy    = jsonencode(
            {
              + Statement = [
                  + {
                      + Action    = "sts:AssumeRole"
                      + Condition = {
                          + StringEquals = {
                              + "aws:SourceAccount" = "659500704179"
                            }
                        }
                      + Effect    = "Allow"
                      + Principal = {
                          + Service = [
                              + "lambda.amazonaws.com",
                              + "kinesisanalytics.amazonaws.com",
                            ]
                        }
                      + Sid       = "ProcessingServicesAssumeRole"
                    },
                ]
              + Version   = "2012-10-17"
            }
        )
      + create_date           = (known after apply)
      + description           = "Rol de ejecucion para Lambda/Flink con acceso acotado al data lake"
      + force_detach_policies = false
      + id                    = (known after apply)
      + managed_policy_arns   = (known after apply)
      + max_session_duration  = 3600
      + name                  = "data-platform-prod-processing-role"
      + name_prefix           = (known after apply)
      + path                  = "/"
      + tags_all              = {
          + "Environment" = "prod"
          + "ManagedBy"   = "terraform"
          + "Project"     = "data-platform"
        }
      + unique_id             = (known after apply)

      + inline_policy (known after apply)
    }

  # module.identity.aws_iam_role_policy_attachment.audit_readonly will be created
  + resource "aws_iam_role_policy_attachment" "audit_readonly" {
      + id         = (known after apply)
      + policy_arn = "arn:aws:iam::aws:policy/SecurityAudit"
      + role       = "data-platform-prod-audit-readonly-role"
    }

  # module.identity.aws_iam_role_policy_attachment.processing_s3 will be created
  + resource "aws_iam_role_policy_attachment" "processing_s3" {
      + id         = (known after apply)
      + policy_arn = (known after apply)
      + role       = "data-platform-prod-processing-role"
    }

  # module.network.data.aws_iam_policy_document.s3_endpoint[0] will be read during apply
  # (config refers to values not yet known)
 <= data "aws_iam_policy_document" "s3_endpoint" {
      + id            = (known after apply)
      + json          = (known after apply)
      + minified_json = (known after apply)

      + statement {
          + actions   = [
              + "s3:AbortMultipartUpload",
              + "s3:GetObject",
              + "s3:ListBucket",
              + "s3:ListBucketMultipartUploads",
              + "s3:PutObject",
            ]
          + effect    = "Allow"
          + resources = [
              + (known after apply),
              + (known after apply),
            ]
          + sid       = "AllowDataBucketsOnly"

          + principals {
              + identifiers = [
                  + "*",
                ]
              + type        = "AWS"
            }
        }
    }

  # module.network.aws_default_security_group.this will be created
  + resource "aws_default_security_group" "this" {
      + arn                    = (known after apply)
      + description            = (known after apply)
      + egress                 = (known after apply)
      + id                     = (known after apply)
      + ingress                = (known after apply)
      + name                   = (known after apply)
      + name_prefix            = (known after apply)
      + owner_id               = (known after apply)
      + region                 = "us-east-1"
      + revoke_rules_on_delete = false
      + tags                   = {
          + "Name" = "data-platform-prod-default-sg-locked"
        }
      + tags_all               = {
          + "Environment" = "prod"
          + "ManagedBy"   = "terraform"
          + "Name"        = "data-platform-prod-default-sg-locked"
          + "Project"     = "data-platform"
        }
      + vpc_id                 = (known after apply)
    }

  # module.network.aws_route_table.private["us-east-1a"] will be created
  + resource "aws_route_table" "private" {
      + arn              = (known after apply)
      + id               = (known after apply)
      + owner_id         = (known after apply)
      + propagating_vgws = (known after apply)
      + region           = "us-east-1"
      + route            = (known after apply)
      + tags             = {
          + "Name" = "data-platform-prod-private-rt-us-east-1a"
        }
      + tags_all         = {
          + "Environment" = "prod"
          + "ManagedBy"   = "terraform"
          + "Name"        = "data-platform-prod-private-rt-us-east-1a"
          + "Project"     = "data-platform"
        }
      + vpc_id           = (known after apply)
    }

  # module.network.aws_route_table.private["us-east-1b"] will be created
  + resource "aws_route_table" "private" {
      + arn              = (known after apply)
      + id               = (known after apply)
      + owner_id         = (known after apply)
      + propagating_vgws = (known after apply)
      + region           = "us-east-1"
      + route            = (known after apply)
      + tags             = {
          + "Name" = "data-platform-prod-private-rt-us-east-1b"
        }
      + tags_all         = {
          + "Environment" = "prod"
          + "ManagedBy"   = "terraform"
          + "Name"        = "data-platform-prod-private-rt-us-east-1b"
          + "Project"     = "data-platform"
        }
      + vpc_id           = (known after apply)
    }

  # module.network.aws_route_table.private["us-east-1c"] will be created
  + resource "aws_route_table" "private" {
      + arn              = (known after apply)
      + id               = (known after apply)
      + owner_id         = (known after apply)
      + propagating_vgws = (known after apply)
      + region           = "us-east-1"
      + route            = (known after apply)
      + tags             = {
          + "Name" = "data-platform-prod-private-rt-us-east-1c"
        }
      + tags_all         = {
          + "Environment" = "prod"
          + "ManagedBy"   = "terraform"
          + "Name"        = "data-platform-prod-private-rt-us-east-1c"
          + "Project"     = "data-platform"
        }
      + vpc_id           = (known after apply)
    }

  # module.network.aws_route_table_association.private["us-east-1a"] will be created
  + resource "aws_route_table_association" "private" {
      + id             = (known after apply)
      + region         = "us-east-1"
      + route_table_id = (known after apply)
      + subnet_id      = (known after apply)
    }

  # module.network.aws_route_table_association.private["us-east-1b"] will be created
  + resource "aws_route_table_association" "private" {
      + id             = (known after apply)
      + region         = "us-east-1"
      + route_table_id = (known after apply)
      + subnet_id      = (known after apply)
    }

  # module.network.aws_route_table_association.private["us-east-1c"] will be created
  + resource "aws_route_table_association" "private" {
      + id             = (known after apply)
      + region         = "us-east-1"
      + route_table_id = (known after apply)
      + subnet_id      = (known after apply)
    }

  # module.network.aws_subnet.private["us-east-1a"] will be created
  + resource "aws_subnet" "private" {
      + arn                                            = (known after apply)
      + assign_ipv6_address_on_creation                = false
      + availability_zone                              = "us-east-1a"
      + availability_zone_id                           = (known after apply)
      + cidr_block                                     = "10.1.0.0/24"
      + enable_dns64                                   = false
      + enable_resource_name_dns_a_record_on_launch    = false
      + enable_resource_name_dns_aaaa_record_on_launch = false
      + id                                             = (known after apply)
      + ipv6_cidr_block                                = (known after apply)
      + ipv6_cidr_block_association_id                 = (known after apply)
      + ipv6_native                                    = false
      + map_public_ip_on_launch                        = false
      + owner_id                                       = (known after apply)
      + private_dns_hostname_type_on_launch            = (known after apply)
      + region                                         = "us-east-1"
      + tags                                           = {
          + "Name" = "data-platform-prod-private-us-east-1a"
        }
      + tags_all                                       = {
          + "Environment" = "prod"
          + "ManagedBy"   = "terraform"
          + "Name"        = "data-platform-prod-private-us-east-1a"
          + "Project"     = "data-platform"
        }
      + vpc_id                                         = (known after apply)
    }

  # module.network.aws_subnet.private["us-east-1b"] will be created
  + resource "aws_subnet" "private" {
      + arn                                            = (known after apply)
      + assign_ipv6_address_on_creation                = false
      + availability_zone                              = "us-east-1b"
      + availability_zone_id                           = (known after apply)
      + cidr_block                                     = "10.1.1.0/24"
      + enable_dns64                                   = false
      + enable_resource_name_dns_a_record_on_launch    = false
      + enable_resource_name_dns_aaaa_record_on_launch = false
      + id                                             = (known after apply)
      + ipv6_cidr_block                                = (known after apply)
      + ipv6_cidr_block_association_id                 = (known after apply)
      + ipv6_native                                    = false
      + map_public_ip_on_launch                        = false
      + owner_id                                       = (known after apply)
      + private_dns_hostname_type_on_launch            = (known after apply)
      + region                                         = "us-east-1"
      + tags                                           = {
          + "Name" = "data-platform-prod-private-us-east-1b"
        }
      + tags_all                                       = {
          + "Environment" = "prod"
          + "ManagedBy"   = "terraform"
          + "Name"        = "data-platform-prod-private-us-east-1b"
          + "Project"     = "data-platform"
        }
      + vpc_id                                         = (known after apply)
    }

  # module.network.aws_subnet.private["us-east-1c"] will be created
  + resource "aws_subnet" "private" {
      + arn                                            = (known after apply)
      + assign_ipv6_address_on_creation                = false
      + availability_zone                              = "us-east-1c"
      + availability_zone_id                           = (known after apply)
      + cidr_block                                     = "10.1.2.0/24"
      + enable_dns64                                   = false
      + enable_resource_name_dns_a_record_on_launch    = false
      + enable_resource_name_dns_aaaa_record_on_launch = false
      + id                                             = (known after apply)
      + ipv6_cidr_block                                = (known after apply)
      + ipv6_cidr_block_association_id                 = (known after apply)
      + ipv6_native                                    = false
      + map_public_ip_on_launch                        = false
      + owner_id                                       = (known after apply)
      + private_dns_hostname_type_on_launch            = (known after apply)
      + region                                         = "us-east-1"
      + tags                                           = {
          + "Name" = "data-platform-prod-private-us-east-1c"
        }
      + tags_all                                       = {
          + "Environment" = "prod"
          + "ManagedBy"   = "terraform"
          + "Name"        = "data-platform-prod-private-us-east-1c"
          + "Project"     = "data-platform"
        }
      + vpc_id                                         = (known after apply)
    }

  # module.network.aws_vpc.this will be created
  + resource "aws_vpc" "this" {
      + arn                                  = (known after apply)
      + cidr_block                           = "10.1.0.0/16"
      + default_network_acl_id               = (known after apply)
      + default_route_table_id               = (known after apply)
      + default_security_group_id            = (known after apply)
      + dhcp_options_id                      = (known after apply)
      + enable_dns_hostnames                 = true
      + enable_dns_support                   = true
      + enable_network_address_usage_metrics = (known after apply)
      + id                                   = (known after apply)
      + instance_tenancy                     = "default"
      + ipv6_association_id                  = (known after apply)
      + ipv6_cidr_block                      = (known after apply)
      + ipv6_cidr_block_network_border_group = (known after apply)
      + main_route_table_id                  = (known after apply)
      + owner_id                             = (known after apply)
      + region                               = "us-east-1"
      + tags                                 = {
          + "Name" = "data-platform-prod-vpc"
        }
      + tags_all                             = {
          + "Environment" = "prod"
          + "ManagedBy"   = "terraform"
          + "Name"        = "data-platform-prod-vpc"
          + "Project"     = "data-platform"
        }
    }

  # module.network.aws_vpc_endpoint.s3 will be created
  + resource "aws_vpc_endpoint" "s3" {
      + arn                   = (known after apply)
      + cidr_blocks           = (known after apply)
      + dns_entry             = (known after apply)
      + id                    = (known after apply)
      + ip_address_type       = (known after apply)
      + network_interface_ids = (known after apply)
      + owner_id              = (known after apply)
      + policy                = (known after apply)
      + prefix_list_id        = (known after apply)
      + private_dns_enabled   = (known after apply)
      + region                = "us-east-1"
      + requester_managed     = (known after apply)
      + route_table_ids       = (known after apply)
      + security_group_ids    = (known after apply)
      + service_name          = "com.amazonaws.us-east-1.s3"
      + service_region        = (known after apply)
      + state                 = (known after apply)
      + subnet_ids            = (known after apply)
      + tags                  = {
          + "Name" = "data-platform-prod-s3-gateway-endpoint"
        }
      + tags_all              = {
          + "Environment" = "prod"
          + "ManagedBy"   = "terraform"
          + "Name"        = "data-platform-prod-s3-gateway-endpoint"
          + "Project"     = "data-platform"
        }
      + vpc_endpoint_type     = "Gateway"
      + vpc_id                = (known after apply)

      + dns_options (known after apply)

      + subnet_configuration (known after apply)
    }

Plan: 22 to add, 0 to change, 0 to destroy.

Changes to Outputs:
  + audit_role_arn           = (known after apply)
  + data_bucket_name         = (known after apply)
  + private_subnet_ids       = [
      + (known after apply),
      + (known after apply),
      + (known after apply),
    ]
  + processing_role_arn      = (known after apply)
  + service_linked_role_arns = {}
  + vpc_id                   = (known after apply)

─────────────────────────────────────────────────────────────────────────────

Note: You didn't use the -out option to save this plan, so Terraform can't
guarantee to take exactly these actions if you run "terraform apply" now.
```
