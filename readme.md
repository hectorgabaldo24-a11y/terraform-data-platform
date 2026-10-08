# Terraform Data Platform — Infraestructura base (Pre-entrega 1)

Andamiaje base de una plataforma de datos en AWS: backend remoto, red privada para datos e IAM core. Prepara el terreno para los módulos de streaming (Kinesis / Flink).

## Estructura

```text
.
├── bootstrap/            # Backend remoto (S3 + DynamoDB). Se aplica una sola vez, con estado local
├── modules/
│   ├── network/          # VPC, subredes privadas, route tables y S3 Gateway Endpoint
│   └── identity/         # Rol de procesamiento (Lambda/Flink) y rol de auditoría read-only
├── environments/
│   └── dev/              # Llama a los módulos y configura el backend
├── .tflint.hcl           # Configuración de tflint (reglas terraform + aws)
├── PLAN_OUTPUT.md        # Salida de terraform plan de environments/dev
└── readme.md
```

Para crear otro entorno (p. ej. `prod`) se copia `environments/dev`, se cambian `terraform.tfvars` y la `key` del backend; los módulos no se modifican.

## Recursos que se crean

| Capa | Recurso |
|------|---------|
| Bootstrap | Bucket S3 de tfstate (versionado, SSE AES256, sin acceso público) y tabla DynamoDB `LockID` para locking |
| Network | VPC, N subredes privadas (una por AZ, mínimo 2), una route table por subred, security group por defecto sin reglas, S3 Gateway Endpoint asociado a todas las route tables privadas |
| Network | **Sin** Internet Gateway, **sin** NAT Gateway, sin IPs públicas: no hay acceso directo desde internet |
| Data lake | Bucket `data-platform-dev-bucket` con SSE y bloqueo de acceso público |
| Identity | `processing-role` (asumible por Lambda y Managed Flink de la cuenta) con solo `s3:ListBucket`, `s3:GetObject`, `s3:PutObject` sobre un prefijo |
| Identity | `audit-readonly-role` con `ReadOnlyAccess`, asumible solo con MFA |

El módulo `identity` ya soporta `kinesis_stream_arns`: cuando se le pasan ARNs de streams, agrega una política de lectura (`GetRecords`, `GetShardIterator`, `DescribeStream`, `ListShards`, `SubscribeToShard`) para Flink, sin usar `*`.

## Requisitos

* Terraform >= 1.5
* Credenciales de AWS configuradas (`aws configure`, SSO o variables `AWS_*`)
* [tflint](https://github.com/terraform-linters/tflint) (Windows: `winget install TerraformLinters.tflint`)

## Despliegue

### 1. Bootstrap del backend (una sola vez)

```bash
cd bootstrap
terraform init
terraform apply
```

El bucket del state se llama `data-platform-tfstate-hector-659500704179` (los nombres de bucket son globales). Si otra persona lo despliega en su cuenta, debe usar un nombre propio: `terraform apply -var state_bucket_name=<nombre-unico>` y actualizar el mismo nombre en el bloque `backend "s3"` de `environments/dev/providers.tf`. El estado local del bootstrap no se versiona.

### 2. Entorno dev

```bash
cd environments/dev
terraform init
terraform validate
terraform plan
terraform apply
```

### 3. Calidad

```bash
terraform fmt -recursive
terraform validate
tflint --init        # una sola vez: descarga los plugins definidos en .tflint.hcl
tflint --recursive
```

Resultado actual: `terraform validate` y `tflint --recursive` sin errores ni advertencias. El `terraform plan` de dev (17 recursos a crear) está en [PLAN_OUTPUT.md](PLAN_OUTPUT.md).

## Variables principales (`environments/dev/terraform.tfvars`)

| Variable | Descripción | Valor dev |
|----------|-------------|-----------|
| `region` | Región de AWS | `us-east-1` |
| `project_name` | Nombre del proyecto | `data-platform` |
| `environment` | `dev`, `staging` o `prod` | `dev` |
| `vpc_cidr` | CIDR de la VPC | `10.0.0.0/16` |
| `az_count` | AZs / subredes privadas | `2` |
| `data_prefix` | Prefijo S3 accesible por el rol de procesamiento | `streaming` |

## Outputs (inputs de la próxima pre-entrega)

`vpc_id`, `private_subnet_ids`, `processing_role_arn`, `audit_role_arn`, `data_bucket_name`.

## Seguridad

* Ningún permiso usa `*` en acciones ni recursos propios (el rol de auditoría usa la política administrada `ReadOnlyAccess` de AWS).
* El rol de procesamiento restringe `ListBucket` por condición `s3:prefix` y los objetos por ARN con prefijo.
* El state está cifrado (SSE), versionado y con locking; `.gitignore` excluye `.terraform/`, `*.tfstate*` y planes.
