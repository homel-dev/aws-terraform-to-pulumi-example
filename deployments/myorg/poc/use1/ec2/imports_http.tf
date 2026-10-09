# The seed HTTP/80 listener belongs to the final POC EC2 root.
# The other nine Compute import blocks live in imports.tf.
import {
  for_each = var.seed_manifest_path == "" ? {} : {
    compute = jsondecode(file(var.seed_manifest_path)).resources.listener_http_arn
  }
  to = module.ec2.aws_lb_listener.http[each.key]
  id = each.value
}
