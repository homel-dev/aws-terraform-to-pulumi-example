# Preserve the already-adopted AWS resource addresses when the module
# changes from one VPC to per-YAML for_each instances. These are state-only
# address moves; they do not create, replace, or delete AWS resources.
moved {
  from = module.vpc.aws_vpc.this
  to   = module.vpc.aws_vpc.this["vpc"]
}

moved {
  from = module.vpc.aws_internet_gateway.this
  to   = module.vpc.aws_internet_gateway.this["vpc"]
}

moved {
  from = module.vpc.aws_subnet.this["public-a"]
  to   = module.vpc.aws_subnet.this["vpc/public-a"]
}

moved {
  from = module.vpc.aws_subnet.this["public-b"]
  to   = module.vpc.aws_subnet.this["vpc/public-b"]
}

moved {
  from = module.vpc.aws_subnet.this["app-a"]
  to   = module.vpc.aws_subnet.this["vpc/app-a"]
}

moved {
  from = module.vpc.aws_subnet.this["database-a"]
  to   = module.vpc.aws_subnet.this["vpc/database-a"]
}

moved {
  from = module.vpc.aws_subnet.this["firewall-a"]
  to   = module.vpc.aws_subnet.this["vpc/firewall-a"]
}

moved {
  from = module.vpc.aws_route_table.this["public-a"]
  to   = module.vpc.aws_route_table.this["vpc/public-a"]
}

moved {
  from = module.vpc.aws_route_table.this["public-b"]
  to   = module.vpc.aws_route_table.this["vpc/public-b"]
}

moved {
  from = module.vpc.aws_route_table.this["app-a"]
  to   = module.vpc.aws_route_table.this["vpc/app-a"]
}

moved {
  from = module.vpc.aws_route_table.this["database-a"]
  to   = module.vpc.aws_route_table.this["vpc/database-a"]
}

moved {
  from = module.vpc.aws_route_table.this["firewall-a"]
  to   = module.vpc.aws_route_table.this["vpc/firewall-a"]
}

moved {
  from = module.vpc.aws_route_table_association.this["public-a"]
  to   = module.vpc.aws_route_table_association.this["vpc/public-a"]
}

moved {
  from = module.vpc.aws_route_table_association.this["public-b"]
  to   = module.vpc.aws_route_table_association.this["vpc/public-b"]
}

moved {
  from = module.vpc.aws_route_table_association.this["app-a"]
  to   = module.vpc.aws_route_table_association.this["vpc/app-a"]
}

moved {
  from = module.vpc.aws_route_table_association.this["database-a"]
  to   = module.vpc.aws_route_table_association.this["vpc/database-a"]
}

moved {
  from = module.vpc.aws_route_table_association.this["firewall-a"]
  to   = module.vpc.aws_route_table_association.this["vpc/firewall-a"]
}

moved {
  from = module.vpc.aws_route.public_default["public-a"]
  to   = module.vpc.aws_route.public_default["vpc/public-a"]
}

moved {
  from = module.vpc.aws_route.public_default["public-b"]
  to   = module.vpc.aws_route.public_default["vpc/public-b"]
}
