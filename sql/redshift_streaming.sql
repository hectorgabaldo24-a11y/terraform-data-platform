/* =============================================================================
   Pre-entrega 6 — Analítica avanzada in-stream con Amazon Redshift
   -----------------------------------------------------------------------------
   Kinesis Data Streams ──(Streaming Ingestion, sin S3)──> Redshift Serverless
   Glue Data Catalog (Iceberg) ──(EXTERNAL SCHEMA)──────> Redshift Serverless

   Destino   : workgroup data-platform-dev-analytics, base "analytics"
               (infra/modules/redshift, desplegado con Terraform)
   Ejecución : python scripts/redshift_sql.py --secret-arn <redshift_admin_secret_arn>
                      --file sql/redshift_streaming.sql
               El runner usa la Redshift Data API (HTTPS + IAM) y separa el
               archivo por secciones "-- @seccion:". Las secciones "reset" y
               "validacion-analista" sólo se ejecutan si se piden con --seccion.

   Capas (medallion dentro de Redshift):
     kds.<stream>                     objeto externo: mapeo del stream de Kinesis
     stream.mv_eventos_kinesis        BRONZE  vista materializada de streaming:
                                              valida el JSON y lo guarda como SUPER
     stream.mv_eventos                SILVER  campos tipados + validación de contrato
     analytics.mv_ventas_por_minuto   GOLD    ventas por minuto y cliente
     analytics.mv_calidad_por_minuto  GOLD    registros válidos / con errores por minuto
     analytics.v_clientes_stream_vs_lakehouse   JOIN stream (caliente) + Iceberg (histórico)
     monitoring.*                     lag de ingesta y estado de los refrescos
     ops.sp_refrescar_stream()        refresco incremental de toda la cadena

   Convenciones de nombres: mv_ = vista materializada, v_ = vista, sp_ =
   procedimiento, sufijo _ts = TIMESTAMP en UTC. Identificadores en minúscula.
   ============================================================================= */


-- @seccion: seguridad
-- -----------------------------------------------------------------------------
-- 1. Roles de base de datos (RBAC)
--    analytics_role   : analistas. Sólo lectura de la capa analytics, del
--                       lakehouse y de la vista de lag. No ve el dato crudo.
--    stream_refresher : sólo puede ejecutar el procedimiento de refresco.
--    Ambos se otorgan automáticamente a los roles IAM que tienen el tag
--    RedshiftDbRoles (data-platform-dev-redshift-analyst / -refresh) cuando se
--    conectan con credenciales temporales: no hay usuarios con contraseña.
-- -----------------------------------------------------------------------------
CREATE ROLE analytics_role;
CREATE ROLE stream_refresher;

-- Nadie crea objetos en el esquema public por defecto.
REVOKE CREATE ON SCHEMA public FROM PUBLIC;


-- @seccion: esquemas-externos
-- -----------------------------------------------------------------------------
-- 2. Mapeo del stream de Kinesis (Streaming Ingestion)
--    IAM_ROLE default = data-platform-dev-redshift-service-role, el rol por
--    defecto del namespace (Terraform). Redshift lo asume para llamar a
--    kinesis:DescribeStream / GetShardIterator / GetRecords: autenticación
--    IAM entre servicios, sin claves de acceso.
--    Cada stream de la cuenta aparece como una tabla de este esquema.
-- -----------------------------------------------------------------------------
CREATE EXTERNAL SCHEMA IF NOT EXISTS kds
FROM KINESIS
IAM_ROLE default;

-- -----------------------------------------------------------------------------
-- 3. Lakehouse: Glue Data Catalog de la Pre-entrega 5 (tablas Apache Iceberg)
--    Redshift lee la metadata de Iceberg (metadata_location en Glue) y los
--    Parquet de S3 con el mismo rol. Es sólo lectura: los commits los hace Flink.
-- -----------------------------------------------------------------------------
CREATE EXTERNAL SCHEMA IF NOT EXISTS lakehouse
FROM DATA CATALOG
DATABASE 'lakehouse_db'
IAM_ROLE default
REGION 'us-east-1';


-- @seccion: esquemas-locales
-- -----------------------------------------------------------------------------
-- 4. Esquemas locales: separan el dato crudo (stream) de lo que consumen los
--    analistas (analytics). Los permisos se dan por esquema en la sección 10.
-- -----------------------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS stream;      -- bronze y silver (uso interno)
CREATE SCHEMA IF NOT EXISTS analytics;   -- gold y vistas de negocio
CREATE SCHEMA IF NOT EXISTS monitoring;  -- lag y salud de la ingesta
CREATE SCHEMA IF NOT EXISTS ops;         -- procedimientos de operación


-- @seccion: ingesta
-- -----------------------------------------------------------------------------
-- 5. BRONZE — vista materializada de streaming sobre el stream de Kinesis
--
--    * Cada REFRESH lee sólo los registros nuevos de cada shard desde el último
--      sequence number confirmado (refresco incremental). El primer REFRESH
--      lee desde TRIM_HORIZON (retención del stream: 24 h).
--    * Validación ANTES de extraer (schema drift): CAN_JSON_PARSE evita que un
--      registro que no es JSON haga fallar el refresco. El registro se conserva
--      con is_valid_json = false para poder auditarlo, en lugar de perderse.
--    * JSON_PARSE convierte el JSON en SUPER (semiestructurado): si mañana el
--      productor agrega un campo, la ingesta no cambia.
--    * Una vista de streaming no admite alias de subconsulta ni navegar el
--      resultado de JSON_PARSE en la misma expresión: la extracción tipada se
--      hace en la capa silver, sobre la columna SUPER ya materializada.
--    * AUTO REFRESH NO: la cadencia la define ops.sp_refrescar_stream() vía
--      EventBridge Scheduler (cada 1 minuto). Ver sección 9.
-- -----------------------------------------------------------------------------
CREATE MATERIALIZED VIEW stream.mv_eventos_kinesis
SORTKEY (llegada_kinesis_ts)
AUTO REFRESH NO
AS
SELECT
    approximate_arrival_timestamp                     AS llegada_kinesis_ts,  -- cuándo lo aceptó Kinesis (UTC)
    refresh_time                                      AS ingesta_redshift_ts, -- cuándo lo materializó Redshift (UTC)
    partition_key,
    shard_id,
    sequence_number,
    CAN_JSON_PARSE(kinesis_data)                      AS is_valid_json,
    CASE WHEN CAN_JSON_PARSE(kinesis_data)
         THEN JSON_PARSE(kinesis_data)
    END                                               AS payload              -- SUPER
FROM kds."data-platform-dev-events";


-- @seccion: modelado
-- -----------------------------------------------------------------------------
-- 6. SILVER — campos JSON convertidos a tipos nativos de Redshift
--
--    Contrato del evento (scripts/kinesis_producer.py):
--      {"event_id": 1, "event_type": "compra", "cliente_id": "cliente-001",
--       "importe": 123.45, "timestamp": "2026-11-10T16:16:25.281662+00:00"}
--
--    * Las conversiones desde SUPER son "lax": si el tipo no coincide
--      (importe = "N/A", timestamp = "10/11/2026 25:61") devuelven NULL en
--      lugar de abortar el refresco. Por eso no hay errores de casting.
--    * JSON_TYPEOF valida el tipo JSON antes de convertir (un event_id "12"
--      como texto no se acepta como número).
--    * event_ts: se exige ISO-8601 con zona UTC (+00:00 o Z). La conversión
--      SUPER -> TIMESTAMP conserva la hora de reloj, así que un offset distinto
--      daría una hora incorrecta: esos registros se marcan inválidos.
--      (Convertir VARCHAR -> TIMESTAMP o usar TIMESTAMPTZ con DATE_TRUNC son
--      funciones "mutables" y obligarían a recalcular la vista completa.)
--    * es_valido / motivo_invalido: el registro se conserva y se clasifica;
--      las capas gold filtran por es_valido y miden los errores.
-- -----------------------------------------------------------------------------
CREATE MATERIALIZED VIEW stream.mv_eventos
SORTKEY (event_ts)
AUTO REFRESH NO
AS
SELECT
    shard_id,
    sequence_number,
    llegada_kinesis_ts,
    ingesta_redshift_ts,

    CASE WHEN JSON_TYPEOF(payload.event_id) = 'number'
         THEN payload.event_id::BIGINT END                          AS event_id,
    CASE WHEN JSON_TYPEOF(payload.event_type) = 'string'
         THEN LOWER(payload.event_type::VARCHAR(32)) END            AS event_type,
    CASE WHEN JSON_TYPEOF(payload.cliente_id) = 'string'
         THEN payload.cliente_id::VARCHAR(64) END                   AS cliente_id,
    CASE WHEN JSON_TYPEOF(payload.importe) = 'number'
         THEN payload.importe::DECIMAL(12, 2) END                   AS importe,
    CASE WHEN JSON_TYPEOF(payload."timestamp") = 'string'
          AND (payload."timestamp"::VARCHAR(64) LIKE '%+00:00'
               OR payload."timestamp"::VARCHAR(64) LIKE '%Z')
         THEN payload."timestamp"::TIMESTAMP END                    AS event_ts,

    -- Registro utilizable por las métricas: JSON válido y los 5 campos con tipo correcto.
    -- COALESCE: un campo ausente da NULL en la comparación; se trata como inválido.
    COALESCE(is_valid_json
     AND JSON_TYPEOF(payload.event_id) = 'number'
     AND JSON_TYPEOF(payload.event_type) = 'string'
     AND JSON_TYPEOF(payload.cliente_id) = 'string'
     AND JSON_TYPEOF(payload.importe) = 'number'
     AND payload."timestamp"::TIMESTAMP IS NOT NULL
     AND (payload."timestamp"::VARCHAR(64) LIKE '%+00:00'
          OR payload."timestamp"::VARCHAR(64) LIKE '%Z'), FALSE)    AS es_valido,

    CASE
        WHEN NOT is_valid_json                                  THEN 'json_invalido'
        WHEN JSON_TYPEOF(payload.event_id) IS DISTINCT FROM 'number'
          OR JSON_TYPEOF(payload.cliente_id) IS DISTINCT FROM 'string'
          OR JSON_TYPEOF(payload.event_type) IS DISTINCT FROM 'string' THEN 'campo_obligatorio_faltante'
        WHEN JSON_TYPEOF(payload.importe) IS DISTINCT FROM 'number' THEN 'importe_no_numerico'
        WHEN payload."timestamp"::TIMESTAMP IS NULL             THEN 'timestamp_invalido'
        WHEN NOT (payload."timestamp"::VARCHAR(64) LIKE '%+00:00'
                  OR payload."timestamp"::VARCHAR(64) LIKE '%Z')   THEN 'timestamp_no_utc'
    END                                                             AS motivo_invalido,

    payload                                                         -- SUPER original, para auditoría
FROM stream.mv_eventos_kinesis;


-- @seccion: agregaciones
-- -----------------------------------------------------------------------------
-- 7. GOLD — métricas de tiempo real (respuesta instantánea: ya están agregadas)
--    Sólo SUM/COUNT/MAX sobre columnas TIMESTAMP: Redshift las mantiene con
--    refresco incremental (svv_mv_info.state = 1), sumando sólo lo nuevo.
-- -----------------------------------------------------------------------------

-- Ventas por minuto (event time) y cliente.
CREATE MATERIALIZED VIEW analytics.mv_ventas_por_minuto
SORTKEY (minuto)
AUTO REFRESH NO
AS
SELECT
    DATE_TRUNC('minute', event_ts)                                AS minuto,
    cliente_id,
    COUNT(*)                                                      AS operaciones,
    SUM(CASE WHEN event_type = 'compra' THEN 1 ELSE 0 END)        AS compras,
    SUM(CASE WHEN event_type = 'compra' THEN importe ELSE 0 END)  AS importe_compras,
    MAX(CASE WHEN event_type = 'compra' THEN importe END)         AS compra_maxima,
    MAX(llegada_kinesis_ts)                                       AS ultima_llegada_ts
FROM stream.mv_eventos
WHERE es_valido
GROUP BY 1, 2;

-- Calidad del stream: registros válidos y errores por minuto de llegada a Kinesis
-- (mide el schema drift: si aparece un motivo nuevo, el productor cambió).
CREATE MATERIALIZED VIEW analytics.mv_calidad_por_minuto
SORTKEY (minuto)
AUTO REFRESH NO
AS
SELECT
    DATE_TRUNC('minute', llegada_kinesis_ts)            AS minuto,
    COALESCE(motivo_invalido, 'ok')                     AS resultado,
    COUNT(*)                                            AS registros
FROM stream.mv_eventos
GROUP BY 1, 2;


-- @seccion: lakehouse
-- -----------------------------------------------------------------------------
-- 8. Integración Lakehouse: datos calientes (stream) + históricos (Iceberg)
--
--    lakehouse.ventanas_clientes es la tabla Iceberg que escribe Flink
--    (Pre-entrega 5): una fila por cliente y ventana de 1 minuto, con el
--    estado acumulado del cliente y alertas.
--    La vista compara el ritmo de compras de los últimos 15 minutos contra el
--    promedio histórico por ventana del mismo cliente.
--    WITH NO SCHEMA BINDING es obligatorio para vistas sobre tablas externas.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW analytics.v_clientes_stream_vs_lakehouse AS
WITH caliente AS (          -- Redshift: vista materializada sobre Kinesis
    SELECT
        cliente_id,
        COUNT(*)                                   AS minutos_activos,
        SUM(compras)                               AS compras_15m,
        SUM(importe_compras)                       AS importe_15m,
        (SUM(importe_compras) / COUNT(*))::DECIMAL(12, 2) AS importe_por_minuto,
        MAX(minuto)                                AS ultimo_minuto
    FROM analytics.mv_ventas_por_minuto
    WHERE minuto >= DATEADD(minute, -15, DATE_TRUNC('minute', GETDATE()))
    GROUP BY cliente_id
),
historico AS (              -- Iceberg en S3 vía Glue Data Catalog
    SELECT
        cliente_id,
        COUNT(*)                                   AS ventanas_historicas,
        AVG(importe_total_compras)::DECIMAL(12, 2) AS importe_promedio_ventana,
        MAX(importe_acumulado)                     AS importe_acumulado_historico,
        SUM(CASE WHEN alerta = 'PICO_COMPRAS' THEN 1 ELSE 0 END) AS alertas_historicas,
        MAX(window_end)                            AS ultima_ventana_historica
    FROM lakehouse.ventanas_clientes
    GROUP BY cliente_id
)
SELECT
    c.cliente_id,
    c.minutos_activos,
    c.compras_15m,
    c.importe_15m,
    c.importe_por_minuto,
    h.ventanas_historicas,
    h.importe_promedio_ventana,
    ROUND(c.importe_por_minuto / NULLIF(h.importe_promedio_ventana, 0), 2) AS ratio_vs_historico,
    h.alertas_historicas,
    h.ultima_ventana_historica,
    c.ultimo_minuto,
    CASE
        WHEN h.cliente_id IS NULL                                       THEN 'CLIENTE_NUEVO'
        WHEN c.importe_por_minuto = 0 AND h.importe_promedio_ventana = 0 THEN 'SIN_COMPRAS'
        WHEN c.importe_por_minuto > 2 * h.importe_promedio_ventana      THEN 'POR_ENCIMA_DEL_HISTORICO'
        WHEN c.importe_por_minuto < 0.5 * h.importe_promedio_ventana    THEN 'POR_DEBAJO_DEL_HISTORICO'
        ELSE 'NORMAL'
    END                                                              AS diagnostico
FROM caliente c
LEFT JOIN historico h ON h.cliente_id = c.cliente_id
WITH NO SCHEMA BINDING;


-- @seccion: monitoreo
-- -----------------------------------------------------------------------------
-- 9a. Lag de ingesta por minuto
--     lag_kinesis_a_redshift : desde que Kinesis aceptó el registro hasta que
--                              un REFRESH lo materializó (lo controla la cadencia).
--     lag_evento_a_kinesis   : desde que se generó el evento hasta Kinesis (red / productor).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW monitoring.v_lag_ingesta AS
SELECT
    DATE_TRUNC('minute', llegada_kinesis_ts)                                       AS minuto,
    COUNT(*)                                                                       AS registros,
    ROUND(AVG(DATEDIFF(millisecond, llegada_kinesis_ts, ingesta_redshift_ts)) / 1000.0, 1) AS lag_kinesis_a_redshift_prom_s,
    ROUND(MAX(DATEDIFF(millisecond, llegada_kinesis_ts, ingesta_redshift_ts)) / 1000.0, 1) AS lag_kinesis_a_redshift_max_s,
    ROUND(AVG(DATEDIFF(millisecond, event_ts, llegada_kinesis_ts)) / 1000.0, 1)    AS lag_evento_a_kinesis_prom_s,
    MAX(ingesta_redshift_ts)                                                       AS ultimo_refresco_ts
FROM stream.mv_eventos
GROUP BY 1;

-- 9b. Lo que leyó cada REFRESH de cada shard (vista del sistema de streaming).
--     lag_from_latest = registros del shard todavía no ingeridos al terminar el scan.
CREATE OR REPLACE VIEW monitoring.v_scans_stream AS
SELECT
    record_time                AS scan_ts,
    mv_name,
    partition_id               AS shard_id,
    scanned_rows,
    skipped_rows,
    scanned_bytes,
    lag_from_latest,
    min_latency_s,
    max_latency_s,
    stream_record_time_min,
    stream_record_time_max
FROM sys_stream_scan_states
WHERE stream_name = 'data-platform-dev-events';

-- 9c. Historial de refrescos (tipo incremental / recálculo completo, duración).
CREATE OR REPLACE VIEW monitoring.v_refrescos AS
SELECT
    schema_name || '.' || mv_name                     AS vista,
    start_time,
    DATEDIFF(millisecond, start_time, end_time)       AS duracion_ms,
    status,
    refresh_type
FROM sys_mv_refresh_history
WHERE schema_name IN ('stream', 'analytics');


-- @seccion: refresco
-- -----------------------------------------------------------------------------
-- 10. Estrategia de refresco incremental
--
--     * Las vistas anidadas (silver/gold sobre bronze) no admiten AUTO REFRESH
--       y, en Serverless, AUTO REFRESH sobre el stream mantendría el cómputo
--       activo todo el tiempo. Se refresca la cadena completa, en orden, desde
--       este procedimiento.
--     * Cadencia: EventBridge Scheduler lo invoca cada 1 minuto (Terraform:
--       redshift_refresh_schedule_enabled / refresh_schedule_expression). Es el
--       equilibrio para métricas "por minuto": refrescar cada segundo saturaría
--       el workgroup y no mejora una métrica que se agrega por minuto.
--     * Equivale a REFRESH ... CASCADE sobre cada vista gold, pero refresca
--       bronze y silver una sola vez para las dos.
--     * Cada REFRESH es incremental: bronze lee sólo los sequence numbers nuevos
--       de cada shard; silver y gold procesan sólo esas filas.
--     * SECURITY DEFINER: corre con los permisos del dueño. Quien lo invoca
--       (rol stream_refresher) no necesita acceso a las tablas.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE ops.sp_refrescar_stream()
AS $$
BEGIN
    -- COMMIT entre capas: dentro de una misma transacción la vista siguiente
    -- ve a la anterior como "no actualizada" y no incorpora las filas nuevas.
    REFRESH MATERIALIZED VIEW stream.mv_eventos_kinesis;       -- bronze: lee Kinesis
    COMMIT;
    REFRESH MATERIALIZED VIEW stream.mv_eventos;               -- silver
    COMMIT;
    REFRESH MATERIALIZED VIEW analytics.mv_ventas_por_minuto;  -- gold
    REFRESH MATERIALIZED VIEW analytics.mv_calidad_por_minuto; -- gold
    COMMIT;
END;
$$ LANGUAGE plpgsql
SECURITY DEFINER;


-- @seccion: permisos
-- -----------------------------------------------------------------------------
-- 11. Acceso restringido por rol (mínimo privilegio)
--     analytics_role : USAGE + SELECT sobre analytics, USAGE sobre lakehouse y
--                      sólo la vista de lag de monitoring. Sin acceso a stream
--                      (payload crudo) ni a kds (lectura directa del stream).
--     stream_refresher: sólo EXECUTE del procedimiento de refresco.
-- -----------------------------------------------------------------------------
REVOKE ALL ON SCHEMA stream     FROM PUBLIC;
REVOKE ALL ON SCHEMA analytics  FROM PUBLIC;
REVOKE ALL ON SCHEMA monitoring FROM PUBLIC;
REVOKE ALL ON SCHEMA ops        FROM PUBLIC;
REVOKE ALL ON SCHEMA kds        FROM PUBLIC;
REVOKE ALL ON SCHEMA lakehouse  FROM PUBLIC;
REVOKE ALL ON PROCEDURE ops.sp_refrescar_stream() FROM PUBLIC;

GRANT USAGE  ON SCHEMA analytics TO ROLE analytics_role;
GRANT SELECT ON ALL TABLES IN SCHEMA analytics TO ROLE analytics_role;
-- Objetos que se creen más adelante en analytics heredan el permiso.
ALTER DEFAULT PRIVILEGES IN SCHEMA analytics GRANT SELECT ON TABLES TO ROLE analytics_role;

GRANT USAGE  ON SCHEMA lakehouse TO ROLE analytics_role;

GRANT USAGE  ON SCHEMA monitoring TO ROLE analytics_role;
GRANT SELECT ON monitoring.v_lag_ingesta TO ROLE analytics_role;

GRANT USAGE   ON SCHEMA ops TO ROLE stream_refresher;
GRANT EXECUTE ON PROCEDURE ops.sp_refrescar_stream() TO ROLE stream_refresher;

-- Primera carga: lee el stream desde TRIM_HORIZON y llena toda la cadena.
CALL ops.sp_refrescar_stream();


-- @seccion: validacion
-- -----------------------------------------------------------------------------
-- 12. Validación (ejecutar después de enviar eventos con kinesis_producer.py)
-- -----------------------------------------------------------------------------

-- V1. Refresco manual de la cadena (lo mismo que hace el scheduler).
CALL ops.sp_refrescar_stream();

-- V2. Bronze: registros ingeridos desde Kinesis, por shard y validez del JSON.
SELECT shard_id, is_valid_json, COUNT(*) AS registros,
       MIN(llegada_kinesis_ts) AS primera_llegada, MAX(llegada_kinesis_ts) AS ultima_llegada
FROM stream.mv_eventos_kinesis
GROUP BY 1, 2
ORDER BY 1, 2;

-- V3. Silver: campos JSON convertidos a tipos nativos (sin errores de casting).
SELECT event_id, event_type, cliente_id, importe, event_ts, llegada_kinesis_ts, ingesta_redshift_ts
FROM stream.mv_eventos
WHERE es_valido
ORDER BY llegada_kinesis_ts DESC, event_id DESC
LIMIT 10;

-- V4. Tipos de las columnas tipadas.
SELECT column_name, data_type, character_maximum_length, numeric_precision, numeric_scale
FROM svv_columns
WHERE table_schema = 'stream' AND table_name = 'mv_eventos'
ORDER BY ordinal_position;

-- V5. Schema drift: registros conservados y clasificados (no rompen la ingesta).
SELECT motivo_invalido, COUNT(*) AS registros,
       MIN(JSON_SERIALIZE(payload)) AS ejemplo
FROM stream.mv_eventos
WHERE NOT es_valido
GROUP BY 1
ORDER BY 2 DESC;

-- V6. Gold: ventas por minuto (últimos 10 minutos con datos).
SELECT minuto, SUM(operaciones) AS operaciones, SUM(compras) AS compras,
       SUM(importe_compras) AS importe_compras, MAX(compra_maxima) AS compra_maxima
FROM analytics.mv_ventas_por_minuto
GROUP BY 1
ORDER BY 1 DESC
LIMIT 10;

-- V7. Gold: calidad del stream por minuto.
SELECT minuto, resultado, registros
FROM analytics.mv_calidad_por_minuto
ORDER BY minuto DESC, registros DESC
LIMIT 15;

-- V8. JOIN stream (Redshift) + histórico (Iceberg) en la misma sesión.
SELECT *
FROM analytics.v_clientes_stream_vs_lakehouse
ORDER BY cliente_id;

-- V9. JOIN ad hoc: importe de la última hora del stream + estado acumulado que
--     Flink dejó en Iceberg. Cada lado se agrega ANTES del JOIN (un cliente
--     tiene muchos minutos y muchas ventanas: unirlos sin agregar duplicaría sumas).
SELECT s.cliente_id,
       s.compras                                        AS compras_stream_ultima_hora,
       s.importe_compras                                AS importe_stream_ultima_hora,
       i.ventanas_procesadas                            AS ventanas_flink,
       i.importe_acumulado::DECIMAL(12, 2)              AS importe_acumulado_iceberg,
       (i.importe_acumulado + s.importe_compras)::DECIMAL(12, 2) AS importe_total_cliente,
       i.ultima_ventana                                 AS ultima_ventana_iceberg
FROM (SELECT cliente_id, SUM(compras) AS compras, SUM(importe_compras) AS importe_compras
      FROM analytics.mv_ventas_por_minuto
      WHERE minuto >= DATEADD(hour, -1, GETDATE())
      GROUP BY cliente_id) AS s
JOIN (SELECT cliente_id, MAX(ventanas_procesadas) AS ventanas_procesadas,
             MAX(importe_acumulado) AS importe_acumulado, MAX(window_end) AS ultima_ventana
      FROM lakehouse.ventanas_clientes
      GROUP BY cliente_id) AS i
  ON i.cliente_id = s.cliente_id
ORDER BY s.cliente_id;

-- V10. Metadatos de la tabla Iceberg vistos desde Redshift (Glue Data Catalog).
--      svv_external_tables trunca "parameters" a 128 caracteres; el historial
--      completo de snapshots se consulta en Athena ("ventanas_clientes$snapshots").
SELECT schemaname, tablename, location,
       TIMESTAMP 'epoch' + (REGEXP_SUBSTR(parameters, '"iceberg.table.lastUpdatedMs":"([0-9]+)"', 1, 1, 'e')::BIGINT / 1000)
                          * INTERVAL '1 second'                            AS ultimo_commit_iceberg,
       parameters                                                          AS parametros_glue
FROM svv_external_tables
WHERE schemaname = 'lakehouse';

SELECT columnnum, columnname, external_type, part_key
FROM svv_external_columns
WHERE schemaname = 'lakehouse' AND tablename = 'ventanas_clientes'
ORDER BY columnnum;

-- Cómo leyó Redshift la tabla: file_format = Iceberg y archivos resueltos a
-- partir de los manifests (no lista S3 ni usa particiones de Glue).
SELECT start_time, TRIM(table_name) AS tabla, TRIM(file_format) AS formato,
       scanned_files, returned_rows, returned_bytes, duration AS duracion_us
FROM sys_external_query_detail
WHERE file_format = 'Iceberg'
ORDER BY start_time DESC
LIMIT 5;

-- V11. Lag de ingesta (minutos recientes).
SELECT *
FROM monitoring.v_lag_ingesta
ORDER BY minuto DESC
LIMIT 10;

-- V12. Scans de Kinesis por shard (últimos refrescos).
SELECT *
FROM monitoring.v_scans_stream
ORDER BY scan_ts DESC
LIMIT 8;

-- V13. Refrescos: deben ser incrementales.
SELECT *
FROM monitoring.v_refrescos
ORDER BY start_time DESC
LIMIT 8;

-- V14. Estado de las vistas: state = 1 -> admite refresco incremental.
SELECT schema_name, name, autorefresh, is_stale, state
FROM svv_mv_info
WHERE schema_name IN ('stream', 'analytics')
ORDER BY schema_name, name;

-- V15. Errores de lectura del stream (registros > 1 MB, etc.): debe estar vacío.
SELECT record_time, mv_name, partition_id, error_code, error_reason
FROM sys_stream_scan_errors
ORDER BY record_time DESC
LIMIT 10;

-- V16. Refresco programado: lo ejecuta el usuario IAMR del rol IAM del scheduler,
--      cada ~60 s, sin contraseña.
SELECT TRIM(u.usename)                            AS usuario_bd,
       TRIM(q.query_text)                         AS sentencia,
       TRIM(q.status)                             AS estado,
       q.start_time,
       DATEDIFF(millisecond, q.start_time, q.end_time) AS duracion_ms
FROM sys_query_history q
JOIN pg_user u ON u.usesysid = q.user_id
WHERE q.query_text ILIKE 'CALL ops.sp_refrescar_stream%'
ORDER BY q.start_time DESC
LIMIT 6;


-- @seccion: validacion-analista
-- -----------------------------------------------------------------------------
-- 13. Validación de permisos. Ejecutar asumiendo el rol IAM de analistas:
--       python scripts/redshift_sql.py --profile terraform-dev \
--         --role-arn <redshift_analyst_role_arn> \
--         --file sql/redshift_streaming.sql --seccion validacion-analista --continue-on-error
--     Las dos últimas consultas DEBEN fallar con "permission denied".
-- -----------------------------------------------------------------------------
SELECT current_user AS usuario_bd;

-- El rol llega por el tag RedshiftDbRoles del rol IAM (no queda en svv_user_grants).
SELECT user_is_member_of(current_user, 'analytics_role')   AS tiene_analytics_role,
       user_is_member_of(current_user, 'stream_refresher') AS tiene_stream_refresher,
       has_schema_privilege('analytics', 'usage')          AS usa_analytics,
       has_schema_privilege('lakehouse', 'usage')          AS usa_lakehouse,
       has_schema_privilege('stream', 'usage')             AS usa_stream,
       has_schema_privilege('kds', 'usage')                AS usa_kds;

SELECT minuto, SUM(importe_compras) AS importe_compras
FROM analytics.mv_ventas_por_minuto
GROUP BY 1
ORDER BY 1 DESC
LIMIT 3;

SELECT COUNT(*) AS ventanas_iceberg
FROM lakehouse.ventanas_clientes;

SELECT cliente_id, compras_15m, ventanas_historicas, diagnostico
FROM analytics.v_clientes_stream_vs_lakehouse
ORDER BY cliente_id
LIMIT 3;

-- Debe fallar: el payload crudo no es accesible para analistas.
SELECT COUNT(*) FROM stream.mv_eventos_kinesis;

-- Debe fallar: no puede leer el stream de Kinesis directamente.
SELECT COUNT(*) FROM kds."data-platform-dev-events";


-- @seccion: reset
-- -----------------------------------------------------------------------------
-- 14. Limpieza (sólo a pedido: --seccion reset). Borra los objetos para volver
--     a ejecutar el script desde cero. Los datos se vuelven a leer del stream
--     (retención de 24 h) en el siguiente refresco.
-- -----------------------------------------------------------------------------
DROP PROCEDURE ops.sp_refrescar_stream();
DROP VIEW IF EXISTS analytics.v_clientes_stream_vs_lakehouse;
DROP VIEW IF EXISTS monitoring.v_lag_ingesta;
DROP VIEW IF EXISTS monitoring.v_scans_stream;
DROP VIEW IF EXISTS monitoring.v_refrescos;
DROP MATERIALIZED VIEW IF EXISTS analytics.mv_calidad_por_minuto;
DROP MATERIALIZED VIEW IF EXISTS analytics.mv_ventas_por_minuto;
DROP MATERIALIZED VIEW IF EXISTS stream.mv_eventos;
DROP MATERIALIZED VIEW IF EXISTS stream.mv_eventos_kinesis;
DROP SCHEMA IF EXISTS stream;
DROP SCHEMA IF EXISTS analytics;
DROP SCHEMA IF EXISTS monitoring;
DROP SCHEMA IF EXISTS ops;
DROP SCHEMA IF EXISTS lakehouse;
DROP SCHEMA IF EXISTS kds;
DROP ROLE analytics_role FORCE;
DROP ROLE stream_refresher FORCE;
