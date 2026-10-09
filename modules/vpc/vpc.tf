resource "aws_vpc" "this" {
  for_each = local.vpcs

  cidr_block           = each.value.cidr
  enable_dns_support   = each.value.enable_dns_support
  enable_dns_hostnames = each.value.enable_dns_hostnames

  tags = merge(try(each.value.tags, {}), { Name = each.value.name })
}

resource "aws_internet_gateway" "this" {
  for_each = local.vpcs

  vpc_id = aws_vpc.this[each.key].id
  tags   = merge(try(each.value.tags, {}), { Name = "${each.value.name}-igw" })
}

resource "aws_subnet" "this" {
  for_each = local.subnets

  vpc_id                  = aws_vpc.this[each.value.vpc_key].id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.availability_zone
  map_public_ip_on_launch = false

  tags = merge(
    try(local.vpcs[each.value.vpc_key].tags, {}),
    try(each.value.tags, {}),
    {
      Name       = "${local.vpcs[each.value.vpc_key].name}-${each.value.subnet_key}"
      SubnetRole = each.value.type
    }
  )
}

resource "aws_route_table" "this" {
  for_each = local.subnets
  vpc_id   = aws_vpc.this[each.value.vpc_key].id

  tags = merge(try(local.vpcs[each.value.vpc_key].tags, {}), {
    Name       = "${local.vpcs[each.value.vpc_key].name}-${each.value.subnet_key}"
    SubnetRole = each.value.type
  })
}

resource "aws_route_table_association" "this" {
  for_each       = local.subnets
  subnet_id      = aws_subnet.this[each.key].id
  route_table_id = aws_route_table.this[each.key].id
}

resource "aws_route" "public_default" {
  for_each = local.public_subnets

  route_table_id         = aws_route_table.this[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this[each.value.vpc_key].id
}
