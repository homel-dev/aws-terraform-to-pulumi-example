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
  for_each           = local.configs
  name               = "${local.prefix}-app${local.iam_suffixes[each.key]}"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
  tags               = merge(local.common_tags, try(each.value.tags, {}))
}

resource "aws_iam_role" "database" {
  for_each           = local.configs
  name               = "${local.prefix}-db${local.iam_suffixes[each.key]}"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
  tags               = merge(local.common_tags, try(each.value.tags, {}))
}

resource "aws_iam_role_policy_attachment" "application_ssm" {
  for_each   = local.ssm_configs
  role       = aws_iam_role.application[each.key].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "database_ssm" {
  for_each   = local.ssm_configs
  role       = aws_iam_role.database[each.key].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

data "aws_iam_policy_document" "application_secret" {
  for_each = local.configs
  statement {
    effect = "Allow"
    actions = [
      "secretsmanager:DescribeSecret",
      "secretsmanager:GetSecretValue",
    ]
    resources = ["arn:aws:secretsmanager:${local.region}:${data.aws_caller_identity.current.account_id}:secret:${local.prefix}/database${local.iam_suffixes[each.key]}-*"]
  }
}

resource "aws_iam_role_policy" "application_secret" {
  for_each = local.configs
  name     = "${local.prefix}-db-secret-read${local.iam_suffixes[each.key]}"
  role     = aws_iam_role.application[each.key].id
  policy   = data.aws_iam_policy_document.application_secret[each.key].json
}

data "aws_iam_policy_document" "database_secret" {
  for_each = local.configs
  statement {
    effect = "Allow"
    actions = [
      "secretsmanager:DescribeSecret",
      "secretsmanager:GetSecretValue",
      "secretsmanager:PutSecretValue",
    ]
    resources = ["arn:aws:secretsmanager:${local.region}:${data.aws_caller_identity.current.account_id}:secret:${local.prefix}/database${local.iam_suffixes[each.key]}-*"]
  }

  statement {
    effect    = "Allow"
    actions   = ["secretsmanager:GetRandomPassword"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "database_secret" {
  for_each = local.configs
  name     = "${local.prefix}-db-secret-bootstrap${local.iam_suffixes[each.key]}"
  role     = aws_iam_role.database[each.key].id
  policy   = data.aws_iam_policy_document.database_secret[each.key].json
}

resource "aws_iam_instance_profile" "application" {
  for_each = local.configs
  name     = "${local.prefix}-app${local.iam_suffixes[each.key]}"
  role     = aws_iam_role.application[each.key].name
  tags     = merge(local.common_tags, try(each.value.tags, {}))
}

resource "aws_iam_instance_profile" "database" {
  for_each = local.configs
  name     = "${local.prefix}-db${local.iam_suffixes[each.key]}"
  role     = aws_iam_role.database[each.key].name
  tags     = merge(local.common_tags, try(each.value.tags, {}))
}
