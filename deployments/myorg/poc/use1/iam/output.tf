output "application_instance_profile_name" {
  value = module.iam.application_instance_profile_name
}

output "database_instance_profile_name" {
  value = module.iam.database_instance_profile_name
}

output "application_role_arn" {
  value = module.iam.application_role_arn
}

output "database_role_arn" {
  value = module.iam.database_role_arn
}
