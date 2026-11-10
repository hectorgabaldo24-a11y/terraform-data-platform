"""
Ejecuta SQL en Redshift Serverless a través de la Redshift Data API.

No abre conexiones de red al workgroup (que no es público) ni usa contraseñas
en texto plano: la Data API autentica con IAM.

  * Por defecto se conecta como administrador con el secreto que Redshift
    administra en Secrets Manager (--secret-arn, lo da `terraform output`).
  * Con --role-arn asume un rol IAM (p. ej. el de analistas) y se conecta con
    credenciales temporales: el usuario de base de datos es IAMR:<rol>.

Ejemplos:

    # Script completo (se separa por sentencias; respeta los cuerpos $$ ... $$)
    python scripts/redshift_sql.py --secret-arn <arn> --file sql/redshift_streaming.sql

    # Sólo una sección del script
    python scripts/redshift_sql.py --secret-arn <arn> --file sql/redshift_streaming.sql --seccion validacion

    # Una consulta
    python scripts/redshift_sql.py --secret-arn <arn> --sql "SELECT COUNT(*) FROM stream.mv_eventos"

    # Como analista
    python scripts/redshift_sql.py --profile terraform-dev \
        --role-arn arn:aws:iam::<cuenta>:role/data-platform-dev-redshift-analyst \
        --sql "SELECT * FROM analytics.mv_ventas_por_minuto LIMIT 5"
"""

import argparse
import re
import sys
import time

import boto3

REGION = "us-east-1"
WORKGROUP = "data-platform-dev-analytics"
DATABASE = "analytics"


def parse_args():
    parser = argparse.ArgumentParser(description="Ejecuta SQL en Redshift vía Data API")
    origen = parser.add_mutually_exclusive_group(required=True)
    origen.add_argument("--file", help="Archivo .sql con una o más sentencias")
    origen.add_argument("--sql", help="Sentencia SQL")
    parser.add_argument("--secret-arn", help="Secreto del administrador (terraform output redshift_admin_secret_arn)")
    parser.add_argument("--role-arn", help="Rol IAM a asumir (conexión con credenciales temporales)")
    parser.add_argument("--profile", help="Perfil de AWS CLI")
    parser.add_argument("--workgroup", default=WORKGROUP)
    parser.add_argument("--database", default=DATABASE)
    parser.add_argument("--max-rows", type=int, default=50, help="Filas a mostrar por resultado")
    parser.add_argument("--continue-on-error", action="store_true", help="No detenerse ante un error")
    parser.add_argument("--echo", action="store_true", help="Mostrar cada sentencia antes de ejecutarla")
    parser.add_argument(
        "--seccion",
        action="append",
        help="Ejecutar sólo estas secciones ('-- @seccion: <nombre>'); se puede repetir. "
        "Sin --seccion se ejecutan todas menos las manuales",
    )
    return parser.parse_args()


# Secciones que sólo se ejecutan si se piden explícitamente con --seccion.
SECCIONES_MANUALES = {"validacion-analista", "reset"}


def split_sections(text):
    """Devuelve [(nombre, texto)] según los marcadores '-- @seccion: <nombre>'."""
    secciones, nombre, buf = [], "inicio", []
    for linea in text.splitlines(keepends=True):
        m = re.match(r"\s*--\s*@seccion:\s*(\S+)", linea)
        if m:
            secciones.append((nombre, "".join(buf)))
            nombre, buf = m.group(1), []
        else:
            buf.append(linea)
    secciones.append((nombre, "".join(buf)))
    return secciones


def split_statements(text):
    """Separa por ';' fuera de comentarios, literales y bloques $$."""
    statements, buf = [], []
    i, n = 0, len(text)
    in_single = in_dollar = in_line_comment = in_block_comment = False

    while i < n:
        c = text[i]
        nxt = text[i + 1] if i + 1 < n else ""

        if in_line_comment:
            if c == "\n":
                in_line_comment = False
            buf.append(c)
        elif in_block_comment:
            buf.append(c)
            if c == "*" and nxt == "/":
                buf.append(nxt)
                i += 1
                in_block_comment = False
        elif in_single:
            buf.append(c)
            if c == "'":
                in_single = False
        elif in_dollar:
            buf.append(c)
            if c == "$" and nxt == "$":
                buf.append(nxt)
                i += 1
                in_dollar = False
        elif c == "-" and nxt == "-":
            in_line_comment = True
            buf.append(c)
        elif c == "/" and nxt == "*":
            in_block_comment = True
            buf.append(c)
        elif c == "'":
            in_single = True
            buf.append(c)
        elif c == "$" and nxt == "$":
            in_dollar = True
            buf.append("$$")
            i += 1
        elif c == ";":
            statements.append("".join(buf))
            buf = []
        else:
            buf.append(c)
        i += 1

    statements.append("".join(buf))
    # Descarta fragmentos que sólo tienen comentarios o espacios.
    limpias = []
    for s in statements:
        sin_comentarios = re.sub(r"--[^\n]*", "", s)
        sin_comentarios = re.sub(r"/\*.*?\*/", "", sin_comentarios, flags=re.S)
        if sin_comentarios.strip():
            limpias.append(s.strip())
    return limpias


def data_api_client(args):
    session = boto3.Session(profile_name=args.profile, region_name=REGION)
    if args.role_arn:
        creds = session.client("sts").assume_role(
            RoleArn=args.role_arn, RoleSessionName="redshift-sql"
        )["Credentials"]
        session = boto3.Session(
            aws_access_key_id=creds["AccessKeyId"],
            aws_secret_access_key=creds["SecretAccessKey"],
            aws_session_token=creds["SessionToken"],
            region_name=REGION,
        )
    return session.client("redshift-data")


def valor(campo):
    if campo.get("isNull"):
        return "NULL"
    for clave in ("stringValue", "longValue", "doubleValue", "booleanValue"):
        if clave in campo:
            return str(campo[clave])
    return str(campo)


def imprimir_resultado(client, statement_id, max_rows):
    resultado = client.get_statement_result(Id=statement_id)
    columnas = [c["name"] for c in resultado["ColumnMetadata"]]
    filas = [[valor(c) for c in r] for r in resultado["Records"]]
    total = resultado.get("TotalNumRows", len(filas))
    filas = filas[:max_rows]

    anchos = [len(c) for c in columnas]
    for fila in filas:
        anchos = [max(a, len(v)) for a, v in zip(anchos, fila)]
    linea = " | ".join(c.ljust(a) for c, a in zip(columnas, anchos))
    print(linea)
    print("-+-".join("-" * a for a in anchos))
    for fila in filas:
        print(" | ".join(v.ljust(a) for v, a in zip(fila, anchos)))
    print(f"({total} filas{', se muestran ' + str(max_rows) if total > max_rows else ''})")


def ejecutar(client, args, sql):
    kwargs = {"WorkgroupName": args.workgroup, "Database": args.database, "Sql": sql}
    if args.secret_arn and not args.role_arn:
        kwargs["SecretArn"] = args.secret_arn
    statement_id = client.execute_statement(**kwargs)["Id"]

    while True:
        desc = client.describe_statement(Id=statement_id)
        if desc["Status"] in ("FINISHED", "FAILED", "ABORTED"):
            break
        time.sleep(0.5)

    if desc["Status"] != "FINISHED":
        print(f"ERROR ({desc['Status']}): {desc.get('Error')}")
        return False

    segundos = desc["Duration"] / 1e9
    if desc.get("HasResultSet"):
        imprimir_resultado(client, statement_id, args.max_rows)
    print(f"OK en {segundos:.2f} s (filas afectadas: {desc.get('ResultRows', 0)})")
    return True


def main():
    args = parse_args()
    if not args.secret_arn and not args.role_arn:
        sys.exit("Indicar --secret-arn (administrador) o --role-arn (rol IAM).")

    client = data_api_client(args)
    if args.file:
        with open(args.file, encoding="utf-8") as f:
            secciones = split_sections(f.read())
        nombres = {n for n, _ in secciones}
        for pedida in args.seccion or []:
            if pedida not in nombres:
                sys.exit(f"Sección desconocida: {pedida}. Disponibles: {sorted(nombres)}")
        sentencias = []
        for nombre, texto in secciones:
            elegida = nombre in args.seccion if args.seccion else nombre not in SECCIONES_MANUALES
            if elegida:
                sentencias.extend(split_statements(texto))
    else:
        sentencias = [args.sql]

    errores = 0
    for n, sql in enumerate(sentencias, 1):
        primera = next(l for l in sql.splitlines() if l.strip() and not l.strip().startswith("--"))
        print(f"\n[{n}/{len(sentencias)}] {primera.strip()[:100]}")
        if args.echo:
            print(sql)
        if not ejecutar(client, args, sql):
            errores += 1
            if not args.continue_on_error:
                sys.exit(1)

    if errores:
        sys.exit(f"{errores} sentencias con error")


if __name__ == "__main__":
    main()
