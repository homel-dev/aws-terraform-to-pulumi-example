output "vpc_id" {
  value = local.seed_ids.vpc_id
}

output "load_balancer_dns_name" {
  value = aws_lb.this.dns_name
}

output "load_balancer_arn" {
  value = aws_lb.this.arn
}

output "application_asg_name" {
  value = aws_autoscaling_group.application.name
}

output "database_instance_id" {
  value = aws_instance.database.id
}

output "database_private_ip" {
  value = aws_instance.database.private_ip
}

output "security_group_ids" {
  value = {
    alb         = aws_security_group.alb.id
    application = aws_security_group.application.id
    database    = aws_security_group.database.id
  }
}
