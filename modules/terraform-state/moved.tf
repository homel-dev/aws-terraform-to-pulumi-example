moved {
  from = aws_s3_bucket.this
  to   = aws_s3_bucket.this["state"]
}

moved {
  from = aws_s3_bucket_public_access_block.this
  to   = aws_s3_bucket_public_access_block.this["state"]
}

moved {
  from = aws_s3_bucket_versioning.this
  to   = aws_s3_bucket_versioning.this["state"]
}

moved {
  from = aws_s3_bucket_server_side_encryption_configuration.this
  to   = aws_s3_bucket_server_side_encryption_configuration.this["state"]
}

moved {
  from = aws_s3_bucket_policy.this
  to   = aws_s3_bucket_policy.this["state"]
}
