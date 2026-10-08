# Explicación simple: qué hicimos y para qué sirve

## La idea general

Hice la analogia con la construccion de un edificio (una **plataforma de datos** en la nube de Amazon, AWS). Antes de poner los muebles (los sistemas que procesan datos en tiempo real), hay que hacer los cimientos: el terreno, las paredes, las llaves y los permisos.

Este proyecto son esos cimientos. Todo está escrito como **código** con una herramienta llamada **Terraform**. En vez de hacer clic en la consola de AWS, escribimos "quiero esto" en archivos, y Terraform lo crea. Ventajas: se puede repetir, revisar, versionar y compartir con un equipo.

## Las 4 piezas

### 1. Backend remoto (carpeta `bootstrap/`)

Terraform lleva una libreta (el **state**) donde anota qué creó. Si esa libreta está solo en tu computadora, es riesgoso: se puede perder y dos personas pueden pisarse.

Por eso la guardamos en AWS:

- **Bucket S3**: la "caja fuerte" donde se guarda la libreta. Está cifrada, con historial de versiones y sin acceso público.
- **Tabla DynamoDB**: un "cartel de ocupado". Si una persona está aplicando cambios, la otra tiene que esperar. Evita choques.

Se crea **una sola vez**, a mano, antes de todo lo demás.

### 2. Red (módulo `network`)

Es una **red privada** propia dentro de AWS (una VPC), como un barrio cerrado.

- Tiene **2 subredes privadas** en zonas de disponibilidad distintas (dos "edificios" separados). Si uno falla, el otro sigue.
- **No tiene salida directa a internet**: nadie de afuera puede entrar.
- Tiene un **S3 Gateway Endpoint**: un pasillo privado hasta S3 (donde se guardan los datos). Así los datos viajan por dentro de AWS, más rápido y sin pagar por un NAT Gateway.

### 3. Identidad y permisos (módulo `identity`)

Son los **roles de IAM**: "carnets" con permisos limitados.

- **Rol de procesamiento**: para los programas que van a procesar datos (Lambda o Flink). Solo puede listar, leer y escribir archivos dentro de **una carpeta específica** del bucket (`streaming/`). Nada más. Es el principio de "mínimo privilegio".
- **Rol de auditoría**: solo **mira**, no puede cambiar nada. Sirve para revisar la cuenta. Además exige MFA (doble verificación) para usarlo.

En ningún lado se usa el permiso comodín `*` ("puede hacer todo").

### 4. Entorno `dev` (carpeta `environments/dev/`)

Es donde se **juntan** las piezas: llama al módulo de red, al de identidad, crea el bucket de datos y le dice a Terraform dónde guardar su libreta. Termina mostrando datos útiles (IDs de la VPC y subredes, ARNs de los roles) que se usarán en la próxima entrega.

## ¿Por qué módulos y entornos?

Los **módulos** son como moldes reutilizables. Si mañana querés un entorno `prod`, copiás la carpeta `dev`, cambiás unos valores (como el rango de IPs) y listo. No hay que reescribir la red ni los roles.

## Resumen de la estructura

```text
bootstrap/          → crea la caja fuerte y el cartel de "ocupado" (una sola vez)
modules/network/    → molde de la red privada
modules/identity/   → molde de los roles y permisos
environments/dev/   → arma todo para el ambiente de desarrollo
PLAN_OUTPUT.md      → el "borrador" de lo que Terraform va a crear (17 recursos)
.tflint.hcl         → reglas del corrector de estilo/errores (tflint)
```

## Cómo se usa (los 3 comandos clave)

```bash
terraform init      # prepara la carpeta y descarga lo necesario
terraform plan      # muestra QUÉ va a crear, sin tocar nada
terraform apply     # lo crea de verdad (pide confirmación)
```

El orden: primero `bootstrap/`, después `environments/dev/`.

## ¿Para qué sirve todo esto al final?

Para tener una base **segura, ordenada y reutilizable** sobre la cual, en las próximas entregas, se construirán los sistemas de datos en tiempo real (Kinesis y Flink) que guardarán la información en el data lake de S3.
