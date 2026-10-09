resource "aws_lb" "this" {
  for_each                   = local.configs
  name                       = substr("${local.business_unit}-${local.environment}-${each.key == "compute" ? "poc" : each.key}", 0, 32)
  internal                   = false
  load_balancer_type         = "application"
  security_groups            = [aws_security_group.alb[each.key].id]
  subnets                    = [for name in each.value.alb.public_subnets : local.vpc_states[each.key].subnet_ids[name]]
  drop_invalid_header_fields = true

  access_logs {
    bucket  = local.logging_bundles[each.key].audit_bucket_name
    prefix  = "alb"
    enabled = true
  }
}

resource "aws_lb_target_group" "application" {
  for_each    = local.configs
  name        = substr("${local.business_unit}-${local.environment}-app${each.key == "compute" ? "" : "-${each.key}"}", 0, 32)
  port        = each.value.application.port
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = local.vpc_states[each.key].vpc_id

  health_check {
    path                = each.value.application.health_check_path
    protocol            = "HTTP"
    port                = "traffic-port"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 15
    matcher             = "200-399"
  }
}

resource "aws_lb_listener" "https" {
  for_each          = local.configs
  load_balancer_arn = aws_lb.this[each.key].arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = each.value.alb.tls_policy
  certificate_arn   = local.acm_certificates[each.key]

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.application[each.key].arn
  }
}
