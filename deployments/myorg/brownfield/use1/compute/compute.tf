resource "aws_instance" "database" {
  ami                         = local.instance_ami
  instance_type               = local.seed_ids.database_instance_type
  subnet_id                   = local.seed_ids["subnet_public-a"]
  vpc_security_group_ids      = [aws_security_group.database.id]
  associate_public_ip_address = true
  user_data                   = file("${path.root}/../../../../../scripts/seed/database-user-data.sh")

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  tags        = merge(local.seed_tags, { Name = "${local.name_prefix}-db" })
  volume_tags = local.seed_tags
}

resource "aws_launch_template" "application" {
  name          = "${local.name_prefix}-app"
  image_id      = local.instance_ami
  instance_type = local.seed_ids.application_instance_type
  user_data     = local.seed_ids.application_user_data_base64

  network_interfaces {
    device_index                = 0
    associate_public_ip_address = true
    security_groups             = [aws_security_group.application.id]
    delete_on_termination       = true
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  tag_specifications {
    resource_type = "instance"
    tags          = merge(local.seed_tags, { Name = "${local.name_prefix}-app" })
  }

  tag_specifications {
    resource_type = "volume"
    tags          = local.seed_tags
  }

  tags = local.seed_tags
}

resource "aws_autoscaling_group" "application" {
  name                      = "${local.name_prefix}-app"
  min_size                  = 1
  max_size                  = 1
  desired_capacity          = 1
  health_check_type         = "ELB"
  health_check_grace_period = 300
  vpc_zone_identifier       = [local.seed_ids["subnet_public-a"], local.seed_ids["subnet_public-b"]]
  target_group_arns         = [aws_lb_target_group.application.arn]

  launch_template {
    id      = aws_launch_template.application.id
    version = "1"
  }

  tag {
    key                 = "MyOrgSeedId"
    value               = local.seed.seed_id
    propagate_at_launch = true
  }

  tag {
    key                 = "ManagedBy"
    value               = "myorg-aws-seed"
    propagate_at_launch = true
  }
}
