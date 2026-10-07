# Terraform Data Platform

Proyecto de práctica para diseñar el scaffolding inicial de una plataforma de datos sobre AWS utilizando Terraform.

La infraestructura evolucionará posteriormente para incorporar servicios como Amazon Kinesis y Apache Flink.

## Estructura del proyecto

```text
terraform-data-platform/
│
├── provider.tf
├── main.tf
├── variables.tf
├── outputs.tf
├── terraform.tfvars
├── .gitignore
└── README.md
```

### provider.tf

Define la versión mínima de Terraform y los providers utilizados por el proyecto.

Actualmente se utiliza el provider de AWS.

### main.tf

Contiene los recursos principales de infraestructura.

En esta primera etapa se utiliza un bucket S3 como recurso de ejemplo.

### variables.tf

Contiene las variables configurables del proyecto.

Las variables actuales son:

* `region`: región de AWS.
* `project_name`: nombre del proyecto.
* `environment`: ambiente de despliegue.

Cada variable posee una descripción y un tipo de dato explícito para facilitar el mantenimiento.

### outputs.tf

Define los valores que Terraform mostrará como resultado del despliegue.

Actualmente se muestra el nombre del bucket S3 creado.

### terraform.tfvars

Contiene los valores utilizados para las variables del proyecto.

En esta práctica contiene valores de ejemplo para la región, proyecto y ambiente.

En proyectos reales, este archivo no debería contener secretos ni credenciales y normalmente se gestiona de manera diferente según la estrategia de configuración adoptada.

### .gitignore

Evita versionar archivos temporales de Terraform, principalmente:

* `.terraform/`
* archivos `.tfstate`
* logs y archivos temporales
* archivos específicos del IDE

El Terraform state no debe almacenarse en el repositorio Git.

## Convención de nombres

La convención utilizada para los recursos sigue el siguiente patrón:

```text
<project_name>-<environment>-<resource>
```

Por ejemplo:

```text
data-platform-dev-bucket
```

De esta manera podemos identificar rápidamente:

* `data-platform`: proyecto.
* `dev`: ambiente.
* `bucket`: tipo de recurso.

Esta convención permitirá posteriormente diferenciar recursos de desarrollo, testing y producción.

## Inicialización

Para inicializar el proyecto ejecutar:

```bash
terraform init
```

Este comando descarga los providers necesarios y prepara el directorio de trabajo de Terraform.

## Validación

Para validar la configuración:

```bash
terraform validate
```

También se puede utilizar:

```bash
terraform fmt
```

para aplicar el formato estándar de Terraform.

## Plan

Para visualizar los cambios que Terraform realizaría:

```bash
terraform plan
```

## Aplicación

Para crear la infraestructura:

```bash
terraform apply
```

Terraform solicitará confirmación antes de realizar los cambios.

También se puede utilizar:

```bash
terraform apply -auto-approve
```

aunque se recomienda evitar `-auto-approve` en ambientes productivos.

## ¿Por qué separar los archivos?

Aunque Terraform permite colocar toda la configuración en un único `main.tf`, separar la configuración por responsabilidad facilita el mantenimiento y la escalabilidad.

La separación utilizada es:

```text
provider.tf     → configuración de Terraform y providers
variables.tf    → parámetros configurables
main.tf         → recursos de infraestructura
outputs.tf      → información generada por Terraform
terraform.tfvars → valores de configuración
```

Esta organización facilita que otros integrantes del equipo puedan localizar rápidamente cada parte de la infraestructura.

A medida que el proyecto crezca, los recursos también podrán dividirse en módulos y archivos específicos, por ejemplo:

```text
kinesis.tf
flink.tf
s3.tf
iam.tf
network.tf
```

## Próximos pasos

La evolución prevista de esta plataforma es incorporar:

1. Amazon S3.
2. Amazon Kinesis.
3. Procesamiento con Apache Flink.
4. IAM y políticas de acceso.
5. Networking.
6. Observabilidad.
7. Separación de ambientes.
8. Backend remoto para Terraform State.

El objetivo final es construir una plataforma de datos reproducible y administrada como infraestructura como código.
