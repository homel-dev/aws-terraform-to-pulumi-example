output "database_rds_identifier" {
  value = module.rds.identifier
}

output "database_rds_endpoint" {
  value = module.rds.endpoint
}

output "database_rds_master_secret_arn" {
  value = module.rds.master_secret_arn
}

output "rds_security_group_id" {
  value = module.rds.security_group_id
}
