# Apply output — environments/dev

`terraform apply` ejecutado sobre la cuenta `659500704179` (`us-east-1`), con backend remoto (S3 + DynamoDB).
Código: commit con árboles `modules 0bd0b7adc45b` · `environments/dev eedb071b10eb` · `bootstrap d1997fc2dea6` (ver `PLAN_OUTPUT.md`).

**Resultado final: `Apply complete! Resources: 8 added, 0 changed, 0 destroyed.` (más 12 del primer intento = 20 recursos).**

## Qué pasó, en orden

1. **Primer intento (falló parcialmente).** Se aplicó el plan de 20 recursos. Se crearon 12 (VPC, subredes, route tables, roles, etc.), pero `aws_s3_bucket.data_platform` falló con
   `BucketAlreadyExists: The requested bucket name is not available` — el nombre `data-platform-dev-bucket` pertenece a otra cuenta (`head-bucket` devolvió 403). Los nombres de bucket S3 son globales y un `plan` no puede detectarlo.
2. **Corrección de código.** El nombre del bucket ahora incluye el ID de cuenta (`data-platform-dev-659500704179-bucket`) mediante `aws_caller_identity`, en `dev` y `prod`.
3. **Segundo `apply`.** Creó los 8 recursos pendientes. Terraform conservó los 12 ya creados (estaban en el state).
4. **Sin deriva.** `terraform plan -detailed-exitcode` posterior devolvió `0` (sin cambios pendientes).

## Salida del primer intento (fallido)

```text

Warning: Deprecated Parameter

The parameter "dynamodb_table" is deprecated. Use parameter "use_lockfile"
instead.
Acquiring state lock. This may take a few moments...
module.identity.aws_iam_service_linked_role.this["lakeformation.amazonaws.com"]: Creating...
module.identity.aws_iam_role.processing: Creating...
module.identity.aws_iam_role.audit: Creating...
module.network.aws_vpc.this: Creating...
aws_s3_bucket.data_platform: Creating...
module.identity.aws_iam_service_linked_role.this["lakeformation.amazonaws.com"]: Creation complete after 1s [id=arn:aws:iam::659500704179:role/aws-service-role/lakeformation.amazonaws.com/AWSServiceRoleForLakeFormationDataAccess]
module.identity.aws_iam_role.audit: Creation complete after 2s [id=data-platform-dev-audit-readonly-role]
module.identity.aws_iam_role_policy_attachment.audit_readonly: Creating...
module.identity.aws_iam_role.processing: Creation complete after 2s [id=data-platform-dev-processing-role]
module.identity.aws_iam_role_policy_attachment.audit_readonly: Creation complete after 0s [id=data-platform-dev-audit-readonly-role/arn:aws:iam::aws:policy/SecurityAudit]
module.network.aws_vpc.this: Creation complete after 4s [id=vpc-0af4a4e28eb6cda86]
module.network.aws_subnet.private["us-east-1b"]: Creating...
module.network.aws_subnet.private["us-east-1a"]: Creating...
module.network.aws_default_security_group.this: Creating...
module.network.aws_subnet.private["us-east-1b"]: Creation complete after 1s [id=subnet-040fe73fae45d2707]
module.network.aws_subnet.private["us-east-1a"]: Creation complete after 2s [id=subnet-0e73636150cae7d00]
module.network.aws_route_table.private["us-east-1b"]: Creating...
module.network.aws_route_table.private["us-east-1a"]: Creating...
module.network.aws_route_table.private["us-east-1b"]: Creation complete after 1s [id=rtb-0b7ce26640390ef29]
module.network.aws_route_table.private["us-east-1a"]: Creation complete after 1s [id=rtb-0297597b322c7e61b]
module.network.aws_route_table_association.private["us-east-1a"]: Creating...
module.network.aws_route_table_association.private["us-east-1b"]: Creating...
module.network.aws_default_security_group.this: Creation complete after 4s [id=sg-07ea3c5e064e49d6c]
module.network.aws_route_table_association.private["us-east-1b"]: Creation complete after 1s [id=rtbassoc-07132fc9c85b711b1]
module.network.aws_route_table_association.private["us-east-1a"]: Creation complete after 1s [id=rtbassoc-04b5327c368ee5c55]

Error: creating S3 Bucket (data-platform-dev-bucket): operation error S3: CreateBucket, https response error StatusCode: 409, RequestID: 3DGZ90VZARXTZAV8, HostID: +gHzv3DHyKVxx0GvA79wT9R/nCbDp9CD6F2FVN2NwDitUuuWpsoGZJBR72cr3HeHvBGizNeqksw4iYXRBW2aZqerhSaIyLNq, BucketAlreadyExists: The requested bucket name is not available. The bucket namespace is shared by all users of the system. Please select a different name and try again.

  with aws_s3_bucket.data_platform,
  on main.tf line 12, in resource "aws_s3_bucket" "data_platform":
  12: resource "aws_s3_bucket" "data_platform" {
```

## Salida del segundo `apply` (exitoso)

```text

Warning: Deprecated Parameter

The parameter "dynamodb_table" is deprecated. Use parameter "use_lockfile"
instead.
Acquiring state lock. This may take a few moments...
aws_s3_bucket.data_platform: Creating...
aws_s3_bucket.data_platform: Creation complete after 5s [id=data-platform-dev-659500704179-bucket]
data.aws_iam_policy_document.data_platform_tls: Reading...
module.network.data.aws_iam_policy_document.s3_endpoint[0]: Reading...
module.identity.data.aws_iam_policy_document.processing_s3: Reading...
aws_s3_bucket_public_access_block.data_platform: Creating...
aws_s3_bucket_versioning.data_platform: Creating...
aws_s3_bucket_server_side_encryption_configuration.data_platform: Creating...
module.network.data.aws_iam_policy_document.s3_endpoint[0]: Read complete after 0s [id=2470331080]
data.aws_iam_policy_document.data_platform_tls: Read complete after 0s [id=3468914165]
module.identity.data.aws_iam_policy_document.processing_s3: Read complete after 0s [id=2703625031]
module.identity.aws_iam_policy.processing_s3: Creating...
module.network.aws_vpc_endpoint.s3: Creating...
aws_s3_bucket_public_access_block.data_platform: Creation complete after 1s [id=data-platform-dev-659500704179-bucket]
aws_s3_bucket_policy.data_platform_tls: Creating...
aws_s3_bucket_server_side_encryption_configuration.data_platform: Creation complete after 2s [id=data-platform-dev-659500704179-bucket]
module.identity.aws_iam_policy.processing_s3: Creation complete after 2s [id=arn:aws:iam::659500704179:policy/data-platform-dev-processing-s3]
module.identity.aws_iam_role_policy_attachment.processing_s3: Creating...
aws_s3_bucket_policy.data_platform_tls: Creation complete after 1s [id=data-platform-dev-659500704179-bucket]
module.identity.aws_iam_role_policy_attachment.processing_s3: Creation complete after 0s [id=data-platform-dev-processing-role/arn:aws:iam::659500704179:policy/data-platform-dev-processing-s3]
aws_s3_bucket_versioning.data_platform: Creation complete after 3s [id=data-platform-dev-659500704179-bucket]
module.network.aws_vpc_endpoint.s3: Creation complete after 8s [id=vpce-02aba676cabeef46b]

Apply complete! Resources: 8 added, 0 changed, 0 destroyed.

Outputs:

audit_role_arn = "arn:aws:iam::659500704179:role/data-platform-dev-audit-readonly-role"
data_bucket_name = "data-platform-dev-659500704179-bucket"
private_subnet_ids = [
  "subnet-0e73636150cae7d00",
  "subnet-040fe73fae45d2707",
]
processing_role_arn = "arn:aws:iam::659500704179:role/data-platform-dev-processing-role"
service_linked_role_arns = {
  "lakeformation.amazonaws.com" = "arn:aws:iam::659500704179:role/aws-service-role/lakeformation.amazonaws.com/AWSServiceRoleForLakeFormationDataAccess"
}
vpc_id = "vpc-0af4a4e28eb6cda86"
```

## Verificación real contra la infraestructura desplegada

Comandos de la sección *Verificación* del README, ejecutados tras el `apply`:

```text
$ aws s3api get-bucket-encryption (state)
[
    {
        "SSEAlgorithm": "AES256"
    }
]
$ aws s3 ls s3://data-platform-tfstate-hector-659500704179/data-platform/dev/
2026-10-13 22:27:57      53055 terraform.tfstate
$ aws dynamodb describe-table (locking)
data-platform-tfstate-lock	ACTIVE	LockID

$ subredes
subnet-0e73636150cae7d00	us-east-1a	10.0.0.0/24	False
subnet-040fe73fae45d2707	us-east-1b	10.0.1.0/24	False

$ endpoint S3
[
    [
        "Gateway",
        "com.amazonaws.us-east-1.s3",
        "available",
        [
            "rtb-0b7ce26640390ef29",
            "rtb-0297597b322c7e61b"
        ]
    ]
]

$ route tables (destinos y gateways)
10.0.0.0/16	None	local
None	pl-63a5400a	vpce-02aba676cabeef46b
10.0.0.0/16	None	local
10.0.0.0/16	None	local
None	pl-63a5400a	vpce-02aba676cabeef46b

$ IGW/NAT en la VPC
IGW: 0  NAT: 0

$ politica del rol de procesamiento
[
    [
        "ListBucketPrefixOnly",
        "s3:ListBucket",
        "arn:aws:s3:::data-platform-dev-659500704179-bucket"
    ],
    [
        "ReadWriteObjectsInPrefix",
        [
            "s3:PutObject",
            "s3:GetObject"
        ],
        "arn:aws:s3:::data-platform-dev-659500704179-bucket/streaming/*"
    ]
]

$ rol de auditoria
SecurityAudit

$ bucket de datos
Enabled
{
    "BlockPublicAcls": true,
    "IgnorePublicAcls": true,
    "BlockPublicPolicy": true,
    "RestrictPublicBuckets": true
}
```

Qué demuestra: state en S3 cifrado (AES256) con tabla de locking `ACTIVE`; 2 subredes en `us-east-1a/b` sin IP pública; S3 Gateway Endpoint `available` asociado a **las dos** route tables privadas; en las route tables solo existe la ruta `local` y la del prefix list de S3 (ninguna a un Internet/NAT Gateway; IGW 0, NAT 0); el rol de procesamiento solo tiene `s3:ListBucket` (sobre el bucket) y `s3:GetObject`/`s3:PutObject` (sobre `streaming/*`); el rol de auditoría usa `SecurityAudit`; el bucket de datos tiene versionado y bloqueo de acceso público.
