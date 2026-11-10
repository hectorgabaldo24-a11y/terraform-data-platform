# Evidencia — Analítica in-stream con Amazon Redshift (Pre-entrega 6)

Corrida del 2026-11-10 en la cuenta `659500704179` (`us-east-1`); todas las horas están en UTC. El documento técnico completo es [CheckPoint_Redshift_Gabaldo_Hector.pdf](CheckPoint_Redshift_Gabaldo_Hector.pdf) y los pasos para reproducir la corrida están en el [README, Checkpoint 6](README.md#checkpoint-6--analítica-avanzada-in-stream-con-amazon-redshift).

| Archivo | Contenido |
|---------|-----------|
| [docs/evidencias-redshift/terraform_apply.txt](docs/evidencias-redshift/terraform_apply.txt) | `terraform apply` del módulo `redshift`. El primer intento falló con la regla de salida del SG: EC2 rechazó la descripción por tener un acento. Tras corregirla, un segundo apply creó la regla |
| [docs/evidencias-redshift/productor.txt](docs/evidencias-redshift/productor.txt) | Última tanda de eventos enviada a Kinesis, con *schema drift* |
| [docs/evidencias-redshift/validacion.txt](docs/evidencias-redshift/validacion.txt) | Salida de la sección `validacion` de [sql/redshift_streaming.sql](sql/redshift_streaming.sql), ejecutada como administrador |
| [docs/evidencias-redshift/validacion_analista.txt](docs/evidencias-redshift/validacion_analista.txt) | Salida de la sección `validacion-analista`, ejecutada con el rol IAM de analistas |
| [docs/evidencias-redshift/iceberg_metadata.txt](docs/evidencias-redshift/iceberg_metadata.txt) | Metadatos Iceberg: `$snapshots`, `$history`, `$partitions` y `$files` (Athena), `metadata_location` (Glue) y `metadata/` (S3) |

## Resultados clave

| Verificación | Resultado |
|--------------|-----------|
| Registros ingeridos de Kinesis (2 shards) | 710, de los cuales 64 tienen *schema drift* y quedaron conservados y clasificados |
| Errores de lectura del stream (`sys_stream_scan_errors`) | 0 |
| Errores de casting | 0: la conversión desde SUPER es *lax* (`"N/A"` → NULL) |
| Tipo de refresco de las 4 vistas | Incremental (`svv_mv_info.state = 1`) |
| Refresco programado | Cada 60 s como `IAMR:data-platform-dev-redshift-refresh`, de 3 a 4,5 s por ciclo |
| Lag Kinesis → Redshift | Promedio de 20–30 s y máximo de ~58 s, lo esperado con la cadencia de 1 minuto |
| JOIN stream + Iceberg | `analytics.v_clientes_stream_vs_lakehouse`. Redshift lee la tabla con `file_format = Iceberg` (10 archivos, 59 filas) |
| Rol de analistas | `IAMR:data-platform-dev-redshift-analyst` con `analytics_role`. Lee analytics y el lakehouse; en `stream` y `kds` recibe *permission denied* |

## Capturas de consola pendientes

Guardarlas en `docs/evidencias-redshift/` con estos nombres y regenerar el PDF con `python scripts/generar_informe_pdf.py`. Cada imagen reemplaza su recuadro "Captura pendiente".

Antes de las capturas: poner `redshift_refresh_schedule_enabled = true`, ejecutar `terraform apply` y correr el productor durante 2 o 3 minutos. Al terminar, volver a `false` y aplicar. En **Query Editor v2**, conectarse al workgroup `data-platform-dev-analytics` con **AWS Secrets Manager**, usando el secreto que devuelve `terraform output redshift_admin_secret_arn`, base `analytics`.

| Archivo | Qué capturar |
|---------|--------------|
| `consola-redshift-mv-stream.png` | Query Editor v2 con la consulta V3 (`stream.mv_eventos`) y filas recién llegadas |
| `consola-redshift-join-iceberg.png` | Query Editor v2 con `SELECT * FROM analytics.v_clientes_stream_vs_lakehouse` |
| `consola-redshift-workgroup.png` | Redshift Serverless → Namespace: rol IAM por defecto y workgroup no público |
| `consola-athena-snapshots.png` | Athena (workgroup `data-platform-dev-lakehouse`): `SELECT * FROM "ventanas_clientes$snapshots"` |
| `consola-glue-iceberg.png` | Glue → Tables → `ventanas_clientes` (formato Iceberg, esquema) |
| `consola-cloudwatch-dashboard.png` | CloudWatch → Dashboards → `data-platform-dev-streaming-analytics` |
