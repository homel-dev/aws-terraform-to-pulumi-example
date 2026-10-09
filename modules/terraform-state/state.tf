data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "this" {
  for_each      = local.configs
  bucket        = local.bucket_names[each.key]
  force_destroy = each.value.force_destroy

  tags = merge(local.common_tags, try(each.value.tags, {}), {
    Name = local.bucket_names[each.key]
  })
}

resource "aws_s3_bucket_public_access_block" "this" {
  for_each = local.configs
  bucket   = aws_s3_bucket.this[each.key].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "this" {
  for_each = local.configs
  bucket   = aws_s3_bucket.this[each.key].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  for_each = local.configs
  bucket   = aws_s3_bucket.this[each.key].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

data "aws_iam_policy_document" "this" {
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
      aws_s3_bucket.this[each.key].arn,
      "${aws_s3_bucket.this[each.key].arn}/*",
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "this" {
  for_each = local.configs
  bucket   = aws_s3_bucket.this[each.key].id
  policy   = data.aws_iam_policy_document.this[each.key].json
}
