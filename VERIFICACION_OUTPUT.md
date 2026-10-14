# Registro de la corrida de verificación

Ejecución real de los pasos 3 y 5 de [VERIFICACION.md](VERIFICACION.md) (más el plan de prod). Todo es de solo lectura: **no se ejecutó `apply` ni `destroy`**.

## Procedencia

| Dato | Valor |
|------|-------|
| Fecha | 2026-10-14 12:33 -0300 |
| Commit base | `fa81b4c` (más `VERIFICACION.md` y el cambio del README, sin commitear) |
| Cuenta AWS | `659500704179` (`us-east-1`), identidad `arn:aws:iam::659500704179:root` |

Hashes del código verificado. Coinciden con los de [PLAN_OUTPUT_PROD.md](PLAN_OUTPUT_PROD.md) y [APPLY_OUTPUT.md](APPLY_OUTPUT.md), es decir, el código no cambió desde el apply:

```text
modules            0bd0b7adc45b
environments/dev   eedb071b10eb
environments/prod  e23f88347eae
```

## Paso 3 — Plan

| Entorno | Comando | Resultado | Exit code |
|---------|---------|-----------|-----------|
| dev | `terraform plan -detailed-exitcode` | `No changes. Your infrastructure matches the configuration.` | `0` |
| prod | `terraform plan -detailed-exitcode` | `Plan: 22 to add, 0 to change, 0 to destroy.` | `2` |

dev ya está aplicado y sin deriva. prod nunca se aplicó, por eso el plan propone crear sus 22 recursos (igual que [PLAN_OUTPUT_PROD.md](PLAN_OUTPUT_PROD.md)).

## Paso 5 — Verificación contra AWS (dev)

| Requisito | Resultado observado | OK |
|-----------|---------------------|----|
| State cifrado | `AES256` | Sí |
| State versionado | `Enabled` | Sí |
| State sin acceso público | `True True True True` | Sí |
| State presente en S3 | `data-platform/dev/terraform.tfstate` (53055 bytes) | Sí |
| Locking | tabla `ACTIVE`, clave `LockID` | Sí |
| Bucket de datos cifrado | `AES256` | Sí |
| Bucket de datos sin acceso público | `True True True True` | Sí |
| Bucket exige TLS | `Deny` con `aws:SecureTransport = false`, sobre bucket y objetos | Sí |
| Subredes | `subnet-0e73636150cae7d00` us-east-1a, `subnet-040fe73fae45d2707` us-east-1b, `MapPublicIpOnLaunch = False` | Sí |
| S3 Gateway Endpoint | `Gateway`, `com.amazonaws.us-east-1.s3`, route tables `rtb-0b7ce26640390ef29` y `rtb-0297597b322c7e61b` | Sí |
| Sin Internet Gateway | lista vacía | Sí |
| Sin NAT Gateway | lista vacía | Sí |
| Security group por defecto | sin reglas de entrada ni de salida | Sí |
| Rol de procesamiento (`data-platform-dev-processing-role`) | Solo 3 acciones: `s3:ListBucket` (condición `s3:prefix` = `streaming`, `streaming/*`), `s3:PutObject` y `s3:GetObject` sobre `streaming/*` | Sí |
| Rol de auditoría (`data-platform-dev-audit-readonly-role`) | Política adjunta `SecurityAudit` | Sí |
| Auditoría exige MFA | `aws:MultiFactorAuthPresent = true` en la trust policy | Sí |
| Service-Linked Role | `arn:aws:iam::659500704179:role/aws-service-role/lakeformation.amazonaws.com/AWSServiceRoleForLakeFormationDataAccess` | Sí |

## No cubierto en esta corrida

* Prueba de bloqueo del state con dos `plan` en paralelo.
* `apply` y verificación contra AWS de prod (solo se planificó).
* `terraform destroy`.
