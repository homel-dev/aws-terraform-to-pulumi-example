resource "aws_lb" "this" {
  name                       = substr("${local.business_unit}-${local.environment}-poc", 0, 32)
  internal                   = false
  load_balancer_type         = "application"
  security_groups            = [aws_security_group.alb.id]
  subnets                    = [for name in local.config.alb.public_subnets : local.vpc_state.subnet_ids[name]]
  drop_invalid_header_fields = true

  access_logs {
    bucket  = local.logging_state.audit_bucket_name
    prefix  = "alb"
    enabled = true
  }
}

resource "aws_lb_target_group" "application" {
  name        = substr("${local.business_unit}-${local.environment}-app", 0, 32)
  port        = local.config.application.port
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = local.vpc_state.vpc_id

  health_check {
    path                = local.config.application.health_check_path
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
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = local.config.alb.tls_policy
  certificate_arn   = local.acm_state.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.application.arn
  }
}
