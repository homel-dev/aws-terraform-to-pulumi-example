data "aws_iam_policy_document" "assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["dlm.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  count              = local.config.enabled ? 1 : 0
  name               = "${local.prefix}-dlm"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

resource "aws_iam_role_policy_attachment" "this" {
  count      = local.config.enabled ? 1 : 0
  role       = aws_iam_role.this[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSDataLifecycleManagerServiceRole"
}

resource "aws_dlm_lifecycle_policy" "database" {
  count              = local.config.enabled ? 1 : 0
  description        = "Scheduled EBS snapshots for ${local.prefix} database volumes"
  execution_role_arn = aws_iam_role.this[0].arn
  state              = "ENABLED"

  policy_details {
    resource_types = ["VOLUME"]
    target_tags    = local.config.target_tags

    schedule {
      name      = "daily-database-snapshots"
      copy_tags = true

      create_rule {
        interval      = local.config.interval_hours
        interval_unit = "HOURS"
        times         = local.config.times
      }

      retain_rule {
        count = local.config.retain_count
      }
    }
  }
}
