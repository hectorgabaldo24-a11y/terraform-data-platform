import json
import time
from datetime import datetime, timezone

import boto3

REGION = "us-east-1"
STREAM_NAME = "data-platform-dev-events"
TOTAL_RECORDS = 100


def main():
    client = boto3.client("kinesis", region_name=REGION)
    records = []

    for i in range(1, TOTAL_RECORDS + 1):
        event = {
            "event_id": i,
            "event_type": "compra" if i % 2 == 0 else "consulta",
            "cliente_id": f"cliente-{((i - 1) % 10) + 1:03d}",
            "importe": round(100 + i * 1.75, 2),
            "timestamp": datetime.now(timezone.utc).isoformat(),
        }

        records.append({
            
            "Data": (json.dumps(event) + "\n").encode("utf-8"),
            "PartitionKey": event["cliente_id"],
        })

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

    print(f"Proceso terminado. Registros enviados: {delivered}")
    print(f"Stream: {STREAM_NAME}")
    print("Claves de partición: 10 clientes diferentes")


if __name__ == "__main__":
    main()
