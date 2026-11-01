# Permisos específicos de Managed Flink, agregados al rol de procesamiento del
# módulo identity (que ya tiene la lectura de Kinesis):
#
# s3:GetObject / ListBucket          -> descargar el ZIP (flink/app/*)
# s3:PutObject y multipart upload    -> escribir resultados (flink/resultados/*)
# logs:Describe* / PutLogEvents      -> logs de la aplicación en CloudWatch
# ec2:*NetworkInterface* (opcional)  -> solo si la aplicación corre dentro de la VPC
#
# La política no concede permisos para crear buckets, borrar fuera del prefijo
# de resultados ni administrar otros servicios.

data "aws_iam_policy_document" "flink_access" {

  # Descargar el ZIP de la aplicación.
  statement {
    sid       = "ReadFlinkApplicationArtifact"
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:GetObjectVersion"]
    resources = ["arn:aws:s3:::${var.artifact_bucket}/flink/app/*"]
  }

  # Listar solo los prefijos de Flink.
  statement {
    sid       = "ListFlinkPrefixes"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::${var.artifact_bucket}"]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["flink/app/*", var.output_prefix, "${var.output_prefix}/*"]
    }
  }

  # El sink de archivos escribe con multipart upload y confirma en cada checkpoint.
  statement {
    sid    = "WriteFlinkResults"
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:DeleteObject",
      "s3:AbortMultipartUpload",
      "s3:ListMultipartUploadParts",
    ]
    resources = ["arn:aws:s3:::${var.artifact_bucket}/${var.output_prefix}/*"]
  }

  # Consultar los grupos de logs (la API no admite restringir por recurso).
  statement {
    sid       = "DescribeCloudWatchLogGroups"
    effect    = "Allow"
    actions   = ["logs:DescribeLogGroups"]
    resources = ["*"]
  }

  # Consultar los streams del grupo de logs de esta aplicación.
  statement {
    sid       = "DescribeCloudWatchLogStreams"
    effect    = "Allow"
    actions   = ["logs:DescribeLogStreams"]
    resources = [aws_cloudwatch_log_group.flink.arn, "${aws_cloudwatch_log_group.flink.arn}:*"]
  }

  # Escribir logs únicamente en el stream creado para Flink.
  statement {
    sid       = "WriteFlinkCloudWatchLogs"
    effect    = "Allow"
    actions   = ["logs:PutLogEvents"]
    resources = [aws_cloudwatch_log_stream.flink.arn]
  }

  # Solo si la aplicación se conecta a la VPC: Managed Flink crea ENIs en las subredes.
  dynamic "statement" {
    for_each = local.use_vpc ? [1] : []

    content {
      sid    = "VpcNetworkInterfaces"
      effect = "Allow"
      actions = [
        "ec2:DescribeVpcs",
        "ec2:DescribeSubnets",
        "ec2:DescribeSecurityGroups",
        "ec2:DescribeDhcpOptions",
        "ec2:DescribeNetworkInterfaces",
        "ec2:CreateNetworkInterface",
        "ec2:CreateNetworkInterfacePermission",
        "ec2:DeleteNetworkInterface",
      ]
      resources = ["*"]
    }
  }
}

resource "aws_iam_policy" "flink_access" {
  name        = "${var.project_name}-${var.environment}-flink-access"
  description = "Permisos acotados de S3 y CloudWatch para Managed Flink"
  policy      = data.aws_iam_policy_document.flink_access.json

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "flink_access" {
  role       = var.execution_role_name
  policy_arn = aws_iam_policy.flink_access.arn
}
