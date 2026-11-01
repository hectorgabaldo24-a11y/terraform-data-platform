# Permisos específicos de Managed Flink, agregados al rol de procesamiento del
# módulo identity (que ya tiene la lectura de Kinesis):
#
# s3:GetObject / ListBucket          -> descargar el ZIP (flink/app/*)
# logs:Describe* / PutLogEvents      -> logs de la aplicación en CloudWatch
# ec2:*NetworkInterface* (opcional)  -> solo si la aplicación corre dentro de la VPC
#
# La escritura en el lakehouse (Glue + S3 del warehouse) la concede el módulo
# lakehouse. Esta política no permite crear buckets ni administrar otros servicios.

data "aws_iam_policy_document" "flink_access" {

  # Descargar el ZIP de la aplicación.
  statement {
    sid       = "ReadFlinkApplicationArtifact"
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:GetObjectVersion"]
    resources = ["arn:aws:s3:::${var.artifact_bucket}/flink/app/*"]
  }

  # Listar solo el prefijo del artefacto.
  statement {
    sid       = "ListFlinkArtifactPrefix"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::${var.artifact_bucket}"]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["flink/app/*"]
    }
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
