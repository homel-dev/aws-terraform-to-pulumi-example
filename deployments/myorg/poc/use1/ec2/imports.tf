# Seed-to-POC EC2 adoption.  These import blocks only activate when a seed
# manifest path is explicitly supplied.  Transfer prior brownfield ownership
# out of the old remote state BEFORE applying an import plan here.
variable "seed_manifest_path" {
  description = "Absolute path to the seed manifest for adopting Compute into the POC EC2 state"
  type        = string
  default     = ""
}

locals {
  seed_compute = {
    for manifest_path in compact([var.seed_manifest_path]) :
    "compute" => jsondecode(file(manifest_path)).resources
  }
}

import {
  for_each = local.seed_compute
  to       = module.ec2.aws_security_group.alb[each.key]
  id       = each.value.security_group_alb
}

import {
  for_each = local.seed_compute
  to       = module.ec2.aws_security_group.application[each.key]
  id       = each.value.security_group_app
}

import {
  for_each = local.seed_compute
  to       = module.ec2.aws_security_group.database[each.key]
  id       = each.value.security_group_db
}

import {
  for_each = local.seed_compute
  to       = module.ec2.aws_instance.database[each.key]
  id       = each.value.database_instance_id
}

import {
  for_each = local.seed_compute
  to       = module.ec2.aws_launch_template.application[each.key]
  id       = each.value.launch_template_id
}

import {
  for_each = local.seed_compute
  to       = module.ec2.aws_autoscaling_group.application[each.key]
  id       = each.value.asg_name
}

import {
  for_each = local.seed_compute
  to       = module.ec2.aws_lb.this[each.key]
  id       = each.value.alb_arn
}

import {
  for_each = local.seed_compute
  to       = module.ec2.aws_lb_target_group.application[each.key]
  id       = each.value.target_group_arn
}

import {
  for_each = local.seed_compute
  to       = module.ec2.aws_lb_listener.https[each.key]
  id       = each.value.listener_https_arn
}
