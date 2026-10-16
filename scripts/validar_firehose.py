import gzip
import json
from pathlib import Path

folder = Path("evidencias/firehose_prueba2")
files = sorted(folder.glob("*2026-10-16-02-06-54*.gz"))

total = 0
invalid = 0
ids = []

for path in files:
    with gzip.open(path, "rt", encoding="utf-8") as f:
        for line in f:
            if not line.strip():
                continue
            try:
                event = json.loads(line)
                if isinstance(event, dict) and "event_id" in event:
                    total += 1
                    ids.append(event["event_id"])
                else:
                    invalid += 1
            except json.JSONDecodeError:
                invalid += 1

print(f"Archivos nuevos: {len(files)}")
print(f"Registros JSON validos: {total}")
print(f"Lineas invalidas: {invalid}")
print(f"IDs distintos: {len(set(ids))}")
print(f"IDs del 1 al 100 completos: {set(ids) == set(range(1, 101))}")
