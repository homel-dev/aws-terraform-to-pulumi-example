resource "aws_ec2_managed_prefix_list" "approved_clients" {
  name           = "${local.prefix}-approved-clients"
  address_family = "IPv4"
  max_entries    = max(1, length(local.config.approved_ingress_cidrs))

  dynamic "entry" {
    for_each = toset(local.config.approved_ingress_cidrs)
    content {
      cidr        = entry.value
      description = "Approved client source"
    }
  }
}

resource "aws_security_group" "alb" {
  name        = "${local.prefix}-alb"
  description = "Approved HTTPS ingress; application-only egress"
  vpc_id      = local.vpc_state.vpc_id
}

resource "aws_security_group" "application" {
  name        = "${local.prefix}-app"
  description = "Application CDE boundary"
  vpc_id      = local.vpc_state.vpc_id
}

resource "aws_security_group" "database" {
  name        = "${local.prefix}-db"
  description = "Database CDE boundary"
  vpc_id      = local.vpc_state.vpc_id
}

resource "aws_security_group" "endpoints" {
  name        = "${local.prefix}-endpoints"
  description = "Private AWS interface endpoints"
  vpc_id      = local.vpc_state.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  security_group_id = aws_security_group.alb.id
  prefix_list_id    = aws_ec2_managed_prefix_list.approved_clients.id
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  description       = "IN-01 approved HTTPS"
}

resource "aws_vpc_security_group_egress_rule" "alb_to_application" {
  security_group_id            = aws_security_group.alb.id
  referenced_security_group_id = aws_security_group.application.id
  ip_protocol                  = "tcp"
  from_port                    = local.config.application.port
  to_port                      = local.config.application.port
  description                  = "OUT-01 ALB to application"
}

resource "aws_vpc_security_group_ingress_rule" "application_from_alb" {
  security_group_id            = aws_security_group.application.id
  referenced_security_group_id = aws_security_group.alb.id
  ip_protocol                  = "tcp"
  from_port                    = local.config.application.port
  to_port                      = local.config.application.port
  description                  = "IN-02 ALB to application"
}

resource "aws_vpc_security_group_egress_rule" "application_to_database" {
  security_group_id            = aws_security_group.application.id
  referenced_security_group_id = aws_security_group.database.id
  ip_protocol                  = "tcp"
  from_port                    = local.config.database.port
  to_port                      = local.config.database.port
  description                  = "OUT-02 application to database"
}

resource "aws_vpc_security_group_egress_rule" "application_https" {
  security_group_id = aws_security_group.application.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  description       = "OUT-03 HTTPS; route forces Internet path through Network Firewall"
}

resource "aws_vpc_security_group_ingress_rule" "database_from_application" {
  security_group_id            = aws_security_group.database.id
  referenced_security_group_id = aws_security_group.application.id
  ip_protocol                  = "tcp"
  from_port                    = local.config.database.port
  to_port                      = local.config.database.port
  description                  = "IN-03 application to database"
}

resource "aws_vpc_security_group_egress_rule" "application_to_endpoints" {
  security_group_id            = aws_security_group.application.id
  referenced_security_group_id = aws_security_group.endpoints.id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
}

resource "aws_vpc_security_group_egress_rule" "database_to_endpoints" {
  security_group_id            = aws_security_group.database.id
  referenced_security_group_id = aws_security_group.endpoints.id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
}

resource "aws_vpc_security_group_ingress_rule" "endpoints_from_application" {
  security_group_id            = aws_security_group.endpoints.id
  referenced_security_group_id = aws_security_group.application.id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
}

resource "aws_vpc_security_group_ingress_rule" "endpoints_from_database" {
  security_group_id            = aws_security_group.endpoints.id
  referenced_security_group_id = aws_security_group.database.id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
}
