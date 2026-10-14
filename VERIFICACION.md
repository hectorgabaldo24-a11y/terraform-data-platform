# Verificación paso a paso

Guía para reproducir y comprobar todo el trabajo, de menor a mayor impacto. Los pasos 1–3 **no crean nada en AWS**; el paso 4 sí (y puede costar/ensuciar la cuenta), el paso 6 lo deshace.

Comandos en Bash (Git Bash, Linux, macOS). En PowerShell funcionan igual salvo `$(...)`, que se reemplaza por una variable previa (`$vpc = terraform output -raw vpc_id`). En Git Bash anteponer `MSYS_NO_PATHCONV=1` a los `aws` que usen rutas que empiecen con `/`.

| Paso | Qué prueba | Toca AWS | Resultado esperado |
|------|------------|----------|--------------------|
| 0 | Herramientas y credenciales | Solo lectura | Versiones y cuenta correctas |
| 1 | Formato y sintaxis | No | Sin salida / `Success!` |
| 2 | Lint | No | Sin hallazgos |
| 3 | Plan | Lee el state | `Plan: 20 to add` (dev) |
| 4 | Apply | **Crea recursos** | `Apply complete!` |
| 5 | Verificación contra AWS | Solo lectura | Ver tabla del paso 5 |
| 6 | Destroy | **Elimina recursos** | `Destroy complete!` |

## 0. Requisitos

```bash
terraform version                 # >= 1.5
aws --version
tflint --version
aws sts get-caller-identity       # debe mostrar la cuenta donde se quiere desplegar
```

Si la cuenta **no** es `659500704179`, antes de seguir cambiar el nombre del bucket del state (único global) en [bootstrap/terraform.tfvars](bootstrap/terraform.tfvars) y en el bloque `backend "s3"` de `environments/dev/backend.tf` y `environments/prod/backend.tf` (ver [README](README.md#1-bootstrap-del-backend-una-sola-vez)).

Chequeo previo del Service-Linked Role de Lake Formation (AWS permite uno por cuenta):

```bash
aws iam list-roles --path-prefix /aws-service-role/lakeformation.amazonaws.com/ --query 'Roles[].RoleName' --output text
```

Vacío = nada que hacer. Si ya existe, seguir la tabla del [README](README.md#chequeo-previo-del-service-linked-role-antes-de-terraform-apply).

## 1. Formato y validación (sin credenciales ni AWS)

Desde la raíz del repo:

```bash
terraform fmt -recursive -check          # sin salida y exit 0 = todo formateado

for d in bootstrap environments/dev environments/prod; do
  (cd "$d" && terraform init -backend=false -input=false >/dev/null && terraform validate)
done                                     # 3 × "Success! The configuration is valid."
```

`-backend=false` evita conectar al bucket del state, por eso no necesita credenciales en un clon limpio. Si el directorio ya tenía `.terraform/` inicializado con el backend, `init` puede pedir credenciales válidas (error `No valid credential sources found`): en ese caso renovar la sesión (`aws sso login`/`aws login`) o borrar `.terraform/` antes.

## 2. Lint

```bash
tflint --init                            # una sola vez
tflint --recursive                       # sin errores ni advertencias
```

## 3. Plan (lee el state remoto, no modifica nada)

```bash
cd environments/dev
terraform init
terraform plan -detailed-exitcode
```

* Antes del primer apply: `Plan: 20 to add, 0 to change, 0 to destroy.` (exit code `2`). Coincide con [PLAN_OUTPUT.md](PLAN_OUTPUT.md).
* Con la infraestructura ya aplicada: `No changes.` (exit code `0`), prueba de que no hay deriva.
* Se espera la advertencia `dynamodb_table is deprecated`; es intencional (ver README).

Reuso de módulos en `prod` (mismo procedimiento): `Plan: 22 to add` según [PLAN_OUTPUT_PROD.md](PLAN_OUTPUT_PROD.md).

```bash
cd ../prod && terraform init && terraform plan
```

## 4. Apply

Solo si el backend (bootstrap) no existe todavía; es de una sola vez y usa state local:

```bash
cd bootstrap
terraform init
terraform apply
terraform output                         # state_bucket y lock_table
```

Luego la plataforma:

```bash
cd ../environments/dev
terraform apply
terraform plan -detailed-exitcode        # debe devolver exit code 0
terraform output
```

Outputs esperados: `vpc_id`, `private_subnet_ids` (2), `processing_role_arn`, `audit_role_arn`, `service_linked_role_arns`, `data_bucket_name`. El registro de una ejecución real está en [APPLY_OUTPUT.md](APPLY_OUTPUT.md).

## 5. Verificación contra AWS (solo lectura)

Desde `environments/dev`. Cada comando contra su requisito:

```bash
VPC=$(terraform output -raw vpc_id)
STATE_BUCKET=data-platform-tfstate-hector-659500704179   # o el nombre que hayas configurado
DATA_BUCKET=$(terraform output -raw data_bucket_name)
```

| Requisito | Comando | Debe verse |
|-----------|---------|------------|
| State remoto cifrado | `aws s3api get-bucket-encryption --bucket $STATE_BUCKET` | `SSEAlgorithm: AES256` |
| State versionado | `aws s3api get-bucket-versioning --bucket $STATE_BUCKET` | `Status: Enabled` |
| State sin acceso público | `aws s3api get-public-access-block --bucket $STATE_BUCKET` | Los 4 valores en `true` |
| State presente en S3 | `aws s3 ls s3://$STATE_BUCKET/data-platform/dev/` | `terraform.tfstate` |
| Locking | `aws dynamodb describe-table --table-name data-platform-tfstate-lock --query Table.[TableStatus,KeySchema[0].AttributeName]` | `ACTIVE`, `LockID` |
| Bucket de datos cifrado | `aws s3api get-bucket-encryption --bucket $DATA_BUCKET` | `AES256` |
| Bucket de datos privado | `aws s3api get-public-access-block --bucket $DATA_BUCKET` | Los 4 valores en `true` |
| Bucket exige TLS | `aws s3api get-bucket-policy --bucket $DATA_BUCKET --query Policy --output text` | `Deny` con `aws:SecureTransport = false` |
| 2 subredes, AZ distintas, sin IP pública | `aws ec2 describe-subnets --filters Name=vpc-id,Values=$VPC --query 'Subnets[].[SubnetId,AvailabilityZone,MapPublicIpOnLaunch]' --output table` | 2 filas, AZ distintas, `False` |
| S3 Gateway Endpoint en las route tables privadas | `aws ec2 describe-vpc-endpoints --filters Name=vpc-id,Values=$VPC --query 'VpcEndpoints[].[VpcEndpointType,ServiceName,RouteTableIds]'` | `Gateway`, `com.amazonaws.us-east-1.s3`, 2 route tables |
| Sin salida a internet | `aws ec2 describe-internet-gateways --filters Name=attachment.vpc-id,Values=$VPC --query 'InternetGateways'` y `aws ec2 describe-nat-gateways --filter Name=vpc-id,Values=$VPC --query 'NatGateways'` | `[]` en ambos |
| Security group por defecto sin reglas | `aws ec2 describe-security-groups --filters Name=vpc-id,Values=$VPC Name=group-name,Values=default --query 'SecurityGroups[].[IpPermissions,IpPermissionsEgress]'` | Listas vacías |
| Rol de procesamiento: mínimo privilegio | `aws iam get-policy-version --version-id v1 --policy-arn $(aws iam list-attached-role-policies --role-name data-platform-dev-processing-role --query 'AttachedPolicies[0].PolicyArn' --output text)` | Solo `s3:ListBucket`, `s3:GetObject`, `s3:PutObject` sobre el bucket/prefijo `streaming` |
| Rol de auditoría | `aws iam list-attached-role-policies --role-name data-platform-dev-audit-readonly-role` | `SecurityAudit` |
| Auditoría exige MFA | `aws iam get-role --role-name data-platform-dev-audit-readonly-role --query Role.AssumeRolePolicyDocument` | Condición `aws:MultiFactorAuthPresent = true` |
| Service-Linked Role | `aws iam get-role --role-name AWSServiceRoleForLakeFormationDataAccess --query Role.Arn` | ARN bajo `/aws-service-role/lakeformation.amazonaws.com/` |

Prueba de que el bloqueo del state funciona: ejecutar `terraform plan` en una terminal y, mientras corre, `terraform plan` en otra; la segunda debe fallar con `Error acquiring the state lock`.

## 6. Limpieza

```bash
cd environments/dev  && terraform destroy
cd ../prod           && terraform destroy     # solo si se aplicó prod
```

El backend (`bootstrap/`) tiene `prevent_destroy` a propósito: se elimina a mano (vaciar el bucket versionado y quitar la protección) cuando ya no hace falta ningún state.

## Si algo falla

| Síntoma | Causa y salida |
|---------|----------------|
| `BucketAlreadyExists` al crear un bucket | Los nombres S3 son globales; cambiar el nombre (el bucket de datos ya incluye el ID de cuenta) |
| `has been taken` en el Service-Linked Role | Ya existe en la cuenta: importarlo o poner `service_linked_role_services = []` (ver README) |
| `Error acquiring the state lock` | Otra ejecución en curso; si quedó huérfano: `terraform force-unlock <ID>` |
| `AccessDenied` / credenciales | Revisar `aws sts get-caller-identity` y los permisos de la cuenta |
