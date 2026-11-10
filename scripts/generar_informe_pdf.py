"""
Genera el documento técnico de la Pre-entrega 6 en PDF.

  docs/checkpoint6/informe.html  (plantilla)  ─┐
  sql/redshift_streaming.sql                   ├─> docs/checkpoint6/informe_generado.html
  docs/evidencias-redshift/*.txt / *.png      ─┘        └─> CheckPoint_Redshift_Gabaldo_Hector.pdf

Marcadores de la plantilla:
  {{SQL}}                 script SQL completo
  {{V:n}} / {{A:n}}       resultado n de validacion.txt / validacion_analista.txt (tabla)
  {{ICE:n}}               bloque n de iceberg_metadata.txt
  {{FILE:ruta}}           archivo de texto como bloque de código
  {{TFAPPLY}}             recursos creados por terraform apply
  {{IMG:archivo|título}}  captura de docs/evidencias-redshift/ (o un recuadro "pendiente")

Sólo usa la biblioteca estándar; el PDF lo imprime Microsoft Edge (o Chrome) en modo headless:

    python scripts/generar_informe_pdf.py
"""

import base64
import html
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
PLANTILLA = RAIZ / "docs" / "checkpoint6" / "informe.html"
GENERADO = RAIZ / "docs" / "checkpoint6" / "informe_generado.html"
EVIDENCIAS = RAIZ / "docs" / "evidencias-redshift"
PDF = RAIZ / "CheckPoint_Redshift_Gabaldo_Hector.pdf"

NAVEGADORES = [
    r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
    r"C:\Program Files\Microsoft\Edge\Application\msedge.exe",
    r"C:\Program Files\Google\Chrome\Application\chrome.exe",
    "msedge",
    "google-chrome",
    "chromium",
]


def leer(ruta):
    return Path(ruta).read_text(encoding="utf-8", errors="replace")


def bloques_runner(texto):
    """Divide la salida de redshift_sql.py en {n: (encabezado, líneas)}."""
    bloques = {}
    actual = None
    for linea in texto.splitlines():
        m = re.match(r"^\[(\d+)/\d+\]\s*(.*)$", linea)
        if m:
            actual = int(m.group(1))
            bloques[actual] = (m.group(2), [])
        elif actual is not None:
            bloques[actual][1].append(linea)
    return bloques


def tabla_html(lineas):
    """Convierte 'a | b' + separador + filas en <table>. Devuelve (html, resto)."""
    filas, resto = [], []
    encabezado = None
    for linea in lineas:
        es_meta = linea.startswith(("OK en", "ERROR", "  ")) or re.match(r"^\(\d+ filas", linea)
        if es_meta or not linea.strip():
            resto.append(linea)
        elif encabezado is None:
            encabezado = [c.strip() for c in linea.split("|")]
        elif re.match(r"^[-+]+$", linea.strip()):
            continue
        else:
            filas.append([c.strip() for c in linea.split("|")])

    if encabezado is None:
        return "", resto
    out = ['<table class="res"><thead><tr>']
    out += [f"<th>{html.escape(c)}</th>" for c in encabezado]
    out.append("</tr></thead><tbody>")
    for f in filas:
        clase = ' class="nulo"' if all(v == "NULL" for v in f) else ""
        out.append(f"<tr{clase}>" + "".join(f"<td>{html.escape(v)}</td>" for v in f) + "</tr>")
    out.append("</tbody></table>")
    return "".join(out), resto


def resultado(texto, n, fuente):
    bloques = bloques_runner(texto)
    if n not in bloques:
        return f'<p class="falta">Resultado {n} no encontrado en {fuente}</p>'
    encabezado, lineas = bloques[n]
    tabla, resto = tabla_html(lineas)
    errores = [l for l in resto if l.startswith("ERROR")]
    meta = [l for l in resto if l.startswith(("OK en", "("))]
    partes = [f'<div class="resultado"><div class="sql-head">{html.escape(encabezado)}</div>']
    if tabla:
        partes.append(tabla)
    for e in errores:
        partes.append(f'<div class="error">{html.escape(e)}</div>')
    if meta:
        partes.append(f'<div class="meta">{html.escape(" · ".join(m.strip() for m in meta))}</div>')
    partes.append("</div>")
    return "".join(partes)


def bloque_iceberg(n):
    texto = leer(EVIDENCIAS / "iceberg_metadata.txt")
    bloques = re.split(r"^== ", texto, flags=re.M)[1:]
    if n > len(bloques):
        return f'<p class="falta">Bloque {n} no encontrado</p>'
    titulo, _, cuerpo = bloques[n - 1].partition("\n")
    lineas = [l for l in cuerpo.splitlines() if l.strip()]
    if lineas and " | " in lineas[0]:
        enc = [c.strip() for c in lineas[0].split(" | ")]
        filas = [[c.strip() for c in l.split(" | ")] for l in lineas[1:]]
        tabla = ['<table class="res"><thead><tr>'] + [f"<th>{html.escape(c)}</th>" for c in enc] + ["</tr></thead><tbody>"]
        tabla += ["<tr>" + "".join(f"<td>{html.escape(v)}</td>" for v in f) + "</tr>" for f in filas]
        tabla.append("</tbody></table>")
        cuerpo_html = "".join(tabla)
    else:
        cuerpo_html = f"<pre>{html.escape(chr(10).join(lineas))}</pre>"
    return f'<div class="resultado"><div class="sql-head">{html.escape(titulo)}</div>{cuerpo_html}</div>'


def tf_apply():
    texto = leer(EVIDENCIAS / "terraform_apply.txt")
    lineas = [l for l in texto.splitlines() if "Creation complete" in l or "Apply complete" in l]
    lineas = [re.sub(r"\s*\[id=.*\]$", "", l) for l in lineas]
    return "<pre>" + html.escape("\n".join(lineas)) + "</pre>"


def imagen(spec):
    archivo, _, titulo = spec.partition("|")
    ruta = EVIDENCIAS / archivo.strip()
    if ruta.exists():
        mime = "image/png" if ruta.suffix.lower() == ".png" else "image/jpeg"
        datos = base64.b64encode(ruta.read_bytes()).decode()
        return (f'<figure><img src="data:{mime};base64,{datos}" alt="{html.escape(titulo)}">'
                f"<figcaption>{html.escape(titulo)}</figcaption></figure>")
    return (f'<figure class="pendiente"><div>Captura pendiente: <code>docs/evidencias-redshift/{html.escape(archivo.strip())}</code></div>'
            f"<figcaption>{html.escape(titulo)}</figcaption></figure>")


def renderizar():
    plantilla = leer(PLANTILLA)
    validacion = leer(EVIDENCIAS / "validacion.txt")
    analista = leer(EVIDENCIAS / "validacion_analista.txt")

    reemplazos = [
        (r"\{\{SQL\}\}", lambda m: "<pre class=\"sql\">" + html.escape(leer(RAIZ / "sql" / "redshift_streaming.sql")) + "</pre>"),
        (r"\{\{V:(\d+)\}\}", lambda m: resultado(validacion, int(m.group(1)), "validacion.txt")),
        (r"\{\{A:(\d+)\}\}", lambda m: resultado(analista, int(m.group(1)), "validacion_analista.txt")),
        (r"\{\{ICE:(\d+)\}\}", lambda m: bloque_iceberg(int(m.group(1)))),
        (r"\{\{FILE:([^}]+)\}\}", lambda m: "<pre>" + html.escape(leer(RAIZ / m.group(1)).strip()) + "</pre>"),
        (r"\{\{TFAPPLY\}\}", lambda m: tf_apply()),
        (r"\{\{IMG:([^}]+)\}\}", lambda m: imagen(m.group(1))),
    ]
    for patron, funcion in reemplazos:
        plantilla = re.sub(patron, funcion, plantilla)

    pendientes = len(re.findall(r'class="pendiente"', plantilla))
    GENERADO.write_text(plantilla, encoding="utf-8")
    return pendientes


def navegador():
    for candidato in NAVEGADORES:
        if os.path.isabs(candidato) and os.path.exists(candidato):
            return candidato
        if not os.path.isabs(candidato) and shutil.which(candidato):
            return shutil.which(candidato)
    sys.exit("No se encontró Edge ni Chrome para imprimir el PDF.")


def main():
    pendientes = renderizar()
    exe = navegador()
    perfil = RAIZ / "docs" / "checkpoint6" / ".perfil-navegador"
    cmd = [
        exe,
        "--headless=new",
        "--disable-gpu",
        "--no-pdf-header-footer",
        f"--user-data-dir={perfil}",
        f"--print-to-pdf={PDF}",
        GENERADO.as_uri(),
    ]
    subprocess.run(cmd, check=True, capture_output=True, timeout=180)
    shutil.rmtree(perfil, ignore_errors=True)
    print(f"PDF generado: {PDF}")
    if pendientes:
        print(f"Atención: {pendientes} capturas de pantalla pendientes (ver recuadros en el PDF).")


if __name__ == "__main__":
    main()
