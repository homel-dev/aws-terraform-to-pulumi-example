# The initial broad rules are deliberately retained during import. Remediation
# is a separate reviewed change after Terraform ownership is established.
resource "aws_security_group" "alb" {
  name        = "${local.name_prefix}-alb"
  description = "Disposable MyOrg brownfield alb initial SG"
  vpc_id      = local.seed_ids.vpc_id

  ingress {
    protocol    = "tcp"
    from_port   = 80
    to_port     = 80
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    protocol    = "tcp"
    from_port   = 443
    to_port     = 443
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.seed_tags
}

resource "aws_security_group" "application" {
  name        = "${local.name_prefix}-app"
  description = "Disposable MyOrg brownfield app initial SG"
  vpc_id      = local.seed_ids.vpc_id

  ingress {
    protocol    = "tcp"
    from_port   = 80
    to_port     = 80
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    protocol        = "tcp"
    from_port       = 8080
    to_port         = 8080
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.seed_tags
}

resource "aws_security_group" "database" {
  name        = "${local.name_prefix}-db"
  description = "Disposable MyOrg brownfield db initial SG"
  vpc_id      = local.seed_ids.vpc_id

  ingress {
    protocol    = "tcp"
    from_port   = 80
    to_port     = 80
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    protocol        = "tcp"
    from_port       = 3306
    to_port         = 3306
    security_groups = [aws_security_group.application.id]
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.seed_tags
}
