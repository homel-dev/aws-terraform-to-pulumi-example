output "firewall_arn" {
  value = aws_networkfirewall_firewall.this.arn
}

output "firewall_endpoint_id" {
  value = local.firewall_endpoint_id
}

output "nat_gateway_id" {
  value = aws_nat_gateway.this.id
}
