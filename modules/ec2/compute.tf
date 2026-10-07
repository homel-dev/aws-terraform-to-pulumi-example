data "aws_ssm_parameter" "application_ami" {
  name = local.config.application.ami_ssm_parameter
}
data "aws_ssm_parameter" "database_ami" {
  name = local.config.database.ami_ssm_parameter
}

resource "aws_secretsmanager_secret" "database" {
  name                    = "${local.prefix}/database"
  recovery_window_in_days = 0
}

resource "aws_launch_template" "application" {
  name_prefix   = "${local.prefix}-app-"
  image_id      = data.aws_ssm_parameter.application_ami.value
  instance_type = local.config.application.instance_type

  iam_instance_profile {
    name = local.iam_state.application_instance_profile_name
  }

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [aws_security_group.application.id]
  }

  block_device_mappings {
    device_name = "/dev/sda1"
    ebs {
      encrypted             = true
      delete_on_termination = true
      volume_type           = "gp3"
      volume_size           = local.config.application.root_volume_gib
    }
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  user_data = base64encode(templatefile("${path.module}/templates/application-user-data.sh.tftpl", {
    artifact_url      = local.config.application.bootstrap.artifact_url
    artifact_path     = local.config.application.bootstrap.artifact_path
    artifact_sha256   = try(local.config.application.bootstrap.artifact_sha256, "")
    install_command   = local.config.application.bootstrap.install_command
    service_name      = local.config.application.bootstrap.service_name
    database_secret   = aws_secretsmanager_secret.database.name
    runtime_https_url = local.config.application.runtime_https_url
  }))

  tag_specifications {
    resource_type = "instance"
    tags          = merge(local.common_tags, { Name = "${local.prefix}-app" })
  }

  tag_specifications {
    resource_type = "volume"
    tags          = merge(local.common_tags, { Name = "${local.prefix}-app" })
  }
}

resource "aws_autoscaling_group" "application" {
  name                = "${local.prefix}-app"
  min_size            = local.config.application.min_size
  max_size            = local.config.application.max_size
  desired_capacity    = local.config.application.desired_capacity
  vpc_zone_identifier = [local.vpc_state.subnet_ids[local.config.application.subnet]]
  target_group_arns   = [aws_lb_target_group.application.arn]
  health_check_type   = "ELB"

  launch_template {
    id      = aws_launch_template.application.id
    version = aws_launch_template.application.latest_version
  }

  dynamic "tag" {
    for_each = merge(local.common_tags, { Name = "${local.prefix}-app" })
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }
}

resource "aws_instance" "database" {
  ami                         = data.aws_ssm_parameter.database_ami.value
  instance_type               = local.config.database.instance_type
  subnet_id                   = local.vpc_state.subnet_ids[local.config.database.subnet]
  vpc_security_group_ids      = [aws_security_group.database.id]
  iam_instance_profile        = local.iam_state.database_instance_profile_name
  associate_public_ip_address = false

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  root_block_device {
    encrypted             = true
    delete_on_termination = true
    volume_type           = "gp3"
    volume_size           = local.config.database.root_volume_gib
    tags = merge(local.common_tags, {
      Name   = "${local.prefix}-db"
      Backup = "dlm"
    })
  }

  user_data = base64encode(templatefile("${path.module}/templates/database-user-data.sh.tftpl", {
    region      = local.config.region
    secret_name = aws_secretsmanager_secret.database.name
    database    = local.config.database.name
    username    = local.config.database.username
  }))

  tags = merge(local.common_tags, { Name = "${local.prefix}-db" })
}
