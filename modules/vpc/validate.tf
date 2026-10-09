locals {
  invalid_subnet_types = {
    for id, config in local.vpcs : id => [
      for name, subnet in config.subnets : name
      if !contains(["public", "application", "database", "firewall"], try(subnet.type, ""))
    ]
    if length([
      for name, subnet in config.subnets : name
      if !contains(["public", "application", "database", "firewall"], try(subnet.type, ""))
    ]) > 0
  }

  subnet_role_counts = {
    for id, config in local.vpcs : id => {
      for subnet_type in ["public", "application", "database", "firewall"] :
      subnet_type => length([
        for _, subnet in config.subnets : 1
        if try(subnet.type, "") == subnet_type
      ])
    }
  }

  missing_required_subnet_roles = {
    for id, counts in local.subnet_role_counts : id => compact([
      counts.public >= 2 ? null : "public>=2",
      counts.application >= 1 ? null : "application>=1",
      counts.database >= 1 ? null : "database>=1",
      counts.firewall >= 1 ? null : "firewall>=1",
    ])
    if counts.public < 2 || counts.application < 1 || counts.database < 1 || counts.firewall < 1
  }
}

data "validation_error" "subnet_types" {
  for_each  = local.invalid_subnet_types
  condition = false
  summary   = "${each.key} has unsupported subnet types"
  details   = "Unsupported subnet type configured on: ${join(", ", each.value)}"
}

data "validation_error" "required_subnet_roles" {
  for_each  = local.missing_required_subnet_roles
  condition = false
  summary   = "${each.key} is missing required POC subnet roles"
  details   = "Required topology: ${join(", ", each.value)}"
}
