output "alb_dns_name" {
  value = module.ec2.alb_dns_name
}

output "alb_zone_id" {
  value = module.ec2.alb_zone_id
}

output "alb_arn" {
  value = module.ec2.alb_arn
}

output "approved_client_prefix_list_id" {
  value = module.ec2.approved_client_prefix_list_id
}

output "application_asg_name" {
  value = module.ec2.application_asg_name
}

output "application_security_group_id" {
  value = module.ec2.application_security_group_id
}

output "database_instance_id" {
  value = module.ec2.database_instance_id
}

output "database_security_group_id" {
  value = module.ec2.database_security_group_id
}

output "database_secret_arn" {
  value = module.ec2.database_secret_arn
}

output "endpoint_security_group_id" {
  value = module.ec2.endpoint_security_group_id
}
