resource "aws_vpc" "this" {
  cidr_block           = local.config.cidr
  enable_dns_support   = local.config.enable_dns_support
  enable_dns_hostnames = local.config.enable_dns_hostnames

  tags = merge(local.common_tags, { Name = local.prefix })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = merge(local.common_tags, { Name = "${local.prefix}-igw" })
}

resource "aws_subnet" "this" {
  for_each = local.config.subnets

  vpc_id                  = aws_vpc.this.id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.availability_zone
  map_public_ip_on_launch = false

  tags = merge(local.common_tags, try(each.value.tags, {}), {
    Name       = "${local.prefix}-${each.key}"
    SubnetRole = each.value.type
  })
}

resource "aws_route_table" "this" {
  for_each = local.config.subnets
  vpc_id   = aws_vpc.this.id

  tags = merge(local.common_tags, {
    Name       = "${local.prefix}-${each.key}"
    SubnetRole = each.value.type
  })
}

resource "aws_route_table_association" "this" {
  for_each       = local.config.subnets
  subnet_id      = aws_subnet.this[each.key].id
  route_table_id = aws_route_table.this[each.key].id
}

resource "aws_route" "public_default" {
  for_each = local.subnets_by_type.public

  route_table_id         = aws_route_table.this[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}
