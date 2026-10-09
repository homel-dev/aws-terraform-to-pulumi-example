# Seed adoption only. All IDs are resolved from aws-brownfield-seed.sh's
# persisted manifest; no resource is created by these blocks.
variable "seed_manifest_path" {
  description = "Absolute path to the JSON manifest emitted by seed deploy"
  type        = string
  default     = ""
}

locals {
  seed_manifest = var.seed_manifest_path == "" ? null : jsondecode(file(var.seed_manifest_path))
  seed_network  = local.seed_manifest == null ? null : local.seed_manifest.resources
}

import {
  for_each = local.seed_network == null ? {} : { seed = local.seed_network.vpc_id }
  to       = module.vpc.aws_vpc.this
  id       = each.value
}

import {
  for_each = local.seed_network == null ? {} : { seed = local.seed_network.internet_gateway_id }
  to       = module.vpc.aws_internet_gateway.this
  id       = each.value
}

import {
  for_each = local.seed_network == null ? {} : { seed = local.seed_network["subnet_public-a"] }
  to       = module.vpc.aws_subnet.this["public-a"]
  id       = each.value
}

import {
  for_each = local.seed_network == null ? {} : { seed = local.seed_network["subnet_public-b"] }
  to       = module.vpc.aws_subnet.this["public-b"]
  id       = each.value
}

import {
  for_each = local.seed_network == null ? {} : { seed = local.seed_network["subnet_app-a"] }
  to       = module.vpc.aws_subnet.this["app-a"]
  id       = each.value
}

import {
  for_each = local.seed_network == null ? {} : { seed = local.seed_network["subnet_database-a"] }
  to       = module.vpc.aws_subnet.this["database-a"]
  id       = each.value
}

import {
  for_each = local.seed_network == null ? {} : { seed = local.seed_network["subnet_firewall-a"] }
  to       = module.vpc.aws_subnet.this["firewall-a"]
  id       = each.value
}

import {
  for_each = local.seed_network == null ? {} : { seed = local.seed_network["route_table_public-a"] }
  to       = module.vpc.aws_route_table.this["public-a"]
  id       = each.value
}

import {
  for_each = local.seed_network == null ? {} : { seed = local.seed_network["route_table_public-b"] }
  to       = module.vpc.aws_route_table.this["public-b"]
  id       = each.value
}

import {
  for_each = local.seed_network == null ? {} : { seed = local.seed_network["route_table_app-a"] }
  to       = module.vpc.aws_route_table.this["app-a"]
  id       = each.value
}

import {
  for_each = local.seed_network == null ? {} : { seed = local.seed_network["route_table_database-a"] }
  to       = module.vpc.aws_route_table.this["database-a"]
  id       = each.value
}

import {
  for_each = local.seed_network == null ? {} : { seed = local.seed_network["route_table_firewall-a"] }
  to       = module.vpc.aws_route_table.this["firewall-a"]
  id       = each.value
}

import {
  for_each = local.seed_network == null ? {} : { seed = local.seed_network["route_association_public-a"] }
  to       = module.vpc.aws_route_table_association.this["public-a"]
  id       = each.value
}

import {
  for_each = local.seed_network == null ? {} : { seed = local.seed_network["route_association_public-b"] }
  to       = module.vpc.aws_route_table_association.this["public-b"]
  id       = each.value
}

import {
  for_each = local.seed_network == null ? {} : { seed = local.seed_network["route_association_app-a"] }
  to       = module.vpc.aws_route_table_association.this["app-a"]
  id       = each.value
}

import {
  for_each = local.seed_network == null ? {} : { seed = local.seed_network["route_association_database-a"] }
  to       = module.vpc.aws_route_table_association.this["database-a"]
  id       = each.value
}

import {
  for_each = local.seed_network == null ? {} : { seed = local.seed_network["route_association_firewall-a"] }
  to       = module.vpc.aws_route_table_association.this["firewall-a"]
  id       = each.value
}

import {
  for_each = local.seed_network == null ? {} : { seed = "${local.seed_network["route_table_public-a"]}_0.0.0.0/0" }
  to       = module.vpc.aws_route.public_default["public-a"]
  id       = each.value
}

import {
  for_each = local.seed_network == null ? {} : { seed = "${local.seed_network["route_table_public-b"]}_0.0.0.0/0" }
  to       = module.vpc.aws_route.public_default["public-b"]
  id       = each.value
}
