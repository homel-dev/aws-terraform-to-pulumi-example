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
  bucket        = "${local.prefix}-${data.aws_caller_identity.current.account_id}-audit"
  force_destroy = local.config.force_destroy
}

resource "aws_s3_bucket_public_access_block" "audit" {
  bucket = aws_s3_bucket.audit.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "audit" {
  bucket = aws_s3_bucket.audit.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "audit" {
  bucket = aws_s3_bucket.audit.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "audit" {
  bucket = aws_s3_bucket.audit.id

  rule {
    id     = "expire-audit-data"
    status = "Enabled"

    filter {}

    expiration {
      days = local.config.retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = local.config.retention_days
    }
  }

  depends_on = [aws_s3_bucket_versioning.audit]
}

locals {
  trail_name = "${local.prefix}-audit"
  trail_arn  = "arn:aws:cloudtrail:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:trail/${local.trail_name}"
}

data "aws_iam_policy_document" "audit_bucket" {
  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    resources = [
      aws_s3_bucket.audit.arn,
      "${aws_s3_bucket.audit.arn}/*",
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  dynamic "statement" {
    for_each = local.config.cloudtrail_enabled ? [1] : []
    content {
      sid     = "CloudTrailAclCheck"
      effect  = "Allow"
      actions = ["s3:GetBucketAcl"]

      principals {
        type        = "Service"
        identifiers = ["cloudtrail.amazonaws.com"]
      }

      resources = [aws_s3_bucket.audit.arn]

      condition {
        test     = "StringEquals"
        variable = "aws:SourceArn"
        values   = [local.trail_arn]
      }
    }
  }

  dynamic "statement" {
    for_each = local.config.cloudtrail_enabled ? [1] : []
    content {
      sid     = "CloudTrailWrite"
      effect  = "Allow"
      actions = ["s3:PutObject"]

      principals {
        type        = "Service"
        identifiers = ["cloudtrail.amazonaws.com"]
      }

      resources = ["${aws_s3_bucket.audit.arn}/cloudtrail/AWSLogs/${data.aws_caller_identity.current.account_id}/*"]

      condition {
        test     = "StringEquals"
        variable = "s3:x-amz-acl"
        values   = ["bucket-owner-full-control"]
      }

      condition {
        test     = "StringEquals"
        variable = "aws:SourceArn"
        values   = [local.trail_arn]
      }
    }
  }

  dynamic "statement" {
    for_each = local.config.alb_access_logs_enabled ? [1] : []
    content {
      sid     = "AlbLogDelivery"
      effect  = "Allow"
      actions = ["s3:PutObject"]

      principals {
        type        = "Service"
        identifiers = ["logdelivery.elasticloadbalancing.amazonaws.com"]
      }

      resources = ["${aws_s3_bucket.audit.arn}/alb/AWSLogs/${data.aws_caller_identity.current.account_id}/*"]
    }
  }
}

resource "aws_s3_bucket_policy" "audit" {
  bucket = aws_s3_bucket.audit.id
  policy = data.aws_iam_policy_document.audit_bucket.json
}

resource "aws_cloudtrail" "this" {
  count                         = local.config.cloudtrail_enabled ? 1 : 0
  name                          = local.trail_name
  s3_bucket_name                = aws_s3_bucket.audit.id
  s3_key_prefix                 = "cloudtrail"
  include_global_service_events = true
  is_multi_region_trail         = false
  enable_log_file_validation    = true
  depends_on                    = [aws_s3_bucket_policy.audit]
}

resource "aws_cloudwatch_log_group" "flow_logs" {
  count             = local.config.vpc_flow_logs_enabled ? 1 : 0
  name              = "/aws/vpc/flowlogs/${local.prefix}"
  retention_in_days = local.config.flow_log_retention_days
}

resource "aws_iam_role" "flow_logs" {
  count              = local.config.vpc_flow_logs_enabled ? 1 : 0
  name               = "${local.prefix}-flow-logs"
  assume_role_policy = data.aws_iam_policy_document.flow_logs_assume_role.json
}

data "aws_iam_policy_document" "flow_logs" {
  count = local.config.vpc_flow_logs_enabled ? 1 : 0

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
  count  = local.config.vpc_flow_logs_enabled ? 1 : 0
  name   = "${local.prefix}-flow-logs"
  role   = aws_iam_role.flow_logs[0].id
  policy = data.aws_iam_policy_document.flow_logs[0].json
}

resource "aws_flow_log" "vpc" {
  count           = local.config.vpc_flow_logs_enabled ? 1 : 0
  iam_role_arn    = aws_iam_role.flow_logs[0].arn
  log_destination = aws_cloudwatch_log_group.flow_logs[0].arn
  traffic_type    = "ALL"
  vpc_id          = data.terraform_remote_state.vpc.outputs.vpc_id
}
