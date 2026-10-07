locals {
  schema = yamldecode(file("${path.module}/schema.yml"))

  records_missing_required = {
    for id, config in local.records : id => [
      for field, props in local.schema.record_fields : field
      if try(props.required, false) && !contains(keys(config), field)
    ]
    if length([
      for field, props in local.schema.record_fields : field
      if try(props.required, false) && !contains(keys(config), field)
    ]) > 0
  }

  records_invalid_type = {
    for id, config in local.records : id => [
      for field, props in local.schema.record_fields : field
      if contains(keys(config), field) && (
        props.type == "string" && !can(tostring(config[field])) ||
        props.type == "bool"   && !can(tobool(config[field])) ||
        props.type == "number" && !can(tonumber(config[field])) ||
        props.type == "map"    && !can(keys(config[field])) ||
        props.type == "list"   && !can(tolist(config[field]))
      )
    ]
    if length([
      for field, props in local.schema.record_fields : field
      if contains(keys(config), field) && (
        props.type == "string" && !can(tostring(config[field])) ||
        props.type == "bool"   && !can(tobool(config[field])) ||
        props.type == "number" && !can(tonumber(config[field])) ||
        props.type == "map"    && !can(keys(config[field])) ||
        props.type == "list"   && !can(tolist(config[field]))
      )
    ]) > 0
  }

  records_invalid_enum = {
    for id, config in local.records : id => [
      for field, props in local.schema.record_fields : field
      if try(contains(keys(props), "allowed") && contains(keys(config), field) && !contains(props.allowed, upper(try(tostring(config[field]), ""))), false)
    ]
    if length([
      for field, props in local.schema.record_fields : field
      if try(contains(keys(props), "allowed") && contains(keys(config), field) && !contains(props.allowed, upper(try(tostring(config[field]), ""))), false)
    ]) > 0
  }

  zones_missing_required_tags = {
    for id, config in local.zones : id => [
      for tag in local.schema.zone_required_tags : tag
      if !contains(keys(try(config.tags, {})), tag)
    ]
    if length([
      for tag in local.schema.zone_required_tags : tag
      if !contains(keys(try(config.tags, {})), tag)
    ]) > 0
  }

  zones_invalid_facing = {
    for id, config in local.zones : id => try(config.tags.facing, null)
    if try(config.tags.facing, null) != null && !contains(local.schema.zone_facing_allowed, config.tags.facing)
  }
}

data "validation_error" "records_missing_required" {
  for_each  = local.records_missing_required
  condition = false
  summary   = "${each.key} is missing required fields: ${join(", ", each.value)}"
  details   = "Update the record YAML under ${path.root}/config to match schema.yml."
}

data "validation_error" "records_invalid_type" {
  for_each  = local.records_invalid_type
  condition = false
  summary   = "${each.key} has invalid field types: ${join(", ", each.value)}"
  details   = "Field types must match modules/route53/schema.yml."
}

data "validation_error" "records_invalid_enum" {
  for_each  = local.records_invalid_enum
  condition = false
  summary   = "${each.key} contains unsupported values: ${join(", ", each.value)}"
  details   = "Record values must match modules/route53/schema.yml."
}

data "validation_error" "zones_missing_tags" {
  for_each  = local.zones_missing_required_tags
  condition = false
  summary   = "${each.key} zone missing required tag(s): ${join(", ", each.value)}"
  details   = "All zones must define a facing tag."
}

data "validation_error" "zones_invalid_facing" {
  for_each  = local.zones_invalid_facing
  condition = false
  summary   = "${each.key} zone has invalid facing value: ${each.value}"
  details   = "facing must be one of: ${join(", ", local.schema.zone_facing_allowed)}"
}
