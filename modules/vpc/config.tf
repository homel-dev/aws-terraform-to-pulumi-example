locals {
  config_path = {
    folder = "config"
    suffix = ".yml"
  }

  # Each YAML describes a VPC; its relative filename is the stable resource key.
  vpcs = {
    for filename in fileset("${path.root}/${local.config_path.folder}", "**") :
    trimsuffix(filename, local.config_path.suffix) => merge(
      local.defaults,
      yamldecode(file("${path.root}/${local.config_path.folder}/${filename}"))
    )
    if endswith(filename, local.config_path.suffix)
  }

  regions = distinct([for _, config in local.vpcs : config.region])
  region  = try(local.regions[0], null)

  # Compound keys permit the same subnet name (e.g. public-a) in many VPCs.
  subnet_entries = flatten([
    for vpc_key, vpc in local.vpcs : [
      for subnet_key, subnet in vpc.subnets : merge(subnet, {
        key        = "${vpc_key}/${subnet_key}"
        vpc_key    = vpc_key
        subnet_key = subnet_key
      })
    ]
  ])

  subnets = { for subnet in local.subnet_entries : subnet.key => subnet }
  public_subnets = {
    for key, subnet in local.subnets : key => subnet
    if subnet.type == "public"
  }
}

data "validation_error" "vpc_config_present" {
  count     = length(local.vpcs) > 0 ? 0 : 1
  condition = false
  summary   = "No VPC configuration found"
  details   = "Add one YAML file per VPC under ${path.root}/config."
}

data "validation_error" "single_region" {
  count     = length(local.regions) == 1 ? 0 : 1
  condition = false
  summary   = "VPC stack contains multiple AWS regions"
  details   = "All VPC YAML files in one location must use the same AWS region."
}
