moved {
  from = aws_networkfirewall_rule_group.tls_allowlist
  to   = aws_networkfirewall_rule_group.tls_allowlist["egress"]
}

moved {
  from = aws_networkfirewall_firewall_policy.this
  to   = aws_networkfirewall_firewall_policy.this["egress"]
}

moved {
  from = aws_networkfirewall_firewall.this
  to   = aws_networkfirewall_firewall.this["egress"]
}

moved {
  from = aws_cloudwatch_log_group.firewall
  to   = aws_cloudwatch_log_group.firewall["egress"]
}

moved {
  from = aws_networkfirewall_logging_configuration.this
  to   = aws_networkfirewall_logging_configuration.this["egress"]
}

moved {
  from = aws_eip.nat
  to   = aws_eip.nat["egress"]
}

moved {
  from = aws_nat_gateway.this
  to   = aws_nat_gateway.this["egress"]
}

moved {
  from = aws_route.application_default
  to   = aws_route.application_default["egress"]
}

moved {
  from = aws_route.firewall_default
  to   = aws_route.firewall_default["egress"]
}

moved {
  from = aws_route.nat_return_to_application
  to   = aws_route.nat_return_to_application["egress"]
}
