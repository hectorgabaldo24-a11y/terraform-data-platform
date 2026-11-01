# Permisos del escritor (rol de ejecución de Managed Flink) sobre el lakehouse:
#
# glue:GetDatabase / GetTable(s)       -> resolver lakehouse_db.ventanas_clientes
# glue:CreateTable / UpdateTable       -> commits de Iceberg (UpdateTable con VersionId = optimistic lock)
# s3:Get/Put/DeleteObject + multipart  -> archivos de datos (Parquet) y de metadata en el warehouse
#
# Todo queda acotado a la base lakehouse_db, sus tablas y el prefijo del warehouse.

data "aws_iam_policy_document" "lakehouse_writer" {

  statement {
    sid    = "GlueCatalogReadWrite"
    effect = "Allow"
    actions = [
      "glue:GetDatabase",
      "glue:GetDatabases",
      "glue:GetTable",
      "glue:GetTables",
      "glue:CreateTable",
      "glue:UpdateTable",
    ]
    resources = [
      "${local.glue_arn_prefix}:catalog",
      "${local.glue_arn_prefix}:database/${var.database_name}",
      "${local.glue_arn_prefix}:table/${var.database_name}/*",
    ]
  }

  statement {
    sid       = "ListWarehousePrefix"
    effect    = "Allow"
    actions   = ["s3:ListBucket", "s3:GetBucketLocation"]
    resources = ["arn:aws:s3:::${var.bucket_name}"]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = [var.warehouse_prefix, "${var.warehouse_prefix}/*"]
    }
  }

  statement {
    sid    = "ReadWriteWarehouseObjects"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:AbortMultipartUpload",
      "s3:ListMultipartUploadParts",
    ]
    resources = ["arn:aws:s3:::${var.bucket_name}/${var.warehouse_prefix}/*"]
  }
}

resource "aws_iam_policy" "lakehouse_writer" {
  name        = "${var.name_prefix}-lakehouse-writer"
  description = "Glue Data Catalog (lakehouse_db) y S3 del warehouse Iceberg para Managed Flink"
  policy      = data.aws_iam_policy_document.lakehouse_writer.json

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "lakehouse_writer" {
  role       = var.writer_role_name
  policy_arn = aws_iam_policy.lakehouse_writer.arn
}
