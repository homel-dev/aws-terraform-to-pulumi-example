data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "application" {
  name               = "${local.prefix}-app"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
}

resource "aws_iam_role" "database" {
  name               = "${local.prefix}-db"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
}

resource "aws_iam_role_policy_attachment" "application_ssm" {
  count      = local.config.enable_ssm ? 1 : 0
  role       = aws_iam_role.application.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "database_ssm" {
  count      = local.config.enable_ssm ? 1 : 0
  role       = aws_iam_role.database.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

data "aws_iam_policy_document" "application_secret" {
  statement {
    effect = "Allow"
    actions = [
      "secretsmanager:DescribeSecret",
      "secretsmanager:GetSecretValue",
    ]
    resources = ["arn:aws:secretsmanager:${local.config.region}:${data.aws_caller_identity.current.account_id}:secret:${local.prefix}/database-*"]
  }
}

resource "aws_iam_role_policy" "application_secret" {
  name   = "${local.prefix}-db-secret-read"
  role   = aws_iam_role.application.id
  policy = data.aws_iam_policy_document.application_secret.json
}

data "aws_iam_policy_document" "database_secret" {
  statement {
    effect = "Allow"
    actions = [
      "secretsmanager:DescribeSecret",
      "secretsmanager:GetSecretValue",
      "secretsmanager:PutSecretValue",
    ]
    resources = ["arn:aws:secretsmanager:${local.config.region}:${data.aws_caller_identity.current.account_id}:secret:${local.prefix}/database-*"]
  }

  statement {
    effect    = "Allow"
    actions   = ["secretsmanager:GetRandomPassword"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "database_secret" {
  name   = "${local.prefix}-db-secret-bootstrap"
  role   = aws_iam_role.database.id
  policy = data.aws_iam_policy_document.database_secret.json
}

resource "aws_iam_instance_profile" "application" {
  name = "${local.prefix}-app"
  role = aws_iam_role.application.name
}

resource "aws_iam_instance_profile" "database" {
  name = "${local.prefix}-db"
  role = aws_iam_role.database.name
}
