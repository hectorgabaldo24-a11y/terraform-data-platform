# Empaqueta la aplicacion PyFlink para Managed Service for Apache Flink.
#
# Resultado: flink-app/flink-app.zip con la estructura que espera el servicio
#   main.py
#   lib/pyflink-dependencies.jar   (conector Kinesis + dependencias, generado con Maven)
#
# Uso (desde cualquier carpeta):
#   .\flink-app\build.ps1              # compila el JAR y arma el ZIP
#   .\flink-app\build.ps1 -SkipMaven   # reutiliza target/pyflink-dependencies.jar

param(
    [switch]$SkipMaven
)

$ErrorActionPreference = "Stop"
Push-Location $PSScriptRoot
try {

$jar = Join-Path $PSScriptRoot "target\pyflink-dependencies.jar"
$zipPath = Join-Path $PSScriptRoot "flink-app.zip"

if (-not $SkipMaven) {
    if (Get-Command mvn -ErrorAction SilentlyContinue) {
        mvn -q clean package
    }
    elseif (Get-Command docker -ErrorAction SilentlyContinue) {
        # Sin Maven local: se compila dentro de un contenedor con JDK 11.
        docker run --rm -v "${PSScriptRoot}:/app" -w /app maven:3.9.9-eclipse-temurin-11 mvn -q clean package
    }
    else {
        throw "Se necesita Maven o Docker para generar el JAR de dependencias."
    }
    if ($LASTEXITCODE -ne 0) { throw "Fallo la compilacion con Maven." }
}

if (-not (Test-Path $jar)) {
    throw "No existe $jar. Ejecutar sin -SkipMaven."
}

if (Test-Path $zipPath) { Remove-Item $zipPath -Force }

# Se arma el ZIP con .NET para garantizar separadores '/' en las rutas internas
# (Compress-Archive de PowerShell 5.1 puede generar '\', que Linux no resuelve).
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$zip = [System.IO.Compression.ZipFile]::Open($zipPath, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, (Join-Path $PSScriptRoot "src\main.py"), "main.py") | Out-Null
    [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $jar, "lib/pyflink-dependencies.jar") | Out-Null
}
finally {
    $zip.Dispose()
}

$sizeMb = [math]::Round((Get-Item $zipPath).Length / 1MB, 1)
Write-Host "Generado $zipPath ($sizeMb MB)"

}
finally {
    Pop-Location
}
