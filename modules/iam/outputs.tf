output "application_instance_profile_name" {
  value = aws_iam_instance_profile.application.name
}

output "database_instance_profile_name" {
  value = aws_iam_instance_profile.database.name
}

output "application_role_arn" {
  value = aws_iam_role.application.arn
}

output "database_role_arn" {
  value = aws_iam_role.database.arn
}
