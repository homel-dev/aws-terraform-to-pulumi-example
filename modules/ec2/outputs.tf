output "alb_dns_name" {
  value = aws_lb.this.dns_name
}

output "alb_zone_id" {
  value = aws_lb.this.zone_id
}

output "alb_arn" {
  value = aws_lb.this.arn
}

output "approved_client_prefix_list_id" {
  value = aws_ec2_managed_prefix_list.approved_clients.id
}

output "application_asg_name" {
  value = aws_autoscaling_group.application.name
}

output "application_security_group_id" {
  value = aws_security_group.application.id
}

output "database_instance_id" {
  value = aws_instance.database.id
}

output "database_security_group_id" {
  value = aws_security_group.database.id
}

output "database_secret_arn" {
  value = aws_secretsmanager_secret.database.arn
}

output "endpoint_security_group_id" {
  value = aws_security_group.endpoints.id
}
