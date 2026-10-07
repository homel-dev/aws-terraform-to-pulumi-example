locals {
  invalid_subnet_types = [
    for name, subnet in local.config.subnets : name
    if !contains(["public", "application", "database", "firewall"], subnet.type)
  ]

  subnets_by_type = {
    for subnet_type in ["public", "application", "database", "firewall"] :
    subnet_type => {
      for name, subnet in local.config.subnets : name => subnet
      if subnet.type == subnet_type
    }
  }

  missing_required_subnet_roles = compact([
    length(local.subnets_by_type.public) >= 2 ? null : "public>=2",
    length(local.subnets_by_type.application) >= 1 ? null : "application>=1",
    length(local.subnets_by_type.database) >= 1 ? null : "database>=1",
    length(local.subnets_by_type.firewall) >= 1 ? null : "firewall>=1",
  ])
}

data "validation_error" "subnet_types" {
  count     = length(local.invalid_subnet_types) > 0 ? 1 : 0
  condition = false
  summary   = "Unsupported subnet types"
  details   = "Unsupported subnet type configured on: ${join(", ", local.invalid_subnet_types)}"
}

data "validation_error" "required_subnet_roles" {
  count     = length(local.missing_required_subnet_roles) > 0 ? 1 : 0
  condition = false
  summary   = "Missing required POC subnet roles"
  details   = "Required topology: ${join(", ", local.missing_required_subnet_roles)}"
}
