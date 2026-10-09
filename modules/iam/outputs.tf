output "groups" {
  description = "IAM role/profile pairs keyed by YAML filename."
  value = {
    for id, profile in aws_iam_instance_profile.application : id => {
      application_instance_profile_name = profile.name
      database_instance_profile_name    = aws_iam_instance_profile.database[id].name
      application_role_arn              = aws_iam_role.application[id].arn
      database_role_arn                 = aws_iam_role.database[id].arn
    }
  }
}

output "application_instance_profile_name" {
  value = aws_iam_instance_profile.application["instances"].name
}

output "database_instance_profile_name" {
  value = aws_iam_instance_profile.database["instances"].name
}

output "application_role_arn" {
  value = aws_iam_role.application["instances"].arn
}

output "database_role_arn" {
  value = aws_iam_role.database["instances"].arn
}
