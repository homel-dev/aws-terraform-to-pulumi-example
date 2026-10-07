output "audit_bucket_name" {
  value = module.logging.audit_bucket_name
}

output "audit_bucket_arn" {
  value = module.logging.audit_bucket_arn
}

output "cloudtrail_arn" {
  value = module.logging.cloudtrail_arn
}

output "flow_log_id" {
  value = module.logging.flow_log_id
}
