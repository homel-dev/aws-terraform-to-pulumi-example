resource "aws_route53_zone" "this" {
  for_each = local.zones

  name          = each.value.name
  comment       = try(each.value.comment, null)
  force_destroy = try(each.value.force_destroy, false)
  tags          = merge(local.defaults.tags, try(each.value.tags, {}))

  dynamic "vpc" {
    for_each = try(each.value.private, false) ? try(each.value.vpc_associations, []) : []
    content {
      vpc_id = vpc.value
    }
  }
}
