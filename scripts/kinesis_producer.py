"""
Productor de eventos de prueba para data-platform-dev-events.

Sin argumentos se comporta como en la Pre-entrega 2: un lote de 100 eventos.
Para la Pre-entrega 4 (Flink) conviene generar trafico durante varios minutos,
asi las ventanas de 1 minuto se cierran y el watermark avanza:

    python scripts/kinesis_producer.py --lotes 30 --registros 20 --pausa 10 --max-retraso 20

--max-retraso resta a cada `timestamp` un retraso aleatorio (0..N segundos)
para simular eventos que llegan desordenados por la red.
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

    for lote in range(1, args.lotes + 1):
        records = []
        for _ in range(args.registros):
            event_id += 1
            event = construir_evento(event_id, args.max_retraso)
            records.append({
                "Data": (json.dumps(event) + "\n").encode("utf-8"),
                "PartitionKey": event["cliente_id"],
            })

        delivered += enviar(client, records)
        print(f"Lote {lote}/{args.lotes}: {len(records)} eventos enviados")

        if lote < args.lotes:
            time.sleep(args.pausa)

    print(f"Proceso terminado. Registros enviados: {delivered}")
    print(f"Stream: {STREAM_NAME}")
    print(f"Claves de partición: {CLIENTES} clientes diferentes")


if __name__ == "__main__":
    main()
