locals {
  schema = yamldecode(file("${path.module}/schema.yml"))

  schema_missing_fields = {
    for id, config in local.vpcs : id => [
      for field, props in local.schema.fields : field
      if try(props.required, false) && !contains(keys(config), field)
    ]
    if length([
      for field, props in local.schema.fields : field
      if try(props.required, false) && !contains(keys(config), field)
    ]) > 0
  }

  schema_invalid_types = {
    for id, config in local.vpcs : id => [
      for field, props in local.schema.fields : field
      if contains(keys(config), field) && (
        props.type == "string" && !can(tostring(config[field])) ||
        props.type == "bool" && !can(tobool(config[field])) ||
        props.type == "number" && !can(tonumber(config[field])) ||
        props.type == "map" && !can(keys(config[field])) ||
        props.type == "list" && !can(tolist(config[field]))
      )
    ]
    if length([
      for field, props in local.schema.fields : field
      if contains(keys(config), field) && (
        props.type == "string" && !can(tostring(config[field])) ||
        props.type == "bool" && !can(tobool(config[field])) ||
        props.type == "number" && !can(tonumber(config[field])) ||
        props.type == "map" && !can(keys(config[field])) ||
        props.type == "list" && !can(tolist(config[field]))
      )
    ]) > 0
  }

  schema_invalid_enums = {
    for id, config in local.vpcs : id => [
      for field, props in local.schema.fields : field
      if try(contains(keys(props), "allowed") && contains(keys(config), field) && !contains(props.allowed, config[field]), false)
    ]
    if length([
      for field, props in local.schema.fields : field
      if try(contains(keys(props), "allowed") && contains(keys(config), field) && !contains(props.allowed, config[field]), false)
    ]) > 0
  }
}

data "validation_error" "schema_required_fields" {
  for_each  = local.schema_missing_fields
  condition = false
  summary   = "${each.key} is missing required configuration fields: ${join(", ", each.value)}"
  details   = "Update that VPC YAML to match ${path.module}/schema.yml."
}

data "validation_error" "schema_invalid_types" {
  for_each  = local.schema_invalid_types
  condition = false
  summary   = "${each.key} has invalid configuration field types: ${join(", ", each.value)}"
  details   = "Field types must match ${path.module}/schema.yml."
}

data "validation_error" "schema_invalid_enums" {
  for_each  = local.schema_invalid_enums
  condition = false
  summary   = "${each.key} has unsupported configuration values: ${join(", ", each.value)}"
  details   = "Allowed values are defined in ${path.module}/schema.yml."
}
