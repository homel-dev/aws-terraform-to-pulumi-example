resource "aws_acm_certificate" "seed" {
  count            = try(local.seed_ids.owned_certificate_arn, "") == "" ? 0 : 1
  certificate_body = file(local.seed_ids.certificate_path)
  private_key      = file(local.seed_ids.private_key_path)
  tags             = local.seed_tags
}

resource "aws_lb_target_group" "application" {
  name        = "${local.name_prefix}-app"
  port        = 8080
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = local.seed_ids.vpc_id

  health_check {
    path    = "/"
    matcher = "200"
  }

  tags = local.seed_tags
}

resource "aws_lb" "this" {
  name               = "${local.name_prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  subnets            = [local.seed_ids["subnet_public-a"], local.seed_ids["subnet_public-b"]]
  security_groups    = [aws_security_group.alb.id]
  tags               = local.seed_tags
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.application.arn
  }

  tags = local.seed_tags
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = try(local.seed_ids.owned_certificate_arn, "") != "" ? aws_acm_certificate.seed[0].arn : local.seed_ids.external_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.application.arn
  }

  tags = local.seed_tags
}
