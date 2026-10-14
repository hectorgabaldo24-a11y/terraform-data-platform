# Evidencia por criterio de la rúbrica

Todas las salidas son reales, ejecutadas sobre este repositorio (Terraform 1.16.5, tflint 0.64.0, AWS provider 6.x).
Los planes y el `apply` de `dev` se ejecutaron contra AWS: ver [APPLY_OUTPUT.md](APPLY_OUTPUT.md).

## 1. Calidad del HCL

Variables con tipo y descripción en todos los módulos y entornos; validaciones en `vpc_cidr`, `az_count`, `environment` y `data_prefix`; `for_each` en lugar de `count` para recursos por AZ.

```text
$ terraform version
Terraform v1.16.5
on windows_amd64

$ terraform fmt -recursive -check   # sin salida = formato correcto
exit=0

$ cd bootstrap && terraform validate
Success! The configuration is valid.

$ cd environments/dev && terraform validate
Success! The configuration is valid.

$ cd environments/prod && terraform validate
Success! The configuration is valid.

$ tflint --version
TFLint version 0.64.0
+ ruleset.aws (0.40.0)

$ tflint --recursive   # sin salida = sin hallazgos
exit=0
```

## 2. Seguridad (ausencia de permisos `*` y red limitada)

```text
$ grep -rnE "\"\*\"|\"[a-z0-9]+:\*\"" modules environments bootstrap --include=*.tf
modules/identity/variables.tf:16:    condition     = length(var.data_prefix) > 0 && !startswith(var.data_prefix, "/") && !endswith(var.data_prefix, "/") && !strcontains(var.data_prefix, "*")
modules/network/main.tf:91:      identifiers = ["*"]
environments/dev/main.tf:48:    actions   = ["s3:*"]
environments/dev/main.tf:52:      type        = "*"
environments/dev/main.tf:53:      identifiers = ["*"]

$ grep -rnE "resources\s*=\s*\[\"\*\"\]" ... (Allow sobre todos los recursos)
coincidencias=0

$ grep -rnE "aws_internet_gateway|aws_nat_gateway|aws_eip" modules environments bootstrap --include=*.tf
coincidencias=0

$ git ls-files | grep -E "\.terraform/|\.tfstate|tfplan"   # repo limpio
coincidencias=0
```

Cómo leer el resultado:

* **Ningún `Allow` usa `resources = ["*"]`** ni `actions = ["*"]`. El rol de procesamiento queda limitado a `s3:ListBucket` (con condición `s3:prefix`) y `s3:GetObject`/`s3:PutObject` sobre `<bucket>/<prefijo>/*`.
* Las coincidencias que sí aparecen son de otro tipo:
  * `modules/identity/variables.tf:16`: no es un permiso; es la validación que **rechaza** prefijos con `*`.
  * `modules/network/main.tf:91`: `Principal: "*"` en la *endpoint policy* del S3 Gateway Endpoint. AWS exige ese principal en políticas de endpoint; el acceso queda restringido a las 5 acciones y a los buckets del data lake listados.
  * `environments/dev/main.tf:48-53`: política de **Deny** para tráfico sin TLS (`aws:SecureTransport = false`). Restringe, no concede.
* El rol de auditoría usa la política administrada `SecurityAudit` (solo metadatos, no lee datos) y exige MFA.
* **Red:** no hay Internet Gateway, NAT Gateway ni EIP; las subredes tienen `map_public_ip_on_launch = false`; el security group por defecto queda sin reglas; el endpoint de S3 es de tipo Gateway asociado a las route tables privadas ([PLAN_OUTPUT.md](PLAN_OUTPUT.md)).

## 3. Modularización (¿se reutiliza para prod?)

`environments/prod` usa los mismos módulos sin modificarlos. Diferencias respecto de `dev` (resultado de `diff -r environments/dev environments/prod`):

| Archivo | Diferencia |
|---------|------------|
| `backend.tf` | `key = "data-platform/prod/terraform.tfstate"` (state separado, mismo bucket y tabla de locking) |
| `terraform.tfvars` | `environment = "prod"`, `vpc_cidr = "10.1.0.0/16"`, `az_count = 3`, sin Service-Linked Role (AWS permite uno por cuenta y ya lo crea dev) |

Resultado: `Plan: 22 to add, 0 to change, 0 to destroy`, con 3 subredes (`10.1.0.0/24`, `10.1.1.0/24`, `10.1.2.0/24`) en `us-east-1a/b/c`. Detalle en [PLAN_OUTPUT_PROD.md](PLAN_OUTPUT_PROD.md).

## 4. Documentación (¿alguien nuevo puede desplegarlo?)

El [README](README.md) incluye, en orden: mapa consigna → archivos, requisitos (`aws sts get-caller-identity`, permisos), bootstrap, despliegue de `dev`, calidad, verificación post-despliegue y outputs.
Un ingeniero nuevo solo debe cambiar el nombre del bucket de estado (los nombres de bucket son globales) y seguir los pasos tal cual.

## Mapa requisito → evidencia

| Requisito de la consigna | Evidencia |
|--------------------------|-----------|
| Módulos `network` e `identity`, `environments/dev`, `README.md` | Estructura del repositorio |
| ≥ 2 subredes privadas en distintas AZ; endpoint S3 en las route tables privadas | [PLAN_OUTPUT.md](PLAN_OUTPUT.md) |
| Sin acceso directo desde internet | Sección 2 (sin IGW/NAT/EIP, sin IP pública) |
| Rol de procesamiento limitado a `ListBucket`/`GetObject`/`PutObject` por prefijo | [PLAN_OUTPUT.md](PLAN_OUTPUT.md) y sección 2 |
| Rol de auditoría de solo lectura; Service-Linked Role | [PLAN_OUTPUT.md](PLAN_OUTPUT.md) |
| Backend S3 con SSE y locking en DynamoDB | `environments/dev/backend.tf` y `bootstrap/main.tf` |
| `terraform validate` y `tflint` | Sección 1 |
| Repo sin temporales ni secretos | Sección 2 (`git ls-files`) |

## Advertencias conocidas

* `dynamodb_table` está marcado como *deprecated* en el backend S3 (Terraform recomienda `use_lockfile`). Se mantiene a propósito porque la consigna exige locking con DynamoDB; el plan confirma que el lock se adquiere (`Acquiring state lock`). Detalle en el README.

* **Service-Linked Role:** se comprobó con `aws iam list-roles` y `aws iam get-role` que `AWSServiceRoleForLakeFormationDataAccess` no existe en la cuenta, y que no hay state previo. El README incluye el chequeo previo y cómo importarlo si ya existiera. No se usa un data source para crearlo condicionalmente porque haría que Terraform lo destruya en el segundo `plan`.

## Trazabilidad de los planes

Cada `PLAN_OUTPUT*.md` incluye una sección *Procedencia* con fecha, comando, commit base, versión de Terraform y los hashes de árbol de `modules/` y `environments/<env>/` (el `bootstrap/` es independiente de esos planes). Esos hashes permiten comprobar con `git rev-parse` que el plan corresponde al código vigente. Los planes se regeneraron tras el último cambio de código y se contrastaron con los guardados antes: solo diferían en tiempos de lectura.

## Alcance

* `dev`: `fmt`, `validate`, `tflint`, `plan`, **`apply` exitoso** (20 recursos) y comandos de verificación del README ejecutados sobre la infraestructura real. Ver [APPLY_OUTPUT.md](APPLY_OUTPUT.md), que incluye el primer intento fallido (`BucketAlreadyExists`) y su corrección.
* `bootstrap`: `validate`, `tflint` y `plan` sobre el state local: `Plan: 1 to add, 0 to change, 0 to destroy` (solo la política de TLS del bucket del state; separar el módulo en `main/variables/outputs/providers` no altera recursos). **Ese cambio está en el código pero pendiente de aplicar** en la cuenta.
* `prod`: solo `plan`; no se aplicó.
* No se probó `terraform destroy`.
