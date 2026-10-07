output "vpc_id" {
  value = module.vpc.vpc_id
}

output "vpc_cidr" {
  value = module.vpc.vpc_cidr
}

output "internet_gateway_id" {
  value = module.vpc.internet_gateway_id
}

output "subnet_ids" {
  value = module.vpc.subnet_ids
}

output "subnet_cidrs" {
  value = module.vpc.subnet_cidrs
}

output "subnet_availability_zones" {
  value = module.vpc.subnet_availability_zones
}

output "route_table_ids" {
  value = module.vpc.route_table_ids
}
