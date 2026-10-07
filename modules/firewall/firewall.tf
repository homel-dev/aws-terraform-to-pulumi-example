resource "aws_networkfirewall_rule_group" "tls_allowlist" {
  capacity    = 100
  name        = substr("${local.prefix}-tls-allowlist", 0, 128)
  description = "POC TLS SNI egress allowlist"
  type        = "STATEFUL"

  rule_group {
    rules_source {
      rules_source_list {
        generated_rules_type = "ALLOWLIST"
        target_types         = ["TLS_SNI"]
        targets              = toset(local.config.allowed_tls_domains)
      }
    }
  }
}

resource "aws_networkfirewall_firewall_policy" "this" {
  name = substr("${local.prefix}-${local.config.name}", 0, 128)
  firewall_policy {
    stateless_default_actions          = ["aws:forward_to_sfe"]
    stateless_fragment_default_actions = ["aws:forward_to_sfe"]
    stateful_rule_group_reference {
      resource_arn = aws_networkfirewall_rule_group.tls_allowlist.arn
    }
  }
}

resource "aws_networkfirewall_firewall" "this" {
  name                = substr("${local.prefix}-${local.config.name}", 0, 128)
  firewall_policy_arn = aws_networkfirewall_firewall_policy.this.arn
  vpc_id              = local.vpc_state.vpc_id

  subnet_mapping {
    subnet_id       = local.vpc_state.subnet_ids[local.config.firewall_subnet]
    ip_address_type = "IPV4"
  }
}

locals {
  firewall_endpoint_id = one([
    for sync_state in aws_networkfirewall_firewall.this.firewall_status[0].sync_states :
    sync_state.attachment[0].endpoint_id
    if sync_state.attachment[0].subnet_id == local.vpc_state.subnet_ids[local.config.firewall_subnet]
  ])
}

resource "aws_cloudwatch_log_group" "firewall" {
  name              = "/aws/network-firewall/${local.prefix}"
  retention_in_days = local.config.log_retention_days
}

resource "aws_networkfirewall_logging_configuration" "this" {
  firewall_arn = aws_networkfirewall_firewall.this.arn
  logging_configuration {
    log_destination_config {
      log_destination      = { logGroup = aws_cloudwatch_log_group.firewall.name }
      log_destination_type = "CloudWatchLogs"
      log_type             = "ALERT"
    }
    log_destination_config {
      log_destination      = { logGroup = aws_cloudwatch_log_group.firewall.name }
      log_destination_type = "CloudWatchLogs"
      log_type             = "FLOW"
    }
  }
}

resource "aws_eip" "nat" {
  domain = "vpc"
}

resource "aws_nat_gateway" "this" {
  allocation_id = aws_eip.nat.id
  subnet_id     = local.vpc_state.subnet_ids[local.config.nat_public_subnet]
}

resource "aws_route" "application_default" {
  route_table_id         = local.vpc_state.route_table_ids[local.config.application_subnet]
  destination_cidr_block = "0.0.0.0/0"
  vpc_endpoint_id        = local.firewall_endpoint_id
}

resource "aws_route" "firewall_default" {
  route_table_id         = local.vpc_state.route_table_ids[local.config.firewall_subnet]
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this.id
}

resource "aws_route" "nat_return_to_application" {
  route_table_id         = local.vpc_state.route_table_ids[local.config.nat_public_subnet]
  destination_cidr_block = local.vpc_state.subnet_cidrs[local.config.application_subnet]
  vpc_endpoint_id        = local.firewall_endpoint_id
}
