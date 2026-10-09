output "loggings" {
  description = "Audit/logging bundles keyed by configuration filename."
  value = {
    for id, bucket in aws_s3_bucket.audit : id => {
      audit_bucket_name     = bucket.bucket
      audit_bucket_arn      = bucket.arn
      cloudtrail_arn        = try(aws_cloudtrail.this[id].arn, null)
      flow_log_id           = try(aws_flow_log.vpc[id].id, null)
      guardduty_detector_id = aws_guardduty_detector.regional.id
    }
  }
  depends_on = [aws_s3_bucket_policy.audit]
}

output "audit_bucket_name" {
  value      = aws_s3_bucket.audit["audit"].bucket
  depends_on = [aws_s3_bucket_policy.audit]
}

output "audit_bucket_arn" {
  value = aws_s3_bucket.audit["audit"].arn
}

output "cloudtrail_arn" {
  value = try(aws_cloudtrail.this["audit"].arn, null)
}

output "flow_log_id" {
  value = try(aws_flow_log.vpc["audit"].id, null)
}

output "guardduty_detector_id" {
  value = aws_guardduty_detector.regional.id
}
