output "vpc_id" {
  value = aws_vpc.this.id
}

output "vpc_cidr" {
  value = aws_vpc.this.cidr_block
}

output "internet_gateway_id" {
  value = aws_internet_gateway.this.id
}

output "subnet_ids" {
  value = { for name, subnet in aws_subnet.this : name => subnet.id }
}

output "subnet_cidrs" {
  value = { for name, subnet in aws_subnet.this : name => subnet.cidr_block }
}

output "subnet_availability_zones" {
  value = { for name, subnet in aws_subnet.this : name => subnet.availability_zone }
}

output "route_table_ids" {
  value = { for name, rt in aws_route_table.this : name => rt.id }
}
