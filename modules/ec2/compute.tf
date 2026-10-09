data "aws_ssm_parameter" "application_ami" {
  for_each = local.configs
  name     = each.value.application.ami_ssm_parameter
}
data "aws_ssm_parameter" "database_ami" {
  for_each = local.configs
  name     = each.value.database.ami_ssm_parameter
}

resource "aws_secretsmanager_secret" "database" {
  for_each                = local.configs
  name                    = "${local.prefix}/database${each.key == "compute" ? "" : "-${each.key}"}"
  recovery_window_in_days = 0
}

resource "aws_launch_template" "application" {
  for_each      = local.configs
  name_prefix   = "${local.name_prefixes[each.key]}-app-"
  image_id      = data.aws_ssm_parameter.application_ami[each.key].value
  instance_type = each.value.application.instance_type

  iam_instance_profile {
    name = local.iam_groups[each.key].application_instance_profile_name
  }

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [aws_security_group.application[each.key].id]
  }

  block_device_mappings {
    device_name = "/dev/sda1"
    ebs {
      encrypted             = true
      delete_on_termination = true
      volume_type           = "gp3"
      volume_size           = each.value.application.root_volume_gib
    }
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  user_data = base64encode(templatefile("${path.module}/templates/application-user-data.sh.tftpl", {
    artifact_url      = each.value.application.bootstrap.artifact_url
    artifact_path     = each.value.application.bootstrap.artifact_path
    artifact_sha256   = try(each.value.application.bootstrap.artifact_sha256, "")
    install_command   = each.value.application.bootstrap.install_command
    service_name      = each.value.application.bootstrap.service_name
    database_secret   = aws_secretsmanager_secret.database[each.key].name
    runtime_https_url = each.value.application.runtime_https_url
  }))

  tag_specifications {
    resource_type = "instance"
    tags          = merge(local.common_tags, try(each.value.tags, {}), { Name = "${local.name_prefixes[each.key]}-app" })
  }

  tag_specifications {
    resource_type = "volume"
    tags          = merge(local.common_tags, try(each.value.tags, {}), { Name = "${local.name_prefixes[each.key]}-app" })
  }
}

resource "aws_autoscaling_group" "application" {
  for_each            = local.configs
  name                = "${local.name_prefixes[each.key]}-app"
  min_size            = each.value.application.min_size
  max_size            = each.value.application.max_size
  desired_capacity    = each.value.application.desired_capacity
  vpc_zone_identifier = [local.vpc_states[each.key].subnet_ids[each.value.application.subnet]]
  target_group_arns   = [aws_lb_target_group.application[each.key].arn]
  health_check_type   = "ELB"

  launch_template {
    id      = aws_launch_template.application[each.key].id
    version = aws_launch_template.application[each.key].latest_version
  }

  dynamic "tag" {
    for_each = merge(local.common_tags, try(each.value.tags, {}), { Name = "${local.name_prefixes[each.key]}-app" })
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }
}

resource "aws_instance" "database" {
  for_each                    = local.configs
  ami                         = data.aws_ssm_parameter.database_ami[each.key].value
  instance_type               = each.value.database.instance_type
  subnet_id                   = local.vpc_states[each.key].subnet_ids[each.value.database.subnet]
  vpc_security_group_ids      = [aws_security_group.database[each.key].id]
  iam_instance_profile        = local.iam_groups[each.key].database_instance_profile_name
  associate_public_ip_address = false

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  root_block_device {
    encrypted             = true
    delete_on_termination = true
    volume_type           = "gp3"
    volume_size           = each.value.database.root_volume_gib
    tags = merge(local.common_tags, try(each.value.tags, {}), {
      Name   = "${local.name_prefixes[each.key]}-db"
      Backup = "dlm"
    })
  }

  user_data = base64encode(templatefile("${path.module}/templates/database-user-data.sh.tftpl", {
    region      = local.region
    secret_name = aws_secretsmanager_secret.database[each.key].name
    database    = each.value.database.name
    username    = each.value.database.username
  }))

  tags = merge(local.common_tags, try(each.value.tags, {}), { Name = "${local.name_prefixes[each.key]}-db" })
}
