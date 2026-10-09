resource "aws_ec2_managed_prefix_list" "approved_clients" {
  for_each = local.configs
  name           = "${local.name_prefixes[each.key]}-approved-clients"
  address_family = "IPv4"
  max_entries    = max(1, length(each.value.approved_ingress_cidrs))
  tags         = merge(local.common_tags, try(each.value.tags, {}))

  dynamic "entry" {
    for_each = toset(each.value.approved_ingress_cidrs)
    content {
      cidr        = entry.value
      description = "Approved client source"
    }
  }
}

resource "aws_security_group" "alb" {
  for_each = local.configs
  name        = "${local.name_prefixes[each.key]}-alb"
  description = "Approved HTTPS ingress; application-only egress"
  vpc_id      = local.vpc_states[each.key].vpc_id
  tags        = merge(local.common_tags, try(each.value.tags, {}))
}

resource "aws_security_group" "application" {
  for_each = local.configs
  name        = "${local.name_prefixes[each.key]}-app"
  description = "Application CDE boundary"
  vpc_id      = local.vpc_states[each.key].vpc_id
  tags        = merge(local.common_tags, try(each.value.tags, {}))
}

resource "aws_security_group" "database" {
  for_each = local.configs
  name        = "${local.name_prefixes[each.key]}-db"
  description = "Database CDE boundary"
  vpc_id      = local.vpc_states[each.key].vpc_id
  tags        = merge(local.common_tags, try(each.value.tags, {}))
}

resource "aws_security_group" "endpoints" {
  for_each = local.configs
  name        = "${local.name_prefixes[each.key]}-endpoints"
  description = "Private AWS interface endpoints"
  vpc_id      = local.vpc_states[each.key].vpc_id
  tags        = merge(local.common_tags, try(each.value.tags, {}))
}

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  for_each = local.configs
  security_group_id = aws_security_group.alb[each.key].id
  prefix_list_id    = aws_ec2_managed_prefix_list.approved_clients[each.key].id
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  description       = "IN-01 approved HTTPS"
}

resource "aws_vpc_security_group_egress_rule" "alb_to_application" {
  for_each = local.configs
  security_group_id            = aws_security_group.alb[each.key].id
  referenced_security_group_id = aws_security_group.application[each.key].id
  ip_protocol                  = "tcp"
  from_port                    = each.value.application.port
  to_port                      = each.value.application.port
  description                  = "OUT-01 ALB to application"
}

resource "aws_vpc_security_group_ingress_rule" "application_from_alb" {
  for_each = local.configs
  security_group_id            = aws_security_group.application[each.key].id
  referenced_security_group_id = aws_security_group.alb[each.key].id
  ip_protocol                  = "tcp"
  from_port                    = each.value.application.port
  to_port                      = each.value.application.port
  description                  = "IN-02 ALB to application"
}

resource "aws_vpc_security_group_egress_rule" "application_to_database" {
  for_each = local.configs
  security_group_id            = aws_security_group.application[each.key].id
  referenced_security_group_id = aws_security_group.database[each.key].id
  ip_protocol                  = "tcp"
  from_port                    = each.value.database.port
  to_port                      = each.value.database.port
  description                  = "OUT-02 application to database"
}

resource "aws_vpc_security_group_egress_rule" "application_https" {
  for_each = local.configs
  security_group_id = aws_security_group.application[each.key].id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  description       = "OUT-03 HTTPS; route forces Internet path through Network Firewall"
}

resource "aws_vpc_security_group_ingress_rule" "database_from_application" {
  for_each = local.configs
  security_group_id            = aws_security_group.database[each.key].id
  referenced_security_group_id = aws_security_group.application[each.key].id
  ip_protocol                  = "tcp"
  from_port                    = each.value.database.port
  to_port                      = each.value.database.port
  description                  = "IN-03 application to database"
}

resource "aws_vpc_security_group_egress_rule" "application_to_endpoints" {
  for_each = local.configs
  security_group_id            = aws_security_group.application[each.key].id
  referenced_security_group_id = aws_security_group.endpoints[each.key].id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
}

resource "aws_vpc_security_group_egress_rule" "database_to_endpoints" {
  for_each = local.configs
  security_group_id            = aws_security_group.database[each.key].id
  referenced_security_group_id = aws_security_group.endpoints[each.key].id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
}

resource "aws_vpc_security_group_ingress_rule" "endpoints_from_application" {
  for_each = local.configs
  security_group_id            = aws_security_group.endpoints[each.key].id
  referenced_security_group_id = aws_security_group.application[each.key].id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
}

resource "aws_vpc_security_group_ingress_rule" "endpoints_from_database" {
  for_each = local.configs
  security_group_id            = aws_security_group.endpoints[each.key].id
  referenced_security_group_id = aws_security_group.database[each.key].id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
}
