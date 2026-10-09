data "aws_region" "current" {}

locals {
  interface_endpoint_services = toset(["ssm", "ssmmessages", "ec2messages", "secretsmanager"])
  endpoint_entries = flatten([
    for id, config in local.configs : [
      for service in local.interface_endpoint_services : {
        key       = "${id}/${service}"
        config_id = id
        service   = service
      }
    ]
  ])
  endpoints = { for endpoint in local.endpoint_entries : endpoint.key => endpoint }
}

resource "aws_vpc_endpoint" "interface" {
  for_each = local.endpoints

  vpc_id              = local.vpc_states[each.value.config_id].vpc_id
  vpc_endpoint_type   = "Interface"
  service_name        = "com.amazonaws.${local.region}.${each.value.service}"
  private_dns_enabled = true
  subnet_ids = [
    local.vpc_states[each.value.config_id].subnet_ids[local.configs[each.value.config_id].application.subnet],
    local.vpc_states[each.value.config_id].subnet_ids[local.configs[each.value.config_id].database.subnet],
  ]
  security_group_ids = [aws_security_group.endpoints[each.value.config_id].id]
}
