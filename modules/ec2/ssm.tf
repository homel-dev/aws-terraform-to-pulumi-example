data "aws_region" "current" {}

locals {
  interface_endpoint_services = toset(["ssm", "ssmmessages", "ec2messages", "secretsmanager"])
}

resource "aws_vpc_endpoint" "interface" {
  for_each = local.interface_endpoint_services

  vpc_id              = local.vpc_state.vpc_id
  vpc_endpoint_type   = "Interface"
  service_name        = "com.amazonaws.${data.aws_region.current.region}.${each.value}"
  private_dns_enabled = true
  subnet_ids = [
    local.vpc_state.subnet_ids[local.config.application.subnet],
    local.vpc_state.subnet_ids[local.config.database.subnet],
  ]
  security_group_ids = [aws_security_group.endpoints.id]
}
