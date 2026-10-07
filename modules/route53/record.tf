resource "aws_route53_record" "standard" {
  for_each = {
    for key, value in local.records : key => value
    if !contains(keys(value), "alias")
  }

  zone_id = aws_route53_zone.this[each.value.zone].zone_id
  name    = each.value.name
  type    = upper(each.value.type)
  ttl     = each.value.ttl
  records = each.value.values

  set_identifier                   = try(each.value.set_identifier, null)
  multivalue_answer_routing_policy = try(each.value.multivalue_answer_routing_policy, null)
  health_check_id                  = try(each.value.health_check_id, null)
}

resource "aws_route53_record" "alias" {
  for_each = {
    for key, value in local.records : key => value
    if contains(keys(value), "alias")
  }

  zone_id = aws_route53_zone.this[each.value.zone].zone_id
  name    = each.value.name
  type    = upper(each.value.type)

  alias {
    name                   = each.value.alias.name
    zone_id                = each.value.alias.zone_id
    evaluate_target_health = try(each.value.alias.evaluate_target_health, false)
  }

  set_identifier                   = try(each.value.set_identifier, null)
  multivalue_answer_routing_policy = try(each.value.multivalue_answer_routing_policy, null)
  health_check_id                  = try(each.value.health_check_id, null)
}
