output "vpcs" {
  description = "VPCs indexed by their YAML configuration filename."
  value       = module.vpc.vpcs
}

locals {
  # Brownfield consumers still use flat outputs. This explicitly selects
  # config/vpc.yml, regardless of how many other VPCs exist in this root.
  brownfield_vpc = module.vpc.vpcs["vpc"]
}

output "vpc_id" {
  value = local.brownfield_vpc.vpc_id
}

output "vpc_cidr" {
  value = local.brownfield_vpc.vpc_cidr
}

output "internet_gateway_id" {
  value = local.brownfield_vpc.internet_gateway_id
}

output "subnet_ids" {
  value = local.brownfield_vpc.subnet_ids
}

output "subnet_cidrs" {
  value = local.brownfield_vpc.subnet_cidrs
}

output "subnet_availability_zones" {
  value = local.brownfield_vpc.subnet_availability_zones
}

output "route_table_ids" {
  value = local.brownfield_vpc.route_table_ids
}
