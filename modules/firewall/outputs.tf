output "firewalls" {
  value = {
    for id, firewall in aws_networkfirewall_firewall.this : id => {
      firewall_arn         = firewall.arn
      firewall_endpoint_id = local.firewall_endpoint_ids[id]
      nat_gateway_id       = aws_nat_gateway.this[id].id
    }
  }
}

output "firewall_arn" {
  value = aws_networkfirewall_firewall.this["egress"].arn
}

output "firewall_endpoint_id" {
  value = local.firewall_endpoint_ids["egress"]
}

output "nat_gateway_id" {
  value = aws_nat_gateway.this["egress"].id
}
