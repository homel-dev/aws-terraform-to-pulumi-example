locals {
  schema = yamldecode(file("${path.module}/schema.yml"))

  schema_missing_fields = [
    for field, props in local.schema.fields : field
    if try(props.required, false) && !contains(keys(local.config), field)
  ]

  schema_invalid_types = [
    for field, props in local.schema.fields : field
    if contains(keys(local.config), field) && (
      props.type == "string" && !can(tostring(local.config[field])) ||
      props.type == "bool"   && !can(tobool(local.config[field])) ||
      props.type == "number" && !can(tonumber(local.config[field])) ||
      props.type == "map"    && !can(keys(local.config[field])) ||
      props.type == "list"   && !can(tolist(local.config[field]))
    )
  ]

  schema_invalid_enums = [
    for field, props in local.schema.fields : field
    if try(
      contains(keys(props), "allowed") &&
      contains(keys(local.config), field) &&
      !contains(props.allowed, local.config[field]),
      false
    )
  ]
}

data "validation_error" "schema_required_fields" {
  count     = length(local.schema_missing_fields) > 0 ? 1 : 0
  condition = false
  summary   = "Missing required configuration fields: ${join(", ", local.schema_missing_fields)}"
  details   = "Update the YAML under ${path.root}/config to match ${path.module}/schema.yml."
}

data "validation_error" "schema_invalid_types" {
  count     = length(local.schema_invalid_types) > 0 ? 1 : 0
  condition = false
  summary   = "Invalid configuration field types: ${join(", ", local.schema_invalid_types)}"
  details   = "Field types must match ${path.module}/schema.yml."
}

data "validation_error" "schema_invalid_enums" {
  count     = length(local.schema_invalid_enums) > 0 ? 1 : 0
  condition = false
  summary   = "Unsupported configuration values: ${join(", ", local.schema_invalid_enums)}"
  details   = "Allowed values are defined in ${path.module}/schema.yml."
}
