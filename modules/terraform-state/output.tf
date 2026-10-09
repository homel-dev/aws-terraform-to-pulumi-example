output "buckets" {
  value = { for id, bucket in aws_s3_bucket.this : id => { name = bucket.bucket, arn = bucket.arn } }
}

output "bucket_name" {
  value = aws_s3_bucket.this["state"].bucket
}

output "bucket_arn" {
  value = aws_s3_bucket.this["state"].arn
}
