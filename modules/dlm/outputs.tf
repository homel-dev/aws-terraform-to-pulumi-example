output "policies" {
  value = { for id, policy in aws_dlm_lifecycle_policy.database : id => policy.arn }
}

output "policy_arn" {
  value = try(aws_dlm_lifecycle_policy.database["database"].arn, null)
}
