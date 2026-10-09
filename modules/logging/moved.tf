moved {
  from = aws_s3_bucket.audit
  to   = aws_s3_bucket.audit["audit"]
}

moved {
  from = aws_s3_bucket_public_access_block.audit
  to   = aws_s3_bucket_public_access_block.audit["audit"]
}

moved {
  from = aws_s3_bucket_versioning.audit
  to   = aws_s3_bucket_versioning.audit["audit"]
}

moved {
  from = aws_s3_bucket_server_side_encryption_configuration.audit
  to   = aws_s3_bucket_server_side_encryption_configuration.audit["audit"]
}

moved {
  from = aws_s3_bucket_lifecycle_configuration.audit
  to   = aws_s3_bucket_lifecycle_configuration.audit["audit"]
}

moved {
  from = aws_s3_bucket_policy.audit
  to   = aws_s3_bucket_policy.audit["audit"]
}

moved {
  from = aws_cloudtrail.this[0]
  to   = aws_cloudtrail.this["audit"]
}

moved {
  from = aws_cloudwatch_log_group.flow_logs[0]
  to   = aws_cloudwatch_log_group.flow_logs["audit"]
}

moved {
  from = aws_iam_role.flow_logs[0]
  to   = aws_iam_role.flow_logs["audit"]
}

moved {
  from = aws_iam_role_policy.flow_logs[0]
  to   = aws_iam_role_policy.flow_logs["audit"]
}

moved {
  from = aws_flow_log.vpc[0]
  to   = aws_flow_log.vpc["audit"]
}

moved {
  from = aws_guardduty_detector.regional
  to   = module.guardduty.aws_guardduty_detector.regional
}
