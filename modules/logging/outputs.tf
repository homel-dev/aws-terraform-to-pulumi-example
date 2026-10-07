output "audit_bucket_name" {
  value      = aws_s3_bucket.audit.bucket
  depends_on = [aws_s3_bucket_policy.audit]
}

output "audit_bucket_arn" {
  value = aws_s3_bucket.audit.arn
}

output "cloudtrail_arn" {
  value = try(aws_cloudtrail.this[0].arn, null)
}

output "flow_log_id" {
  value = try(aws_flow_log.vpc[0].id, null)
}
