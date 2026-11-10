"""
Productor de eventos de prueba para data-platform-dev-events.

Sin argumentos se comporta como en la Pre-entrega 2: un lote de 100 eventos.
Para la Pre-entrega 4 (Flink) conviene generar trafico durante varios minutos,
asi las ventanas de 1 minuto se cierran y el watermark avanza:

    python scripts/kinesis_producer.py --lotes 30 --registros 20 --pausa 10 --max-retraso 20

--max-retraso resta a cada `timestamp` un retraso aleatorio (0..N segundos)
para simular eventos que llegan desordenados por la red.

--anomalias P (Pre-entrega 6) reemplaza ~P% de los eventos por registros con
"schema drift" para validar la vista materializada de Redshift:

    python scripts/kinesis_producer.py --lotes 10 --registros 20 --pausa 10 --anomalias 10
"""

import argparse
import json
import random
import time
from datetime import datetime, timedelta, timezone

import boto3

REGION = "us-east-1"
STREAM_NAME = "data-platform-dev-events"
CLIENTES = 10


def parse_args():
    parser = argparse.ArgumentParser(description="Envia eventos JSON a Kinesis")
    parser.add_argument("--registros", type=int, default=100, help="Eventos por lote")
    parser.add_argument("--lotes", type=int, default=1, help="Cantidad de lotes")
    parser.add_argument("--pausa", type=float, default=5, help="Segundos entre lotes")
    parser.add_argument(
        "--max-retraso",
        type=int,
        default=0,
        help="Retraso aleatorio maximo (segundos) aplicado al timestamp del evento",
    )
    parser.add_argument(
        "--anomalias",
        type=float,
        default=0,
        help="Porcentaje de eventos con schema drift (JSON roto, tipos o campos cambiados)",
    )
    return parser.parse_args()


def construir_evento(event_id, max_retraso):
    retraso = random.randint(0, max_retraso) if max_retraso > 0 else 0
    momento = datetime.now(timezone.utc) - timedelta(seconds=retraso)

    return {
        "event_id": event_id,
        "event_type": "compra" if event_id % 2 == 0 else "consulta",
        "cliente_id": f"cliente-{((event_id - 1) % CLIENTES) + 1:03d}",
        "importe": round(random.uniform(10, 500), 2),
        "timestamp": momento.isoformat(),
    }


# Variantes de schema drift. Las cuatro primeras deben quedar marcadas como
# inválidas en Redshift; la última (campo nuevo) es una evolución compatible.
ANOMALIAS = [
    "json_roto",          # no es JSON
    "importe_texto",      # importe llega como string no numérico
    "sin_cliente",        # falta un campo obligatorio
    "timestamp_invalido", # timestamp con formato desconocido
    "campo_nuevo",        # campo adicional: válido, se ignora
]


def aplicar_anomalia(evento, tipo):
    if tipo == "json_roto":
        return '{"event_id": ' + str(evento["event_id"]) + ', "cliente_id": "cliente-x"'
    if tipo == "importe_texto":
        evento["importe"] = "N/A"
    elif tipo == "sin_cliente":
        del evento["cliente_id"]
    elif tipo == "timestamp_invalido":
        evento["timestamp"] = "10/11/2026 25:61"
    elif tipo == "campo_nuevo":
        evento["canal"] = "app-movil"
    return json.dumps(evento)


def enviar(client, records):
    pending = records
    delivered = 0

    while pending:
        response = client.put_records(
            StreamName=STREAM_NAME,
            Records=pending,
        )

        failed = response["FailedRecordCount"]
        delivered += len(pending) - failed

        if failed == 0:
            pending = []
        else:
            pending = [
                record
                for record, result in zip(pending, response["Records"])
                if "ErrorCode" in result
            ]
            print(f"Registros pendientes: {len(pending)}. Reintentando...")
            time.sleep(2)

    return delivered


def main():
    args = parse_args()
    client = boto3.client("kinesis", region_name=REGION)

    event_id = 0
    delivered = 0
    anomalias = {}

    for lote in range(1, args.lotes + 1):
        records = []
        for _ in range(args.registros):
            event_id += 1
            event = construir_evento(event_id, args.max_retraso)
            partition_key = event["cliente_id"]
            cuerpo = json.dumps(event)
            if args.anomalias > 0 and random.uniform(0, 100) < args.anomalias:
                tipo = random.choice(ANOMALIAS)
                cuerpo = aplicar_anomalia(event, tipo)
                anomalias[tipo] = anomalias.get(tipo, 0) + 1
            records.append({
                "Data": (cuerpo + "\n").encode("utf-8"),
                "PartitionKey": partition_key,
            })

        delivered += enviar(client, records)
        print(f"Lote {lote}/{args.lotes}: {len(records)} eventos enviados")

        if lote < args.lotes:
            time.sleep(args.pausa)

    print(f"Proceso terminado. Registros enviados: {delivered}")
    print(f"Stream: {STREAM_NAME}")
    print(f"Claves de partición: {CLIENTES} clientes diferentes")
    if anomalias:
        print(f"Eventos con schema drift: {sum(anomalias.values())} {anomalias}")


if __name__ == "__main__":
    main()
