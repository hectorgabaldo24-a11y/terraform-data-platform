# Terraform Data Platform

Plataforma de datos en AWS construida de forma incremental con Terraform:

| Pre-entrega | Capa | Sección |
|-------------|------|---------|
| 1 | Infraestructura base: backend remoto, red privada, IAM core | [Despliegue](#despliegue) |
| 2 | Ingesta: Kinesis Data Streams + Firehose -> S3 (bronze) | [Checkpoint 2](#checkpoint-2--ingesta-en-tiempo-real-con-amazon-kinesis) |
| 4 | Procesamiento en tiempo real: Managed Service for Apache Flink | [Checkpoint 4](#checkpoint-4--procesamiento-en-tiempo-real-con-managed-service-for-apache-flink) |

> **Dónde ejecutar Terraform:** la raíz del repo no contiene configuración. Hay dos puntos de entrada: `bootstrap/` (backend, una vez) y `environments/dev/` (la plataforma). Ver [Despliegue](#despliegue).

| Componente de la consigna | Dónde está |
|---------------------------|------------|
| Módulos `network` e `identity` | [modules/network](modules/network), [modules/identity](modules/identity) |
| Entorno que llama a los módulos | [environments/dev/main.tf](environments/dev/main.tf) |
| Backend S3 con SSE + locking DynamoDB | Config: [environments/dev/backend.tf](environments/dev/backend.tf) · Recursos: [bootstrap/main.tf](bootstrap/main.tf) (variables en `variables.tf`, valores en `terraform.tfvars`) |
| Variables (entorno, región, CIDR) | [environments/dev/variables.tf](environments/dev/variables.tf) |
| Outputs (`vpc_id`, `private_subnet_ids`, ARN de roles) | [environments/dev/outputs.tf](environments/dev/outputs.tf) |
| Salida de `terraform plan` | [PLAN_OUTPUT.md](PLAN_OUTPUT.md) |
| Salida de `terraform apply` y verificación real | [APPLY_OUTPUT.md](APPLY_OUTPUT.md) |
| Instrucciones para reproducir y verificar todo, paso a paso | [VERIFICACION.md](VERIFICACION.md) |
| Registro de una corrida real de esa verificación | [VERIFICACION_OUTPUT.md](VERIFICACION_OUTPUT.md) |
| Evidencia por criterio de la rúbrica (HCL, seguridad, modularización, documentación) | [EVIDENCIA.md](EVIDENCIA.md) |
| Reuso del módulo de red en otro entorno | [environments/prod](environments/prod) · [PLAN_OUTPUT_PROD.md](PLAN_OUTPUT_PROD.md) |
| Ingesta Kinesis + Firehose (Pre-entrega 2) | [modules/kinesis](modules/kinesis) · [scripts/](scripts) |
| Aplicación Flink y su módulo Terraform (Pre-entrega 4) | [flink-app/](flink-app) · [modules/flink](modules/flink) · [EVIDENCIA_FLINK.md](EVIDENCIA_FLINK.md) |

## Estructura

```text
.
├── bootstrap/            # Backend remoto (S3 + DynamoDB): main, variables, outputs, providers, tfvars. Se aplica una vez, con estado local
├── modules/
│   ├── network/          # VPC, subredes privadas, route tables y S3 Gateway Endpoint
│   ├── identity/         # Rol de procesamiento (Lambda/Flink) y rol de auditoría read-only
│   ├── kinesis/          # Kinesis Data Stream (2 shards, KMS), Firehose a S3 y alarmas (Pre-entrega 2)
│   └── flink/            # Managed Flink: aplicación, artefacto en S3, logs e IAM (Pre-entrega 4)
├── flink-app/            # Código PyFlink (src/main.py), pom.xml del conector y build.ps1 (Pre-entrega 4)
├── scripts/              # Productor de eventos y validación de Firehose
├── environments/
│   ├── dev/              # backend.tf, providers.tf, variables.tf, main.tf, outputs.tf, terraform.tfvars
│   └── prod/             # Ejemplo de reuso de los módulos: solo cambian backend key y tfvars
├── .tflint.hcl           # Configuración de tflint (reglas terraform + aws)
├── PLAN_OUTPUT.md        # Salida de terraform plan de environments/dev
├── APPLY_OUTPUT.md       # Apply de dev y verificación contra AWS
├── PLAN_OUTPUT_PROD.md   # Plan de environments/prod (reuso de módulos)
├── EVIDENCIA.md          # Evidencia por criterio de la rúbrica
├── EVIDENCIA_FLINK.md    # Evidencia de ejecución de la aplicación Flink
└── README.md
```

Para crear otro entorno se copia `environments/dev`, se cambian `terraform.tfvars` y la `key` del backend; los módulos no se modifican. [`environments/prod`](environments/prod) es un ejemplo ya armado y planificado (CIDR `10.1.0.0/16`, 3 AZ).

## Recursos que se crean

| Capa | Recurso |
|------|---------|
| Bootstrap | Bucket S3 de tfstate (versionado, SSE AES256, sin acceso público, política que exige TLS) y tabla DynamoDB `LockID` para locking |
| Network | VPC, N subredes privadas (una por AZ, mínimo 2), una route table por subred, security group por defecto sin reglas, S3 Gateway Endpoint asociado a todas las route tables privadas, con endpoint policy que solo permite los buckets del data lake |
| Network | **Sin** Internet Gateway, **sin** NAT Gateway, sin IPs públicas: no hay acceso directo desde internet |
| Data lake | Bucket `data-platform-dev-<ACCOUNT_ID>-bucket` (el ID de cuenta evita colisiones, los nombres S3 son globales) con SSE, versionado, bloqueo de acceso público y política que rechaza tráfico sin TLS |
| Identity | `processing-role` (asumible por Lambda y Managed Flink de la cuenta) con solo `s3:ListBucket`, `s3:GetObject`, `s3:PutObject` sobre un prefijo |
| Identity | Service-Linked Role de Lake Formation (`lakeformation.amazonaws.com`), configurable con `service_linked_role_services`; lo administra AWS y su política la define AWS |
| Identity | `audit-readonly-role` con `SecurityAudit` (solo lectura de metadatos, sin leer datos), asumible solo con MFA |

El módulo `identity` ya soporta `kinesis_stream_arns`: cuando se le pasan ARNs de streams, agrega una política de lectura (`GetRecords`, `GetShardIterator`, `DescribeStream`, `ListShards`, `SubscribeToShard`) para Flink, sin usar `*`.

### Chequeo previo del Service-Linked Role (antes de `terraform apply`)

AWS permite **un único** SLR por servicio y cuenta. Verificá si el de Lake Formation ya existe:

```bash
# Linux/macOS/Git Bash (en Git Bash anteponer MSYS_NO_PATHCONV=1)
aws iam list-roles --path-prefix /aws-service-role/lakeformation.amazonaws.com/   --query 'Roles[].RoleName' --output text
```

| Resultado | Qué hacer |
|-----------|-----------|
| Vacío (no existe) | Nada: `terraform apply` lo crea |
| `AWSServiceRoleForLakeFormationDataAccess` y **no** está en el state | **Importarlo** (conserva el rol existente): `terraform import 'module.identity.aws_iam_service_linked_role.this["lakeformation.amazonaws.com"]' arn:aws:iam::<ACCOUNT_ID>:role/aws-service-role/lakeformation.amazonaws.com/AWSServiceRoleForLakeFormationDataAccess` |
| Existe y no se quiere gestionar con Terraform | Poner `service_linked_role_services = []` en `terraform.tfvars` |

Un segundo entorno de la misma cuenta (p. ej. `prod`) debe usar `[]`, porque `dev` ya lo gestiona. Si `apply` falla con *"has been taken"*, aplicar la fila correspondiente. Estado verificado en la cuenta de desarrollo: el rol **no existía** (solo estaban los SLR de Resource Explorer, Support y Trusted Advisor).

## Requisitos

* Terraform >= 1.5
* AWS CLI y credenciales configuradas (`aws configure`, SSO o variables `AWS_*`). Comprobar con `aws sts get-caller-identity`
* Permisos para crear S3, DynamoDB, VPC/EC2 e IAM en la cuenta (en un sandbox sirve `AdministratorAccess`)
* [tflint](https://github.com/terraform-linters/tflint) (Windows: `winget install TerraformLinters.tflint`)

## Despliegue

### 1. Bootstrap del backend (una sola vez)

```bash
cd bootstrap
terraform init
terraform apply
```

El bucket del state se llama `data-platform-tfstate-hector-659500704179` y se define en [bootstrap/terraform.tfvars](bootstrap/terraform.tfvars) (los nombres de bucket son globales). Si otra persona lo despliega en su cuenta, debe editar `state_bucket_name` en ese archivo y poner el mismo nombre en el bloque `backend "s3"` de `environments/*/backend.tf`. El bucket del state exige TLS, está versionado, cifrado y sin acceso público. El estado local del bootstrap (`bootstrap/terraform.tfstate`) no se versiona: conviene respaldarlo fuera del repo.

> **Advertencia esperada en `terraform init/plan`:** *"The parameter `dynamodb_table` is deprecated. Use parameter `use_lockfile` instead."* Terraform ≥ 1.10 ofrece locking nativo en S3 (`use_lockfile = true`), pero la consigna pide el locking mediante una tabla de DynamoDB, así que se mantiene `dynamodb_table`. Es una advertencia, no un error: el locking funciona (el plan muestra `Acquiring state lock`). Para migrar en el futuro: agregar `use_lockfile = true`, verificar el bloqueo y recién entonces quitar `dynamodb_table` y la tabla de `bootstrap/`.

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

Resultado actual: `terraform validate` y `tflint --recursive` sin errores ni advertencias. El `terraform plan` de dev (20 recursos a crear) está en [PLAN_OUTPUT.md](PLAN_OUTPUT.md).

## Verificación

Después de `terraform apply` en `environments/dev`, estos comandos comprueban cada requisito de la consigna (ejecutar desde `environments/dev`):

```bash
# Outputs esperados: vpc_id, private_subnet_ids (2), processing_role_arn, audit_role_arn
terraform output

# Backend: el state está en S3 con cifrado, y el lock en DynamoDB
aws s3api get-bucket-encryption --bucket data-platform-tfstate-hector-659500704179
aws s3 ls s3://data-platform-tfstate-hector-659500704179/data-platform/dev/
aws dynamodb describe-table --table-name data-platform-tfstate-lock --query Table.TableStatus

# Red: 2 subredes en AZ distintas, sin IP pública
aws ec2 describe-subnets --filters Name=vpc-id,Values=$(terraform output -raw vpc_id)   --query 'Subnets[].[SubnetId,AvailabilityZone,MapPublicIpOnLaunch]' --output table

# S3 Gateway Endpoint asociado a las route tables privadas
aws ec2 describe-vpc-endpoints --filters Name=vpc-id,Values=$(terraform output -raw vpc_id)   --query 'VpcEndpoints[].[VpcEndpointType,ServiceName,RouteTableIds]'

# No hay salida a internet: ninguna ruta a un Internet/NAT Gateway
aws ec2 describe-route-tables --filters Name=vpc-id,Values=$(terraform output -raw vpc_id)   --query 'RouteTables[].Routes[].GatewayId'

# IAM: el rol de procesamiento solo tiene s3:ListBucket/GetObject/PutObject
aws iam get-policy-version --version-id v1   --policy-arn $(aws iam list-attached-role-policies --role-name data-platform-dev-processing-role   --query 'AttachedPolicies[0].PolicyArn' --output text)
```

Para destruir todo lo del entorno: `terraform destroy` en `environments/dev`. El backend (`bootstrap/`) tiene `prevent_destroy` y se elimina a mano.

## Variables principales (`environments/dev/terraform.tfvars`)

| Variable | Descripción | Valor dev |
|----------|-------------|-----------|
| `region` | Región de AWS | `us-east-1` |
| `project_name` | Nombre del proyecto | `data-platform` |
| `environment` | `dev`, `staging` o `prod` | `dev` |
| `vpc_cidr` | CIDR de la VPC | `10.0.0.0/16` |
| `az_count` | AZs / subredes privadas | `2` |
| `data_prefix` | Prefijo S3 accesible por el rol de procesamiento | `streaming` |
| `service_linked_role_services` | Servicios con Service-Linked Role | `["lakeformation.amazonaws.com"]` |

## Outputs (inputs de la próxima pre-entrega)

`vpc_id`, `private_subnet_ids`, `processing_role_arn`, `audit_role_arn`, `service_linked_role_arns`, `data_bucket_name`.

## Seguridad

* Ningún permiso usa `*` en acciones ni recursos propios (el rol de auditoría usa la política administrada `SecurityAudit` de AWS, que solo lee configuración). Los únicos comodines son `Principal: "*"` en una política de **Deny** de TLS del bucket y en la endpoint policy, que AWS exige para esos tipos de política.
* El rol de procesamiento restringe `ListBucket` por condición `s3:prefix` y los objetos por ARN con prefijo.
* El state está cifrado (SSE), versionado y con locking; `.gitignore` excluye `.terraform/`, `*.tfstate*` y planes.



---

## Checkpoint 2 — Ingesta en tiempo real con Amazon Kinesis

### 1. Objetivo

Implementar una ingesta de eventos en AWS utilizando Amazon Kinesis Data Streams, Amazon Data Firehose y Amazon S3, administrando la infraestructura mediante Terraform.

### 2. Arquitectura implementada

Python (boto3)
  -> Kinesis Data Streams
  -> Amazon Data Firehose
  -> Amazon S3 (zona Bronze)

### 3. Recursos desplegados

| Recurso | Configuración |
|---|---|
| Kinesis Data Stream | `data-platform-dev-events` |
| Modo de capacidad | PROVISIONED |
| Cantidad de shards | 2 |
| Cifrado de Kinesis | KMS |
| Firehose | `data-platform-dev-bronze` |
| Destino | Bucket S3 de desarrollo |
| Buffer de Firehose | 5 MB o 60 segundos |
| Compresión de salida | GZIP |
| Alarmas | Lectura y escritura excedidas |

Los recursos se administran desde el módulo `modules/kinesis/`, invocado desde `environments/dev/main.tf`.

### 4. Productor de eventos

Se implementó el productor Python en:

- `scripts/kinesis_producer.py`
- `scripts/requirements.txt`

La prueba envió 100 registros JSON a `data-platform-dev-events`, utilizando boto3 y 10 claves de partición diferentes (`cliente-001` a `cliente-010`).

Para ejecutar la prueba:

```powershell
python -m pip install -r .\scripts\requirements.txt
python .\scripts\kinesis_producer.py
```

Resultado informado por el productor:

```text
Proceso terminado. Registros enviados: 100
Stream: data-platform-dev-events
Claves de partición: 10 clientes diferentes
```

### 5. Validación de la infraestructura

Se verificó mediante AWS CLI que Kinesis y Firehose estuvieran activos.

Comandos utilizados:

```powershell
aws kinesis describe-stream-summary `
  --stream-name data-platform-dev-events `
  --query "StreamDescriptionSummary.{Estado:StreamStatus,Shards:OpenShardCount,Cifrado:EncryptionType}" `
  --output table
```

```powershell
aws firehose describe-delivery-stream `
  --delivery-stream-name data-platform-dev-bronze `
  --query "DeliveryStreamDescription.{Estado:DeliveryStreamStatus,Destino:Destinations[0].ExtendedS3DestinationDescription.BucketARN}" `
  --output table
```

Resultados observados:

- Kinesis: `ACTIVE`.
- Shards abiertos: `2`.
- Cifrado: `KMS`.
- Firehose: `ACTIVE`.

### 6. Validación de la entrega a S3

Se verificó la existencia de dos archivos GZIP en el bucket de desarrollo.

Prefijo observado:

```text
ingesta/year=2026/month=10/day=16/
```

Comando de verificación:

```powershell
aws s3 ls s3://data-platform-dev-659500704179-bucket/ingesta/ --recursive
```

Se descargaron los dos archivos y se comprobó que podían descomprimirse y contenían eventos JSON con campos como `event_id`, `event_type`, `cliente_id`, `importe` y `timestamp`.

Los archivos observados tenían tamaños de 532 y 722 bytes.

**Resultado:** se confirmó la entrega de datos desde Kinesis a través de Firehose hasta S3.

### 7. Evidencias locales

Los archivos descargados durante la prueba se guardaron en:

```text
evidencias/firehose/
```

Estos archivos sirven como evidencia local de la entrega y permiten inspeccionar el contenido descomprimido.

### 8. Observaciones pendientes

En la primera inspección, los objetos JSON aparecieron concatenados sin saltos de línea. Para facilitar el procesamiento posterior con herramientas como Python, Spark o Athena, conviene asegurar que cada registro enviado termine con `\n` y volver a validar el formato de los archivos nuevos.

La prueba confirmó la existencia y lectura de los archivos, pero no se debe interpretar la presencia de dos archivos como una verificación independiente de que los 100 registros estén todos presentes y sin duplicados.

### 9. Estado del checkpoint

- [x] Infraestructura desplegada mediante Terraform.
- [x] Kinesis activo con dos shards y cifrado KMS.
- [x] Firehose activo y configurado para entregar a S3.
- [x] Productor Python ejecutado con 100 registros.
- [x] Archivos GZIP encontrados y descargados desde S3.
- [ ] Validar el formato final con un registro JSON por línea.
- [ ] Contar y verificar los 100 registros entregados.
- [ ] Incorporar las evidencias definitivas y confirmar los cambios en Git.

### 10. Segunda prueba: validación del formato JSON

Se corrigió `scripts/kinesis_producer.py` para agregar un salto de línea (`\n`) al final de cada evento enviado a Kinesis. Esto permite procesar la salida como JSON Lines (NDJSON).

Se ejecutó nuevamente el productor y se descargaron los dos archivos generados en la segunda prueba, en la carpeta `evidencias/firehose_prueba2/`.

La validación se realizó mediante `scripts/validar_firehose.py`, que descomprime los archivos, analiza cada línea y comprueba los identificadores de los eventos.

**Resultado observado:**

| Métrica | Resultado |
|---|---:|
| Archivos GZIP de la segunda prueba | 2 |
| Registros JSON válidos | 100 |
| Líneas inválidas | 0 |
| IDs distintos | 100 |
| IDs del 1 al 100 completos | Sí |

La segunda prueba confirmó la entrega de los 100 registros y la validez del formato JSON por línea.

Estado actualizado del checkpoint:

- [x] Infraestructura desplegada mediante Terraform.
- [x] Kinesis activo con dos shards y cifrado KMS.
- [x] Firehose activo y configurado para entregar a S3.
- [x] Productor Python ejecutado con 100 registros.
- [x] Archivos GZIP descargados y descomprimidos.
- [x] Formato JSON por línea validado en la segunda prueba.
- [x] 100 registros y sus IDs verificados.
- [ ] Revisar los cambios de Git y preparar el commit.

### Evidencia de entrega en S3

```powershell
aws s3 ls s3://data-platform-dev-659500704179-bucket/ingesta/ --recursive
```

```text
2026-10-15 22:59:51        532 ingesta/year=2026/month=10/day=16/data-platform-dev-bronze-1-2026-10-16-01-58-50-9832922e-1b28-400c-8cc5-5e7e83c83f48.gz
2026-10-15 22:59:51        722 ingesta/year=2026/month=10/day=16/data-platform-dev-bronze-1-2026-10-16-01-58-50-a5fec46c-02dc-445d-a872-ecd9dc711514.gz
2026-10-15 23:07:57        724 ingesta/year=2026/month=10/day=16/data-platform-dev-bronze-1-2026-10-16-02-06-54-571abf9b-4adf-4969-884a-183a7ee9a766.gz
2026-10-15 23:08:02        532 ingesta/year=2026/month=10/day=16/data-platform-dev-bronze-1-2026-10-16-02-06-54-fccaf5b4-b13f-482d-bb79-f6fa02dc5708.gz
2026-10-15 23:27:18        542 ingesta/year=2026/month=10/day=16/data-platform-dev-bronze-1-2026-10-16-02-26-12-a1ba6215-3b03-4c05-9e4e-23536ced3c86.gz
2026-10-15 23:27:13        731 ingesta/year=2026/month=10/day=16/data-platform-dev-bronze-1-2026-10-16-02-26-12-dd973b1a-2dc0-44d4-a2ac-e387025d1085.gz
2026-10-15 23:38:06         89 ingesta/year=2026/month=10/day=16/data-platform-dev-bronze-1-2026-10-16-02-37-00-a5a54295-4c04-4bc0-a86e-172b444ff124.gz
```

---

## Checkpoint 4 — Procesamiento en tiempo real con Managed Service for Apache Flink

### 1. Objetivo

Agregar una capa de procesamiento *stateful* sobre la ingesta del Checkpoint 2: una aplicación de **Amazon Managed Service for Apache Flink** (PyFlink, Flink 1.19) que consume el mismo Kinesis Data Stream, agrega eventos en ventanas de tiempo de evento y mantiene estado por cliente, con checkpoints para recuperarse ante fallas.

### 2. Arquitectura

```text
scripts/kinesis_producer.py
        │  put_records (PartitionKey = cliente_id)
        ▼
Kinesis Data Stream  data-platform-dev-events  (2 shards, KMS)
        │                                   │
        │ (Checkpoint 2)                    │ (Checkpoint 4)
        ▼                                   ▼
Firehose -> S3 ingesta/ (bronze)     Managed Flink  data-platform-dev-flink
                                       ├─ Source Kinesis + watermark (event time)
                                       ├─ TUMBLE 1 min GROUP BY cliente_id
                                       ├─ KeyedProcessFunction (ValueState por cliente)
                                       ├─ Sink S3  flink/resultados/dt=YYYY-MM-DD/
                                       └─ Logs CloudWatch /aws/kinesis-analytics/data-platform-dev-flink
```

Firehose y Flink leen el stream en paralelo como consumidores independientes; cada uno lleva su propia posición de lectura.

### 3. Lógica de negocio

Los eventos representan operaciones de clientes (`compra` o `consulta`):

```json
{"event_id": 42, "event_type": "compra", "cliente_id": "cliente-002", "importe": 173.5, "timestamp": "2026-11-01T14:05:12.345678+00:00"}
```

El código está en [flink-app/src/main.py](flink-app/src/main.py) y calcula, por cliente y por minuto:

| Paso | Qué hace | Detalle |
|------|----------|---------|
| Deserialización | Tabla `eventos` sobre el conector `kinesis`, formato JSON | `json.ignore-parse-errors = true`: un registro malformado no detiene el job |
| Event time | `event_time` se deriva del campo `timestamp` del evento (no de la hora de llegada) | Se lee como texto y se convierte a `TIMESTAMP(3)`; si falta o es inválido cae en 1970 y se descarta como tardío |
| Watermark | `WATERMARK FOR event_time AS event_time - INTERVAL '30' SECOND` | Tolera hasta 30 s de desorden (configurable con `flink_watermark_delay_seconds`) |
| Ventana | `TUMBLE(..., INTERVAL '1' MINUTE)` agrupada por `cliente_id` | Equivale a `TumblingEventTimeWindows.of(1 min)` sobre un stream con `key_by(cliente_id)` |
| Agregaciones | `total_operaciones`, `cantidad_compras`, `importe_total_compras`, `importe_promedio_compras` | Flink mantiene el estado de cada ventana abierta hasta que el watermark la cierra |
| Estado por clave (KeyedState) | `DeteccionPatrones` (`KeyedProcessFunction`) con 3 `ValueState` por cliente | `ventanas_procesadas`, `importe_acumulado` (total histórico del cliente) e `importe_ventana_anterior` |
| Detección de patrones | `variacion_pct` contra la ventana anterior y `alerta = PICO_COMPRAS` | Se dispara si el importe de la ventana es ≥ 2 veces el anterior con al menos 2 compras |
| Salida | JSON en `s3://<bucket>/flink/resultados/dt=YYYY-MM-DD/` y una línea `VENTANA ...` por resultado en CloudWatch | Los archivos se confirman en cada checkpoint (exactly-once hacia S3) |

**Por qué 30 segundos de watermark:** el productor y la red introducen desorden (dos shards leídos en paralelo, reintentos de `put_records`, y el productor puede simular retrasos con `--max-retraso`). Con 5 s, un evento retrasado 10 s se perdería como tardío; con 30 s se aceptan esos casos y la ventana se emite como mucho 30 s después de cerrar, una latencia razonable para métricas por minuto. Además, `table.exec.source.idle-timeout = 30 s` evita que un shard sin tráfico frene el watermark de todo el job (sin esto las ventanas no se cerrarían nunca).

### 4. Paralelismo y KPUs

| Parámetro (Terraform) | Valor | Motivo |
|-----------------------|-------|--------|
| `parallelism` | 2 | El stream tiene 2 shards y el consumidor de Kinesis reparte shards entre subtareas: más de 2 subtareas de lectura quedarían ociosas |
| `parallelism_per_kpu` | 1 | Una tarea por KPU (1 vCPU, 4 GB): el worker de Python necesita memoria propia además de la JVM |
| KPUs de procesamiento | 2 | `ceil(parallelism / parallelism_per_kpu)` |
| KPU de orquestación | 1 | La agrega el servicio a toda aplicación; total facturado: 3 KPUs mientras está en `RUNNING` |
| `auto_scaling_enabled` | false | Costo predecible en dev; el volumen de prueba no lo justifica |

Para escalar: aumentar los shards en `modules/kinesis` y `flink_parallelism` en `environments/dev/terraform.tfvars` en la misma proporción. La aplicación se crea con `flink_start_application = false` para no generar costo hasta que se quiera probar (ver despliegue).

### 5. Tolerancia a fallos

* **Checkpoints** (`checkpoint_configuration`): `checkpointing_enabled = true`, cada 60 s, con 5 s de pausa mínima. Managed Flink guarda los checkpoints en almacenamiento durable respaldado por S3 que administra el propio servicio: el bucket no se elige, así implementa el servicio la "ruta de S3" de checkpoints. Si un TaskManager falla, el job se reinicia desde el último checkpoint con el estado de las ventanas y el `ValueState` de cada cliente intactos, y retoma la lectura de Kinesis desde las posiciones guardadas.
* **Snapshots** (`application_snapshot_configuration`): habilitados. Al detener o actualizar la aplicación se toma un snapshot, y `RESTORE_FROM_LATEST_SNAPSHOT` lo restaura al iniciar, así el acumulado por cliente sobrevive a un redeploy.
* **Sink a S3**: el conector `filesystem` sólo publica los archivos cuando el checkpoint se completa, por lo que no quedan resultados duplicados ni parciales tras un reinicio.

### 6. Infraestructura (Terraform)

El módulo nuevo [modules/flink](modules/flink) se invoca desde [environments/dev/main.tf](environments/dev/main.tf) junto a `network`, `identity` y `kinesis`, y recibe sus outputs (nombre del stream, rol de procesamiento, bucket del data lake).

| Archivo | Contenido |
|---------|-----------|
| [modules/flink/main.tf](modules/flink/main.tf) | Log group/stream de CloudWatch, `aws_s3_object` con el ZIP, `aws_kinesisanalyticsv2_application` (código en S3, propiedades, checkpoints, monitoreo, paralelismo, snapshots, VPC opcional) |
| [modules/flink/iam.tf](modules/flink/iam.tf) | Política agregada al rol de procesamiento: leer el ZIP, escribir en `flink/resultados/`, logs de CloudWatch y, sólo si se usa VPC, ENIs |
| [modules/flink/variables.tf](modules/flink/variables.tf) / [outputs.tf](modules/flink/outputs.tf) | Parámetros (paralelismo, watermark, checkpoints, VPC) y salidas (nombre, estado, ruta S3, log group) |
| [modules/identity/main.tf](modules/identity/main.tf) | Ya existente: `processing-role` (confía en `kinesisanalytics.amazonaws.com`) y, al recibir `kinesis_stream_arns`, la lectura del stream (`GetRecords`, `GetShardIterator`, `DescribeStream`, `ListShards`, ...) |

La aplicación se registra como Python mediante el grupo de propiedades `kinesis.analytics.flink.run.options` (`python = main.py`, `jarfile = lib/pyflink-dependencies.jar`). La configuración de negocio (stream, región, ruta de salida, watermark) viaja en el grupo `FlinkApplicationProperties`, de modo que el código no tiene nombres de cuenta ni de bucket fijos.

**Red:** la aplicación corre **fuera de la VPC**. La VPC del Checkpoint 1 no tiene NAT y sólo tiene un endpoint Gateway de S3; si el job se conectara a ella no podría llegar a Kinesis ni a CloudWatch Logs. Sin VPC, Managed Flink usa los endpoints públicos de AWS con el rol IAM, que es todo lo que este job necesita. El módulo acepta `private_subnet_ids`/`security_group_ids`: si se completan, crea la `vpc_configuration` y agrega los permisos de ENI; en ese caso habría que sumar en `modules/network` endpoints de interfaz para Kinesis Data Streams, CloudWatch Logs y Monitoring.

### 7. Despliegue

Requisitos adicionales: Maven **o** Docker (para compilar el JAR del conector) y credenciales AWS vigentes.

```powershell
# 1. Empaquetar: compila lib/pyflink-dependencies.jar (conector Kinesis) y arma flink-app/flink-app.zip
.\flink-app\build.ps1

# 2. Desplegar (sube el ZIP a s3://<bucket>/flink/app/ y crea la aplicación en estado READY)
cd environments\dev
terraform init
terraform plan
terraform apply

# 3. Iniciar el job: en terraform.tfvars poner  flink_start_application = true
terraform apply

# 4. Generar tráfico durante ~5 minutos, con eventos desordenados
cd ..\..
python .\scripts\kinesis_producer.py --lotes 30 --registros 20 --pausa 10 --max-retraso 20
```

Para cortar el costo: volver a `flink_start_application = false` y `terraform apply` (toma un snapshot y detiene la aplicación), o `terraform destroy`. Conviene iniciar y detener siempre con la variable: si se inicia desde la consola, el siguiente `apply` con `false` la detiene.

Si cambia el código: `.\flink-app\build.ps1` y `terraform apply`. El hash del ZIP cambia, Terraform sube la nueva versión y actualiza la aplicación, que se reinicia restaurando el último snapshot.

### 8. Validación

```powershell
# Estado de la aplicación (RUNNING) y paralelismo efectivo
aws kinesisanalyticsv2 describe-application --application-name data-platform-dev-flink `
  --query "ApplicationDetail.{Estado:ApplicationStatus,Version:ApplicationVersionId,Paralelismo:ApplicationConfigurationDescription.FlinkApplicationConfigurationDescription.ParallelismConfigurationDescription.CurrentParallelism}" --output table

# Resultados por ventana en los logs (una línea por cliente y minuto)
aws logs filter-log-events --log-group-name /aws/kinesis-analytics/data-platform-dev-flink `
  --filter-pattern VENTANA --max-items 20 --query "events[].message" --output text

# Alertas detectadas con el estado por cliente
aws logs filter-log-events --log-group-name /aws/kinesis-analytics/data-platform-dev-flink `
  --filter-pattern PICO_COMPRAS --max-items 10 --query "events[].message" --output text

# Archivos confirmados en S3 (aparecen después de cada checkpoint)
aws s3 ls s3://data-platform-dev-659500704179-bucket/flink/resultados/ --recursive
```

**Flink Dashboard:** consola de AWS -> Managed Apache Flink -> `data-platform-dev-flink` -> *Open Apache Flink dashboard*. En *Running Jobs* el grafo muestra la fuente Kinesis con el watermark, el operador de ventana (`WindowAggregate`), `deteccion-patrones-por-cliente` y el sink de archivos. En la pestaña *Checkpoints* se ven los checkpoints completados y el tamaño del estado; en *Watermarks* de cada operador, el avance del event time.

La evidencia de la corrida (capturas del grafo y logs) se registra en [EVIDENCIA_FLINK.md](EVIDENCIA_FLINK.md).

### 9. Ejecución local (opcional)

Requiere Java 11 y el JAR compilado (`build.ps1`). Lee el stream real con las credenciales locales y escribe en `flink-app/output/`:

```powershell
cd flink-app
python -m venv .venv; .\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
$env:IS_LOCAL = "true"
python .\src\main.py
```

### 10. Errores comunes contemplados

| Riesgo de la consigna | Cómo se cubre |
|-----------------------|---------------|
| Ignorar el checkpointing | `checkpointing_enabled = true` cada 60 s + snapshots con restauración automática |
| Watermarks demasiado agresivos | 30 s de tolerancia, configurable sin tocar código; timeout de inactividad para shards sin datos |
| Timestamps no parseables | `timestamp` se lee como texto y se normaliza; los inválidos no rompen el job |
| Permisos excesivos | Política acotada a `flink/app/*`, `flink/resultados/*` y al log stream de la aplicación; lectura sólo del stream propio |

### 11. Estado del checkpoint

- [x] Aplicación PyFlink que consume el stream del Checkpoint 2.
- [x] Watermark de 30 s sobre event time y timeout de inactividad.
- [x] Ventanas tumbling de 1 minuto con conteos, sumas y promedios por cliente.
- [x] `KeyedProcessFunction` con `ValueState` por cliente (acumulados y detección de picos).
- [x] Módulo `modules/flink` con `aws_kinesisanalyticsv2_application`, código en S3, checkpoints, monitoreo y paralelismo.
- [x] IAM: lectura de Kinesis (identity) + S3 y CloudWatch Logs (flink).
- [x] `terraform validate` y `tflint --recursive` sin errores ni advertencias.
- [x] `terraform apply` e inicio del job: `RUNNING` con paralelismo 2, checkpoints completados, 37 resultados de ventana y alertas en CloudWatch, archivos en S3 ([EVIDENCIA_FLINK.md](EVIDENCIA_FLINK.md)).
- [ ] Capturas del grafo y de los checkpoints en el Flink Dashboard (`docs/evidencias-flink/`).
