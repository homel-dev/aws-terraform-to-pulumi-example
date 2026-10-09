data "aws_region" "current" {}

data "aws_iam_policy_document" "flow_logs_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
  }
}

resource "aws_s3_bucket" "audit" {
  for_each      = local.configs
  bucket        = "${local.prefix}-${data.aws_caller_identity.current.account_id}-${each.key}"
  force_destroy = each.value.force_destroy
  tags          = merge(local.common_tags, try(each.value.tags, {}))
}

resource "aws_s3_bucket_public_access_block" "audit" {
  for_each = local.configs
  bucket   = aws_s3_bucket.audit[each.key].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "audit" {
  for_each = local.configs
  bucket   = aws_s3_bucket.audit[each.key].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "audit" {
  for_each = local.configs
  bucket   = aws_s3_bucket.audit[each.key].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "audit" {
  for_each = local.configs
  bucket   = aws_s3_bucket.audit[each.key].id

  rule {
    id     = "expire-audit-data"
    status = "Enabled"

    filter {}

    expiration {
      days = each.value.retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = each.value.retention_days
    }
  }

  depends_on = [aws_s3_bucket_versioning.audit]
}

locals {
  trail_names = { for id, _ in local.configs : id => "${local.prefix}-${id}" }
  trail_arns  = { for id, name in local.trail_names : id => "arn:aws:cloudtrail:${local.region}:${data.aws_caller_identity.current.account_id}:trail/${name}" }
}

data "aws_iam_policy_document" "audit_bucket" {
  for_each = local.configs
  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    resources = [
      aws_s3_bucket.audit[each.key].arn,
      "${aws_s3_bucket.audit[each.key].arn}/*",
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  dynamic "statement" {
    for_each = each.value.cloudtrail_enabled ? [1] : []
    content {
      sid     = "CloudTrailAclCheck"
      effect  = "Allow"
      actions = ["s3:GetBucketAcl"]

      principals {
        type        = "Service"
        identifiers = ["cloudtrail.amazonaws.com"]
      }

      resources = [aws_s3_bucket.audit[each.key].arn]

      condition {
        test     = "StringEquals"
        variable = "aws:SourceArn"
        values   = [local.trail_arns[each.key]]
      }
    }
  }

  dynamic "statement" {
    for_each = each.value.cloudtrail_enabled ? [1] : []
    content {
      sid     = "CloudTrailWrite"
      effect  = "Allow"
      actions = ["s3:PutObject"]

      principals {
        type        = "Service"
        identifiers = ["cloudtrail.amazonaws.com"]
      }

      resources = ["${aws_s3_bucket.audit[each.key].arn}/cloudtrail/AWSLogs/${data.aws_caller_identity.current.account_id}/*"]

      condition {
        test     = "StringEquals"
        variable = "s3:x-amz-acl"
        values   = ["bucket-owner-full-control"]
      }

      condition {
        test     = "StringEquals"
        variable = "aws:SourceArn"
        values   = [local.trail_arns[each.key]]
      }
    }
  }

  dynamic "statement" {
    for_each = each.value.alb_access_logs_enabled ? [1] : []
    content {
      sid     = "AlbLogDelivery"
      effect  = "Allow"
      actions = ["s3:PutObject"]

      principals {
        type        = "Service"
        identifiers = ["logdelivery.elasticloadbalancing.amazonaws.com"]
      }

      resources = ["${aws_s3_bucket.audit[each.key].arn}/alb/AWSLogs/${data.aws_caller_identity.current.account_id}/*"]
    }
  }
}

resource "aws_s3_bucket_policy" "audit" {
  for_each = local.configs
  bucket   = aws_s3_bucket.audit[each.key].id
  policy   = data.aws_iam_policy_document.audit_bucket[each.key].json
}

resource "aws_cloudtrail" "this" {
  for_each                      = local.cloudtrail_configs
  name                          = local.trail_names[each.key]
  s3_bucket_name                = aws_s3_bucket.audit[each.key].id
  s3_key_prefix                 = "cloudtrail"
  include_global_service_events = true
  is_multi_region_trail         = false
  enable_log_file_validation    = true
  depends_on                    = [aws_s3_bucket_policy.audit]
}

resource "aws_cloudwatch_log_group" "flow_logs" {
  for_each          = local.flow_log_configs
  name              = "/aws/vpc/flowlogs/${local.prefix}${each.key == "audit" ? "" : "-${each.key}"}"
  retention_in_days = each.value.flow_log_retention_days
}

resource "aws_iam_role" "flow_logs" {
  for_each           = local.flow_log_configs
  name               = "${local.prefix}-flow-logs${each.key == "audit" ? "" : "-${each.key}"}"
  assume_role_policy = data.aws_iam_policy_document.flow_logs_assume_role.json
}

data "aws_iam_policy_document" "flow_logs" {
  for_each = local.flow_log_configs

  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "flow_logs" {
  for_each = local.flow_log_configs
  name     = "${local.prefix}-flow-logs${each.key == "audit" ? "" : "-${each.key}"}"
  role     = aws_iam_role.flow_logs[each.key].id
  policy   = data.aws_iam_policy_document.flow_logs[each.key].json
}

resource "aws_flow_log" "vpc" {
  for_each        = local.flow_log_configs
  iam_role_arn    = aws_iam_role.flow_logs[each.key].arn
  log_destination = aws_cloudwatch_log_group.flow_logs[each.key].arn
  traffic_type    = "ALL"
  vpc_id          = data.terraform_remote_state.vpc.outputs.vpcs[each.value.vpc_key].vpc_id
}
