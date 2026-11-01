# Evidencia — Lakehouse con Apache Iceberg y AWS Glue (Pre-entrega 5)

Corrida del 2026-11-01 en la cuenta `659500704179` (`us-east-1`). Pasos para reproducirla: [README, Checkpoint 5](README.md#9-despliegue-y-prueba-de-persistencia). Capturas en [docs/evidencias-lakehouse/](docs/evidencias-lakehouse/).

## 1. Terraform: catálogo, tabla, IAM y workgroup

```text
$ terraform apply tfplan
module.lakehouse.aws_athena_workgroup.lakehouse: Creation complete after 1s [id=data-platform-dev-lakehouse]
module.lakehouse.aws_iam_policy.lakehouse_writer: Creation complete after 1s [id=arn:aws:iam::659500704179:policy/data-platform-dev-lakehouse-writer]
module.lakehouse.aws_glue_catalog_database.lakehouse_db: Creation complete after 1s [id=659500704179:lakehouse_db]
module.lakehouse.aws_iam_role_policy_attachment.lakehouse_writer: Creation complete after 0s [id=data-platform-dev-processing-role/arn:aws:iam::659500704179:policy/data-platform-dev-lakehouse-writer]
module.lakehouse.aws_glue_catalog_table.ventanas_clientes: Creation complete after 1s [id=659500704179:lakehouse_db:ventanas_clientes]
module.flink.aws_iam_policy.flink_access: Modifications complete after 1s
module.flink.aws_s3_object.flink_application: Modifications complete after 37s
module.flink.aws_kinesisanalyticsv2_application.flink: Modifications complete after 9s
Apply complete! Resources: 5 added, 3 changed, 0 destroyed.
```

`terraform validate` y `tflint --recursive` sin errores ni advertencias.

## 2. Tabla Iceberg creada por Terraform (antes del primer commit de Flink)

Metadata inicial `00000-*.metadata.json`, escrita por Glue a partir del esquema declarado en HCL:

```text
format-version  2
partition-specs [{'spec-id': 0, 'fields': [{'name': 'window_start_day', 'transform': 'day', 'source-id': 1, 'field-id': 1000}]}]
cols  [('window_start', 'timestamp'), ('window_end', 'timestamp'), ('cliente_id', 'string'), ('total_operaciones', 'long'),
       ('cantidad_compras', 'long'), ('importe_total_compras', 'double'), ('importe_promedio_compras', 'double'),
       ('ventanas_procesadas', 'long'), ('importe_acumulado', 'double'), ('variacion_pct', 'double'), ('alerta', 'string')]
props {'write.metadata.delete-after-commit.enabled': 'true', 'commit.retry.num-retries': '10', 'write.format.default': 'parquet',
       'write.metadata.previous-versions-max': '100', 'write.parquet.compression-codec': 'zstd'}
```

**Consola de AWS Glue → Data Catalog → Databases → `lakehouse_db` → Tables → `ventanas_clientes`:**

![Tabla en Glue](docs/evidencias-lakehouse/glue-tabla.png)

![Esquema y particionado en Glue](docs/evidencias-lakehouse/glue-esquema.png)

## 3. Job de Flink escribiendo en Iceberg

Arranque con el catálogo Glue (log de la aplicación):

```text
INFO:flink-app:Configuracion: stream=data-platform-dev-events region=us-east-1 initpos=LATEST destino=glue_catalog.lakehouse_db.ventanas_clientes warehouse=s3://data-platform-dev-659500704179-bucket/lakehouse watermark=30s
```

Operadores del sink: 2 escritores y **un único committer**:

```text
deteccion-patrones-por-cliente -> ... -> Calc[11] -> IcebergStreamWriter (1/2) switched from INITIALIZING to RUNNING.
IcebergFilesCommitter -> Sink: IcebergSink glue_catalog.lakehouse_db.ventanas_clientes (1/1) switched from INITIALIZING to RUNNING.
```

Tráfico de prueba: `python scripts/kinesis_producer.py --lotes 24 --registros 20 --pausa 10 --max-retraso 20` (480 eventos).

## 4. Commits en cada checkpoint (intervalo 1 minuto)

```text
Completed checkpoint 94 for job de4ebc1c2f31d41340bd2e276881c2c3 (148824 bytes, checkpointDuration=768 ms, finalizationTime=340 ms).
Committed snapshot 6388884917182056901 (MergeAppend)
Committed append to table: glue_catalog.lakehouse_db.ventanas_clientes, branch: main, checkpointId 94 in 576 ms
Completed checkpoint 95 for job de4ebc1c2f31d41340bd2e276881c2c3 (144758 bytes, checkpointDuration=984 ms, finalizationTime=278 ms).
Committed snapshot 3876041861386617884 (MergeAppend)
Committed append to table: glue_catalog.lakehouse_db.ventanas_clientes, branch: main, checkpointId 95 in 644 ms
```

**Cero errores de concurrencia:** búsqueda en CloudWatch de `ERROR`, `CommitFailedException` y `ConcurrentModification` durante la corrida → **0 eventos**.

## 5. Metadata actualizada en el Glue Data Catalog

```text
$ aws glue get-table --database-name lakehouse_db --name ventanas_clientes --query "Table.Parameters.{metadata:metadata_location,previa:previous_metadata_location}"
{
    "metadata": "s3://data-platform-dev-659500704179-bucket/lakehouse/lakehouse_db.db/ventanas_clientes/metadata/00004-cc5f3d40-cc00-48e9-bc97-2fcb98cb6176.metadata.json",
    "previa":   "s3://data-platform-dev-659500704179-bucket/lakehouse/lakehouse_db.db/ventanas_clientes/metadata/00003-53cf891a-c2dc-45e1-8cd8-ebb9d97d1c5a.metadata.json"
}
```

Al detener la aplicación se hizo el último commit y Glue quedó apuntando a `00005-65e5328a-....metadata.json` (`table_type = ICEBERG`).

## 6. Formato Iceberg en S3 (`data/` + `metadata/`)

```text
$ aws s3 ls s3://data-platform-dev-659500704179-bucket/lakehouse/lakehouse_db.db/ventanas_clientes/ --recursive
4191 data/window_start_day=2026-11-01/00000-0-9d6449e4-cd2a-4a52-a747-40bd2e35a98e-00001.parquet
4162 data/window_start_day=2026-11-01/00000-0-9d6449e4-cd2a-4a52-a747-40bd2e35a98e-00002.parquet
3918 data/window_start_day=2026-11-01/00001-0-232ae620-b24a-47cb-a5b6-e6df7630629e-00001.parquet
...
1913 metadata/00000-d0ef9405-69bc-4a41-8621-eb30c4632bd5.metadata.json   <- creada por Terraform/Glue
4152 metadata/00001-b9a6329f-7917-4680-a2cb-6266a7f9c6ae.metadata.json   <- 1er commit de Flink
5561 metadata/00002-b959cc8d-528c-4c55-8777-2010e03c49e1.metadata.json
6970 metadata/00003-53cf891a-c2dc-45e1-8cd8-ebb9d97d1c5a.metadata.json
8379 metadata/00004-cc5f3d40-cc00-48e9-bc97-2fcb98cb6176.metadata.json
8259 metadata/0a1516d6-b27c-4f59-9879-9edf0db25fa0-m0.avro                <- manifest
4496 metadata/snap-3077757530987269976-1-0a1516d6-b27c-4f59-9879-9edf0db25fa0.avro   <- manifest list
...
```

Estado final: 6 `metadata.json` (creación + 5 commits), 10 archivos Parquet en la partición `window_start_day=2026-11-01` (un prefijo por escritor: `00000-` y `00001-`).

## 7. Consultas en Athena (workgroup `data-platform-dev-lakehouse`)

![Consulta en Athena](docs/evidencias-lakehouse/athena-consulta.png)

Resumen de la tabla:

```text
SELECT count(*) AS filas, count(DISTINCT cliente_id) AS clientes, min(window_start) AS desde, max(window_start) AS hasta, sum(total_operaciones) AS operaciones FROM ventanas_clientes
filas | clientes | desde                      | hasta                      | operaciones
59    | 10       | 2026-11-01 17:51:00.000000 | 2026-11-01 22:13:00.000000 | 501
```

Transformaciones de Flink legibles (ventana, agregados y estado por cliente):

```text
SELECT window_start, cliente_id, total_operaciones, cantidad_compras, round(importe_total_compras,2) AS importe, ventanas_procesadas, round(importe_acumulado,2) AS acumulado, variacion_pct, alerta
FROM ventanas_clientes WHERE cliente_id = 'cliente-002' ORDER BY window_start
window_start               | cliente_id  | total_operaciones | cantidad_compras | importe | ventanas_procesadas | acumulado | variacion_pct | alerta
2026-11-01 17:51:00.000000 | cliente-002 | 13 | 13 | 2708.3  | 5 | 12248.81 | -1.13  | NULL
2026-11-01 22:10:00.000000 | cliente-002 | 3  | 3  | 995.01  | 6 | 13243.82 | -63.26 | NULL
2026-11-01 22:11:00.000000 | cliente-002 | 11 | 11 | 2606.48 | 7 | 15850.3  | 161.96 | PICO_COMPRAS
2026-11-01 22:12:00.000000 | cliente-002 | 11 | 11 | 2442.51 | 8 | 18292.81 | -6.29  | NULL
2026-11-01 22:13:00.000000 | cliente-002 | 12 | 12 | 3304.29 | 9 | 21597.1  | 35.28  | NULL
```

`ventanas_procesadas` arranca en 5 e `importe_acumulado` en 12.248,81 porque el `ValueState` del cliente se restauró del snapshot de la corrida de la Pre-entrega 4 (allí había llegado a 4 ventanas). La ventana de 17:51 había quedado abierta al detener esa corrida y se emitió al restaurar.

Alertas detectadas por la lógica stateful:

```text
SELECT window_start, cliente_id, round(importe_total_compras,2) AS importe, variacion_pct, alerta FROM ventanas_clientes WHERE alerta IS NOT NULL ORDER BY window_start
2026-11-01 22:10:00.000000 | cliente-010 | 1455.45 | 206.44 | PICO_COMPRAS
2026-11-01 22:10:00.000000 | cliente-008 | 1683.14 | 120.99 | PICO_COMPRAS
2026-11-01 22:10:00.000000 | cliente-006 | 1357.42 | 260.86 | PICO_COMPRAS
2026-11-01 22:11:00.000000 | cliente-002 | 2606.48 | 161.96 | PICO_COMPRAS
2026-11-01 22:11:00.000000 | cliente-004 | 2931.46 | 278.79 | PICO_COMPRAS
```

Historial de commits (un snapshot por checkpoint, cada ~60 s):

```text
SELECT committed_at, snapshot_id, operation, summary['added-records'] AS filas_agregadas FROM "ventanas_clientes$snapshots" ORDER BY committed_at
2026-11-01 22:11:25.639 UTC | 3077757530987269976 | append | 19
2026-11-01 22:12:23.628 UTC | 4210774569761478939 | append | 10
2026-11-01 22:13:23.598 UTC | 6388884917182056901 | append | 10
2026-11-01 22:14:23.782 UTC | 3876041861386617884 | append | 10
2026-11-01 22:15:23.592 UTC | 500829894777509235  | append | 10
```

Particiones:

```text
SELECT partition, record_count, file_count FROM "ventanas_clientes$partitions"
{window_start_day=2026-11-01} | 59 | 10
```

## 8. Partition pruning

La misma agregación, con distinto rango sobre `window_start` (la columna de negocio, no una columna de partición):

| Filtro | Filas | Bytes escaneados |
|--------|-------|------------------|
| Sin filtro | 10 clientes | 1.586 |
| `window_start` del 01/11 (la partición con datos) | 10 clientes | 1.586 |
| `window_start` del 31/10 (sin datos) | 0 | **0** |

```text
SELECT cliente_id, round(sum(importe_total_compras),2) AS importe FROM ventanas_clientes
WHERE window_start >= TIMESTAMP '2026-10-31 00:00:00' AND window_start < TIMESTAMP '2026-11-01 00:00:00'
GROUP BY cliente_id ORDER BY importe DESC LIMIT 3
-- estado=SUCCEEDED escaneado=0 bytes
```

Athena tradujo el predicado sobre `window_start` a la partición `day(window_start)` y descartó todos los archivos con la metadata de Iceberg, sin abrir ningún Parquet. Los `count(*)` también escanean 0 bytes: Iceberg los responde con las estadísticas de los manifests.

## 9. Problemas encontrados en el despliegue (y solución)

| Síntoma en CloudWatch | Causa | Solución |
|-----------------------|-------|----------|
| `LinkageError: loader constraint violation ... org.apache.commons.cli.Options` | `hadoop-client` incluía `commons-cli`, ya cargado por el `PythonDriver` de Flink | Excluido del shade (`commons-cli:commons-cli`) |
| `NoClassDefFoundError: org/apache/hadoop/conf/Configuration` en `FlinkCatalogFactory.clusterHadoopConf` | `HadoopUtils` de Flink vive en el classloader del runtime y no ve el Hadoop del JAR | `HadoopUtils` propia + relocations del shade, como el ejemplo oficial de AWS (`java/Iceberg/IcebergSQLSink`) |
| Arranque bloqueado por el snapshot anterior | El grafo cambió (sink JSON → Iceberg) | `flink_allow_non_restored_state = true` sólo para la migración; vuelto a `false` |
