resource "aws_networkfirewall_rule_group" "tls_allowlist" {
  for_each    = local.configs
  capacity    = 100
  name        = substr("${local.prefix}-tls-allowlist${each.key == "egress" ? "" : "-${each.key}"}", 0, 128)
  description = "POC TLS SNI egress allowlist"
  type        = "STATEFUL"

  rule_group {
    rules_source {
      rules_source_list {
        generated_rules_type = "ALLOWLIST"
        target_types         = ["TLS_SNI"]
        targets              = toset(each.value.allowed_tls_domains)
      }
    }
  }
}

resource "aws_networkfirewall_firewall_policy" "this" {
  for_each = local.configs
  name     = substr("${local.prefix}-${each.value.name}", 0, 128)
  firewall_policy {
    stateless_default_actions          = ["aws:forward_to_sfe"]
    stateless_fragment_default_actions = ["aws:forward_to_sfe"]
    stateful_rule_group_reference {
      resource_arn = aws_networkfirewall_rule_group.tls_allowlist[each.key].arn
    }
  }
}

resource "aws_networkfirewall_firewall" "this" {
  for_each            = local.configs
  name                = substr("${local.prefix}-${each.value.name}", 0, 128)
  firewall_policy_arn = aws_networkfirewall_firewall_policy.this[each.key].arn
  vpc_id              = local.vpc_states[each.key].vpc_id

  subnet_mapping {
    subnet_id       = local.vpc_states[each.key].subnet_ids[each.value.firewall_subnet]
    ip_address_type = "IPV4"
  }
}

locals {
  firewall_endpoint_ids = {
    for id, config in local.configs : id => one([
      for sync_state in aws_networkfirewall_firewall.this[id].firewall_status[0].sync_states :
      sync_state.attachment[0].endpoint_id
      if sync_state.attachment[0].subnet_id == local.vpc_states[id].subnet_ids[config.firewall_subnet]
    ])
  }
}

resource "aws_cloudwatch_log_group" "firewall" {
  for_each          = local.configs
  name              = "/aws/network-firewall/${local.prefix}${each.key == "egress" ? "" : "-${each.key}"}"
  retention_in_days = each.value.log_retention_days
}

resource "aws_networkfirewall_logging_configuration" "this" {
  for_each     = local.configs
  firewall_arn = aws_networkfirewall_firewall.this[each.key].arn
  logging_configuration {
    log_destination_config {
      log_destination      = { logGroup = aws_cloudwatch_log_group.firewall[each.key].name }
      log_destination_type = "CloudWatchLogs"
      log_type             = "ALERT"
    }
    log_destination_config {
      log_destination      = { logGroup = aws_cloudwatch_log_group.firewall[each.key].name }
      log_destination_type = "CloudWatchLogs"
      log_type             = "FLOW"
    }
  }
}

resource "aws_eip" "nat" {
  for_each = local.configs
  domain   = "vpc"
}

resource "aws_nat_gateway" "this" {
  for_each      = local.configs
  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = local.vpc_states[each.key].subnet_ids[each.value.nat_public_subnet]
}

resource "aws_route" "application_default" {
  for_each               = local.configs
  route_table_id         = local.vpc_states[each.key].route_table_ids[each.value.application_subnet]
  destination_cidr_block = "0.0.0.0/0"
  vpc_endpoint_id        = local.firewall_endpoint_ids[each.key]
}

resource "aws_route" "firewall_default" {
  for_each               = local.configs
  route_table_id         = local.vpc_states[each.key].route_table_ids[each.value.firewall_subnet]
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[each.key].id
}

resource "aws_route" "nat_return_to_application" {
  for_each               = local.configs
  route_table_id         = local.vpc_states[each.key].route_table_ids[each.value.nat_public_subnet]
  destination_cidr_block = local.vpc_states[each.key].subnet_cidrs[each.value.application_subnet]
  vpc_endpoint_id        = local.firewall_endpoint_ids[each.key]
}
