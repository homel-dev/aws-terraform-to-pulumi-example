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
  for_each           = local.enabled_configs
  name               = "${local.prefix}-dlm${each.key == "database" ? "" : "-${each.key}"}"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
  tags               = merge(local.common_tags, try(each.value.tags, {}))
}

resource "aws_iam_role_policy_attachment" "this" {
  for_each   = local.enabled_configs
  role       = aws_iam_role.this[each.key].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSDataLifecycleManagerServiceRole"
}

resource "aws_dlm_lifecycle_policy" "database" {
  for_each           = local.enabled_configs
  description        = "Scheduled EBS snapshots for ${local.prefix}${each.key == "database" ? "" : "-${each.key}"} database volumes"
  execution_role_arn = aws_iam_role.this[each.key].arn
  state              = "ENABLED"

  policy_details {
    resource_types = ["VOLUME"]
    target_tags    = each.value.target_tags

    schedule {
      name      = each.key == "database" ? "daily-database-snapshots" : "daily-${each.key}-snapshots"
      copy_tags = true

      create_rule {
        interval      = each.value.interval_hours
        interval_unit = "HOURS"
        times         = each.value.times
      }

      retain_rule {
        count = each.value.retain_count
      }
    }
  }
  tags = merge(local.common_tags, try(each.value.tags, {}))
}
