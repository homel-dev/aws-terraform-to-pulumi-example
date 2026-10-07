output "policy_arn" {
  value = try(aws_dlm_lifecycle_policy.database[0].arn, null)
}
