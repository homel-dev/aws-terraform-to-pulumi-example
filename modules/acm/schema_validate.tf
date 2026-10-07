locals {
  schema = yamldecode(file("${path.module}/schema.yml"))

  schema_missing_required = {
    for id, config in local.certificates : id => [
      for field, props in local.schema.fields : field
      if try(props.required, false) && !contains(keys(config), field)
    ]
    if length([
      for field, props in local.schema.fields : field
      if try(props.required, false) && !contains(keys(config), field)
    ]) > 0
  }

  schema_invalid_types = {
    for id, config in local.certificates : id => [
      for field, props in local.schema.fields : field
      if contains(keys(config), field) && (
        props.type == "string" && !can(tostring(config[field])) ||
        props.type == "bool"   && !can(tobool(config[field])) ||
        props.type == "number" && !can(tonumber(config[field])) ||
        props.type == "map"    && !can(keys(config[field])) ||
        props.type == "list"   && !can(tolist(config[field]))
      )
    ]
    if length([
      for field, props in local.schema.fields : field
      if contains(keys(config), field) && (
        props.type == "string" && !can(tostring(config[field])) ||
        props.type == "bool"   && !can(tobool(config[field])) ||
        props.type == "number" && !can(tonumber(config[field])) ||
        props.type == "map"    && !can(keys(config[field])) ||
        props.type == "list"   && !can(tolist(config[field]))
      )
    ]) > 0
  }

  schema_invalid_enums = {
    for id, config in local.certificates : id => [
      for field, props in local.schema.fields : field
      if try(contains(keys(props), "allowed") && contains(keys(config), field) && !contains(props.allowed, config[field]), false)
    ]
    if length([
      for field, props in local.schema.fields : field
      if try(contains(keys(props), "allowed") && contains(keys(config), field) && !contains(props.allowed, config[field]), false)
    ]) > 0
  }

  invalid_mode_contract = {
    for id, config in local.certificates : id => config.mode
    if (
      config.mode == "managed_dns" && (try(config.domain_name, "") == "" || try(config.zone_name, "") == "")
    ) || (
      config.mode == "imported" && try(config.certificate_arn, "") == ""
    )
  }
}

data "validation_error" "schema_required_fields" {
  for_each  = local.schema_missing_required
  condition = false
  summary   = "${each.key} is missing required fields: ${join(", ", each.value)}"
  details   = "Update the ACM YAML file to match modules/acm/schema.yml."
}

data "validation_error" "schema_invalid_types" {
  for_each  = local.schema_invalid_types
  condition = false
  summary   = "${each.key} has invalid field types: ${join(", ", each.value)}"
  details   = "Field types must match modules/acm/schema.yml."
}

data "validation_error" "schema_invalid_enums" {
  for_each  = local.schema_invalid_enums
  condition = false
  summary   = "${each.key} contains unsupported values: ${join(", ", each.value)}"
  details   = "Allowed values are defined in modules/acm/schema.yml."
}

data "validation_error" "mode_contract" {
  for_each  = local.invalid_mode_contract
  condition = false
  summary   = "${each.key} does not satisfy the ${each.value} ACM mode contract"
  details   = "managed_dns requires domain_name + zone_name; imported requires certificate_arn."
}
