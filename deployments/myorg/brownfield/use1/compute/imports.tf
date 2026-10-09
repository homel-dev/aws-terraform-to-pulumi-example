# Every seed-owned infrastructure object is imported to one Terraform address.
# The ASG owns the application instance: never import the ASG member as a
# standalone aws_instance, which would create competing lifecycle owners.
import {
  to = aws_security_group.alb
  id = local.seed_ids.security_group_alb
}

import {
  to = aws_security_group.application
  id = local.seed_ids.security_group_app
}

import {
  to = aws_security_group.database
  id = local.seed_ids.security_group_db
}

import {
  to = aws_instance.database
  id = local.seed_ids.database_instance_id
}

import {
  to = aws_launch_template.application
  id = local.seed_ids.launch_template_id
}

import {
  to = aws_autoscaling_group.application
  id = local.seed_ids.asg_name
}

import {
  to = aws_lb.this
  id = local.seed_ids.alb_arn
}

import {
  to = aws_lb_target_group.application
  id = local.seed_ids.target_group_arn
}

import {
  to = aws_lb_listener.http
  id = local.seed_ids.listener_http_arn
}

import {
  to = aws_lb_listener.https
  id = local.seed_ids.listener_https_arn
}

import {
  for_each = try(local.seed_ids.owned_certificate_arn, "") == "" ? {} : { certificate = local.seed_ids.owned_certificate_arn }
  to       = aws_acm_certificate.seed[0]
  id       = each.value
}
