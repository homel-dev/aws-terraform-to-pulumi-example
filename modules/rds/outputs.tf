output "identifier" {
  value = aws_db_instance.database.identifier
}

output "endpoint" {
  value = aws_db_instance.database.address
}

output "master_secret_arn" {
  value = aws_db_instance.database.master_user_secret[0].secret_arn
}

output "security_group_id" {
  value = aws_security_group.rds.id
}
