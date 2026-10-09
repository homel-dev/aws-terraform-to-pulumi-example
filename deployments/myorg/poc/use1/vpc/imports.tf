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
  to       = module.vpc.aws_vpc.this["vpc"]
  id       = each.value
}

import {
  for_each = local.seed_network == null ? {} : { seed = local.seed_network.internet_gateway_id }
  to       = module.vpc.aws_internet_gateway.this["vpc"]
  id       = each.value
}

import {
  for_each = local.seed_network == null ? {} : { seed = local.seed_network["subnet_public-a"] }
  to       = module.vpc.aws_subnet.this["vpc/public-a"]
  id       = each.value
}

import {
  for_each = local.seed_network == null ? {} : { seed = local.seed_network["subnet_public-b"] }
  to       = module.vpc.aws_subnet.this["vpc/public-b"]
  id       = each.value
}

import {
  for_each = local.seed_network == null ? {} : { seed = local.seed_network["subnet_app-a"] }
  to       = module.vpc.aws_subnet.this["vpc/app-a"]
  id       = each.value
}

import {
  for_each = local.seed_network == null ? {} : { seed = local.seed_network["subnet_database-a"] }
  to       = module.vpc.aws_subnet.this["vpc/database-a"]
  id       = each.value
}

import {
  for_each = local.seed_network == null ? {} : { seed = local.seed_network["subnet_firewall-a"] }
  to       = module.vpc.aws_subnet.this["vpc/firewall-a"]
  id       = each.value
}

import {
  for_each = local.seed_network == null ? {} : { seed = local.seed_network["route_table_public-a"] }
  to       = module.vpc.aws_route_table.this["vpc/public-a"]
  id       = each.value
}

import {
  for_each = local.seed_network == null ? {} : { seed = local.seed_network["route_table_public-b"] }
  to       = module.vpc.aws_route_table.this["vpc/public-b"]
  id       = each.value
}

import {
  for_each = local.seed_network == null ? {} : { seed = local.seed_network["route_table_app-a"] }
  to       = module.vpc.aws_route_table.this["vpc/app-a"]
  id       = each.value
}

import {
  for_each = local.seed_network == null ? {} : { seed = local.seed_network["route_table_database-a"] }
  to       = module.vpc.aws_route_table.this["vpc/database-a"]
  id       = each.value
}

import {
  for_each = local.seed_network == null ? {} : { seed = local.seed_network["route_table_firewall-a"] }
  to       = module.vpc.aws_route_table.this["vpc/firewall-a"]
  id       = each.value
}

import {
  for_each = local.seed_network == null ? {} : { seed = "${local.seed_network["subnet_public-a"]}/${local.seed_network["route_table_public-a"]}" }
  to       = module.vpc.aws_route_table_association.this["vpc/public-a"]
  id       = each.value
}

import {
  for_each = local.seed_network == null ? {} : { seed = "${local.seed_network["subnet_public-b"]}/${local.seed_network["route_table_public-b"]}" }
  to       = module.vpc.aws_route_table_association.this["vpc/public-b"]
  id       = each.value
}

import {
  for_each = local.seed_network == null ? {} : { seed = "${local.seed_network["subnet_app-a"]}/${local.seed_network["route_table_app-a"]}" }
  to       = module.vpc.aws_route_table_association.this["vpc/app-a"]
  id       = each.value
}

import {
  for_each = local.seed_network == null ? {} : { seed = "${local.seed_network["subnet_database-a"]}/${local.seed_network["route_table_database-a"]}" }
  to       = module.vpc.aws_route_table_association.this["vpc/database-a"]
  id       = each.value
}

import {
  for_each = local.seed_network == null ? {} : { seed = "${local.seed_network["subnet_firewall-a"]}/${local.seed_network["route_table_firewall-a"]}" }
  to       = module.vpc.aws_route_table_association.this["vpc/firewall-a"]
  id       = each.value
}

import {
  for_each = local.seed_network == null ? {} : { seed = "${local.seed_network["route_table_public-a"]}_0.0.0.0/0" }
  to       = module.vpc.aws_route.public_default["vpc/public-a"]
  id       = each.value
}

import {
  for_each = local.seed_network == null ? {} : { seed = "${local.seed_network["route_table_public-b"]}_0.0.0.0/0" }
  to       = module.vpc.aws_route.public_default["vpc/public-b"]
  id       = each.value
}
