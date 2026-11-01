"""
Procesamiento en tiempo real de eventos de clientes (Pre-entregas 4 y 5).

Flujo:
  Kinesis (data-platform-dev-events)
    -> tabla `eventos` con event time + watermark
    -> ventana TUMBLE de 1 minuto por cliente (conteos, sumas, promedios)
    -> KeyedProcessFunction con ValueState por cliente (acumulados y deteccion de picos)
    -> tabla Apache Iceberg registrada en AWS Glue Data Catalog (lakehouse_db)

El sink de Iceberg escribe archivos Parquet en S3 y solo confirma el commit
(nuevo metadata.json + snapshot en Glue) cuando Flink completa un checkpoint.

En Managed Service for Apache Flink la configuracion se lee de las
"runtime properties" (grupo FlinkApplicationProperties) que define Terraform.
En local (IS_LOCAL=true) se usan variables de entorno o valores por defecto.
"""

import json
import logging
import os
from pathlib import Path

from pyflink.common import Row, Types
from pyflink.datastream import StreamExecutionEnvironment
from pyflink.datastream.functions import KeyedProcessFunction, RuntimeContext
from pyflink.datastream.state import ValueStateDescriptor
from pyflink.table import EnvironmentSettings, StreamTableEnvironment


# --------------------------------------------------
# CONFIGURACION
# --------------------------------------------------

APPLICATION_PROPERTIES_FILE = "/etc/flink/application_properties.json"
PROPERTY_GROUP_ID = "FlinkApplicationProperties"

IS_LOCAL = os.environ.get("IS_LOCAL", "").lower() == "true"
PROJECT_DIR = Path(__file__).resolve().parent.parent

logger = logging.getLogger("flink-app")
logging.basicConfig(level=logging.INFO)


def cargar_propiedades():
    """Lee las runtime properties de Managed Flink (si existen)."""
    if not os.path.isfile(APPLICATION_PROPERTIES_FILE):
        return {}

    with open(APPLICATION_PROPERTIES_FILE, "r", encoding="utf-8") as f:
        grupos = json.load(f)

    for grupo in grupos:
        if grupo["PropertyGroupId"] == PROPERTY_GROUP_ID:
            return grupo["PropertyMap"]

    return {}


PROPS = cargar_propiedades()


def prop(nombre, default):
    """Prioridad: runtime property -> variable de entorno -> default."""
    return PROPS.get(nombre, os.environ.get(nombre.upper().replace(".", "_"), default))


AWS_REGION = prop("aws.region", "us-east-1")
KINESIS_STREAM = prop("input.stream.name", "data-platform-dev-events")
STREAM_INITPOS = prop("input.stream.initpos", "LATEST")

# Lakehouse: catalogo Glue + tabla Iceberg creada por Terraform (modulo lakehouse).
ICEBERG_CATALOG = "glue_catalog"
ICEBERG_WAREHOUSE = prop("iceberg.warehouse", "")
ICEBERG_DATABASE = prop("iceberg.database", "lakehouse_db")
ICEBERG_TABLE = prop("iceberg.table", "ventanas_clientes")

# Tolerancia al desorden: un evento puede llegar hasta N segundos tarde
# respecto del evento mas nuevo visto y aun asi entrar en su ventana.
WATERMARK_DELAY_SECONDS = int(prop("watermark.delay.seconds", "30"))

# Si un shard no recibe datos, no frena el avance del watermark.
SOURCE_IDLE_TIMEOUT = prop("source.idle.timeout", "30 s")

# Deteccion de picos: total de compras de la ventana >= factor x ventana anterior.
SPIKE_FACTOR = float(prop("alert.spike.factor", "2.0"))
SPIKE_MIN_COMPRAS = int(prop("alert.spike.min.compras", "2"))


# --------------------------------------------------
# LOGICA STATEFUL POR CLIENTE (KeyedState)
# --------------------------------------------------

# Orden de columnas que produce la consulta de ventanas.
(
    COL_WINDOW_START,
    COL_WINDOW_END,
    COL_CLIENTE,
    COL_TOTAL_OPERACIONES,
    COL_CANTIDAD_COMPRAS,
    COL_IMPORTE_TOTAL,
    COL_IMPORTE_PROMEDIO,
) = range(7)

OUTPUT_TYPE = Types.ROW_NAMED(
    [
        "window_start",
        "window_end",
        "cliente_id",
        "total_operaciones",
        "cantidad_compras",
        "importe_total_compras",
        "importe_promedio_compras",
        "ventanas_procesadas",
        "importe_acumulado",
        "variacion_pct",
        "alerta",
    ],
    [
        Types.STRING(),
        Types.STRING(),
        Types.STRING(),
        Types.LONG(),
        Types.LONG(),
        Types.DOUBLE(),
        Types.DOUBLE(),
        Types.LONG(),
        Types.DOUBLE(),
        Types.DOUBLE(),
        Types.STRING(),
    ],
)


class DeteccionPatrones(KeyedProcessFunction):
    """
    Recibe el resultado de cada ventana de un cliente y mantiene en estado:
      - cantidad de ventanas procesadas,
      - importe acumulado de compras desde que arranco el job,
      - importe de compras de la ventana anterior.
    Con eso calcula la variacion contra la ventana anterior y marca picos.
    El estado se guarda en cada checkpoint y se recupera ante reinicios.
    """

    def open(self, runtime_context: RuntimeContext):
        self.ventanas = runtime_context.get_state(
            ValueStateDescriptor("ventanas_procesadas", Types.LONG())
        )
        self.acumulado = runtime_context.get_state(
            ValueStateDescriptor("importe_acumulado", Types.DOUBLE())
        )
        self.anterior = runtime_context.get_state(
            ValueStateDescriptor("importe_ventana_anterior", Types.DOUBLE())
        )

    def process_element(self, value, ctx):
        cliente = value[COL_CLIENTE]
        importe = value[COL_IMPORTE_TOTAL] or 0.0
        compras = value[COL_CANTIDAD_COMPRAS] or 0

        ventanas = (self.ventanas.value() or 0) + 1
        acumulado = (self.acumulado.value() or 0.0) + importe
        anterior = self.anterior.value()

        variacion = None
        alerta = None
        if anterior is not None and anterior > 0:
            variacion = round((importe - anterior) / anterior * 100, 2)
            if importe >= anterior * SPIKE_FACTOR and compras >= SPIKE_MIN_COMPRAS:
                alerta = "PICO_COMPRAS"

        self.ventanas.update(ventanas)
        self.acumulado.update(acumulado)
        self.anterior.update(importe)

        logger.info(
            "VENTANA cliente=%s inicio=%s operaciones=%s compras=%s importe=%.2f "
            "acumulado=%.2f ventanas=%s variacion_pct=%s alerta=%s",
            cliente,
            value[COL_WINDOW_START],
            value[COL_TOTAL_OPERACIONES],
            compras,
            importe,
            acumulado,
            ventanas,
            variacion,
            alerta,
        )

        yield Row(
            value[COL_WINDOW_START],
            value[COL_WINDOW_END],
            cliente,
            value[COL_TOTAL_OPERACIONES],
            compras,
            importe,
            value[COL_IMPORTE_PROMEDIO],
            ventanas,
            round(acumulado, 2),
            variacion,
            alerta,
        )


# --------------------------------------------------
# PIPELINE
# --------------------------------------------------

def main():
    env = StreamExecutionEnvironment.get_execution_environment()
    table_env = StreamTableEnvironment.create(
        env, environment_settings=EnvironmentSettings.in_streaming_mode()
    )
    config = table_env.get_config().get_configuration()

    if IS_LOCAL:
        # En Managed Flink los checkpoints los configura el servicio (Terraform).
        env.enable_checkpointing(10000)
        jar_path = PROJECT_DIR / "target" / "pyflink-dependencies.jar"
        config.set_string("pipeline.jars", jar_path.as_uri())

    config.set_string("table.exec.source.idle-timeout", SOURCE_IDLE_TIMEOUT)

    if not ICEBERG_WAREHOUSE:
        raise ValueError("Falta la propiedad iceberg.warehouse (ICEBERG_WAREHOUSE en local)")

    destino = f"{ICEBERG_CATALOG}.{ICEBERG_DATABASE}.{ICEBERG_TABLE}"
    logger.info(
        "Configuracion: stream=%s region=%s initpos=%s destino=%s warehouse=%s watermark=%ss",
        KINESIS_STREAM,
        AWS_REGION,
        STREAM_INITPOS,
        destino,
        ICEBERG_WAREHOUSE,
        WATERMARK_DELAY_SECONDS,
    )

    # --------------------------------------------------
    # FUENTE: KINESIS
    # --------------------------------------------------
    # El productor envia `timestamp` en ISO-8601 con zona (+00:00), que el formato
    # JSON de Flink no parsea como TIMESTAMP(3). Se lee como STRING y se deriva
    # event_time con precision de segundos. Si falta o es invalido, cae en 1970
    # y el watermark lo descarta como evento tardio en lugar de romper el job.

    table_env.execute_sql(f"""
        CREATE TABLE eventos (
            event_id BIGINT,
            event_type STRING,
            cliente_id STRING,
            importe DOUBLE,
            `timestamp` STRING,
            event_time AS COALESCE(
                TO_TIMESTAMP(REPLACE(SUBSTRING(`timestamp`, 1, 19), 'T', ' ')),
                TIMESTAMP '1970-01-01 00:00:00'
            ),
            WATERMARK FOR event_time
                AS event_time - INTERVAL '{WATERMARK_DELAY_SECONDS}' SECOND
        )
        WITH (
            'connector' = 'kinesis',
            'stream' = '{KINESIS_STREAM}',
            'aws.region' = '{AWS_REGION}',
            'scan.stream.initpos' = '{STREAM_INITPOS}',
            'format' = 'json',
            'json.ignore-parse-errors' = 'true'
        )
    """)

    # --------------------------------------------------
    # DESTINO: CATALOGO GLUE + TABLA ICEBERG
    # --------------------------------------------------
    # La base lakehouse_db y la tabla (esquema + particionado day(window_start))
    # las crea Terraform; aca solo se registra el catalogo y se apunta a la tabla.
    #
    # Concurrencia: GlueCatalog usa el optimistic locking de Glue por defecto
    # (UpdateTable condicionado al VersionId de la tabla), sin lock externo.
    # Ademas el sink de Iceberg confirma desde un unico committer (paralelismo 1),
    # asi que nunca hay dos commits simultaneos desde este job.

    table_env.execute_sql(f"""
        CREATE CATALOG {ICEBERG_CATALOG} WITH (
            'type' = 'iceberg',
            'catalog-impl' = 'org.apache.iceberg.aws.glue.GlueCatalog',
            'io-impl' = 'org.apache.iceberg.aws.s3.S3FileIO',
            'warehouse' = '{ICEBERG_WAREHOUSE}',
            'client.region' = '{AWS_REGION}',
            'glue.skip-archive' = 'true'
        )
    """)

    # --------------------------------------------------
    # VENTANAS TUMBLING DE 1 MINUTO (event time)
    # --------------------------------------------------

    ventanas = table_env.sql_query("""
        SELECT
            CAST(window_start AS STRING) AS window_start,
            CAST(window_end AS STRING) AS window_end,
            cliente_id,
            COUNT(*) AS total_operaciones,
            CAST(SUM(CASE WHEN event_type = 'compra' THEN 1 ELSE 0 END) AS BIGINT)
                AS cantidad_compras,
            SUM(CASE WHEN event_type = 'compra' THEN importe ELSE 0.0 END)
                AS importe_total_compras,
            AVG(CASE WHEN event_type = 'compra' THEN importe ELSE CAST(NULL AS DOUBLE) END)
                AS importe_promedio_compras
        FROM TABLE(
            TUMBLE(TABLE eventos, DESCRIPTOR(event_time), INTERVAL '1' MINUTE)
        )
        WHERE cliente_id IS NOT NULL
        GROUP BY window_start, window_end, cliente_id
    """)

    # --------------------------------------------------
    # ESTADO POR CLIENTE (KeyedState) Y ESCRITURA
    # --------------------------------------------------

    enriquecido = (
        table_env.to_data_stream(ventanas)
        .key_by(lambda r: r[COL_CLIENTE], key_type=Types.STRING())
        .process(DeteccionPatrones(), output_type=OUTPUT_TYPE)
        .name("deteccion-patrones-por-cliente")
    )

    table_env.create_temporary_view("ventanas_enriquecidas", table_env.from_data_stream(enriquecido))

    logger.info("Iniciando procesamiento de eventos Kinesis hacia %s...", destino)

    # Las ventanas viajan como texto por el DataStream de Python; aca se convierten
    # a TIMESTAMP(6), el tipo `timestamp` de Iceberg sobre el que se particiona.
    result = table_env.execute_sql(f"""
        INSERT INTO {destino}
        SELECT
            CAST(window_start AS TIMESTAMP(6)),
            CAST(window_end AS TIMESTAMP(6)),
            cliente_id,
            total_operaciones,
            cantidad_compras,
            importe_total_compras,
            importe_promedio_compras,
            ventanas_procesadas,
            importe_acumulado,
            variacion_pct,
            alerta
        FROM ventanas_enriquecidas
    """)

    if IS_LOCAL:
        result.wait()


if __name__ == "__main__":
    main()
