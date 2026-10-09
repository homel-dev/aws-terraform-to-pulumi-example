moved {
  from = aws_lb.this
  to   = aws_lb.this["compute"]
}

moved {
  from = aws_lb_target_group.application
  to   = aws_lb_target_group.application["compute"]
}

moved {
  from = aws_lb_listener.https
  to   = aws_lb_listener.https["compute"]
}

moved {
  from = aws_ec2_managed_prefix_list.approved_clients
  to   = aws_ec2_managed_prefix_list.approved_clients["compute"]
}

moved {
  from = aws_security_group.alb
  to   = aws_security_group.alb["compute"]
}

moved {
  from = aws_security_group.application
  to   = aws_security_group.application["compute"]
}

moved {
  from = aws_security_group.database
  to   = aws_security_group.database["compute"]
}

moved {
  from = aws_security_group.endpoints
  to   = aws_security_group.endpoints["compute"]
}

moved {
  from = aws_vpc_security_group_ingress_rule.alb_https
  to   = aws_vpc_security_group_ingress_rule.alb_https["compute"]
}

moved {
  from = aws_vpc_security_group_egress_rule.alb_to_application
  to   = aws_vpc_security_group_egress_rule.alb_to_application["compute"]
}

moved {
  from = aws_vpc_security_group_ingress_rule.application_from_alb
  to   = aws_vpc_security_group_ingress_rule.application_from_alb["compute"]
}

moved {
  from = aws_vpc_security_group_egress_rule.application_to_database
  to   = aws_vpc_security_group_egress_rule.application_to_database["compute"]
}

moved {
  from = aws_vpc_security_group_egress_rule.application_https
  to   = aws_vpc_security_group_egress_rule.application_https["compute"]
}

moved {
  from = aws_vpc_security_group_ingress_rule.database_from_application
  to   = aws_vpc_security_group_ingress_rule.database_from_application["compute"]
}

moved {
  from = aws_vpc_security_group_egress_rule.application_to_endpoints
  to   = aws_vpc_security_group_egress_rule.application_to_endpoints["compute"]
}

moved {
  from = aws_vpc_security_group_egress_rule.database_to_endpoints
  to   = aws_vpc_security_group_egress_rule.database_to_endpoints["compute"]
}

moved {
  from = aws_vpc_security_group_ingress_rule.endpoints_from_application
  to   = aws_vpc_security_group_ingress_rule.endpoints_from_application["compute"]
}

moved {
  from = aws_vpc_security_group_ingress_rule.endpoints_from_database
  to   = aws_vpc_security_group_ingress_rule.endpoints_from_database["compute"]
}

moved {
  from = aws_secretsmanager_secret.database
  to   = aws_secretsmanager_secret.database["compute"]
}

moved {
  from = aws_launch_template.application
  to   = aws_launch_template.application["compute"]
}

moved {
  from = aws_autoscaling_group.application
  to   = aws_autoscaling_group.application["compute"]
}

moved {
  from = aws_instance.database
  to   = aws_instance.database["compute"]
}

moved {
  from = aws_vpc_endpoint.interface["ssm"]
  to   = aws_vpc_endpoint.interface["compute/ssm"]
}

moved {
  from = aws_vpc_endpoint.interface["ssmmessages"]
  to   = aws_vpc_endpoint.interface["compute/ssmmessages"]
}


moved {
  from = aws_vpc_endpoint.interface["ec2messages"]
  to   = aws_vpc_endpoint.interface["compute/ec2messages"]
}

moved {
  from = aws_vpc_endpoint.interface["secretsmanager"]
  to   = aws_vpc_endpoint.interface["compute/secretsmanager"]
}
