output "vpcs" {
  description = "VPCs indexed by YAML filename (without .yml)."
  value = {
    for vpc_key, vpc in aws_vpc.this : vpc_key => {
      vpc_id              = vpc.id
      vpc_cidr            = vpc.cidr_block
      internet_gateway_id = aws_internet_gateway.this[vpc_key].id

      subnet_ids = {
        for subnet_key, subnet in local.subnets : subnet.subnet_key => aws_subnet.this[subnet_key].id
        if subnet.vpc_key == vpc_key
      }
      subnet_cidrs = {
        for subnet_key, subnet in local.subnets : subnet.subnet_key => aws_subnet.this[subnet_key].cidr_block
        if subnet.vpc_key == vpc_key
      }
      subnet_availability_zones = {
        for subnet_key, subnet in local.subnets : subnet.subnet_key => aws_subnet.this[subnet_key].availability_zone
        if subnet.vpc_key == vpc_key
      }
      route_table_ids = {
        for subnet_key, subnet in local.subnets : subnet.subnet_key => aws_route_table.this[subnet_key].id
        if subnet.vpc_key == vpc_key
      }
    }
  }
}
