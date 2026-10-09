output "computes" {
  description = "Compute bundles keyed by YAML filename."
  value = {
    for id, alb in aws_lb.this : id => {
      alb_dns_name = aws_lb.this[id].dns_name
      alb_zone_id = aws_lb.this[id].zone_id
      alb_arn = aws_lb.this[id].arn
      approved_client_prefix_list_id = aws_ec2_managed_prefix_list.approved_clients[id].id
      application_asg_name = aws_autoscaling_group.application[id].name
      application_security_group_id = aws_security_group.application[id].id
      database_instance_id = aws_instance.database[id].id
      database_security_group_id = aws_security_group.database[id].id
      database_secret_arn = aws_secretsmanager_secret.database[id].arn
      endpoint_security_group_id = aws_security_group.endpoints[id].id
    }
  }
}

output "alb_dns_name" {
  value = aws_lb.this["compute"].dns_name
}

output "alb_zone_id" {
  value = aws_lb.this["compute"].zone_id
}

output "alb_arn" {
  value = aws_lb.this["compute"].arn
}

output "approved_client_prefix_list_id" {
  value = aws_ec2_managed_prefix_list.approved_clients["compute"].id
}

output "application_asg_name" {
  value = aws_autoscaling_group.application["compute"].name
}

output "application_security_group_id" {
  value = aws_security_group.application["compute"].id
}

output "database_instance_id" {
  value = aws_instance.database["compute"].id
}

output "database_security_group_id" {
  value = aws_security_group.database["compute"].id
}

output "database_secret_arn" {
  value = aws_secretsmanager_secret.database["compute"].arn
}

output "endpoint_security_group_id" {
  value = aws_security_group.endpoints["compute"].id
}
