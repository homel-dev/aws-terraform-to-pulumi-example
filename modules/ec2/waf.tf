module "waf" {
  source   = "../waf"
  for_each = local.configs

  name_prefix  = local.name_prefixes[each.key]
  resource_arn = aws_lb.this[each.key].arn
  tags         = merge(local.common_tags, try(each.value.tags, {}))
}
