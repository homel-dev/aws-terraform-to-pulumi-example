locals {
  config_path = {
    folder = "config"
    suffix = ".yml"
  }

  stack_configs = {
    for filename in fileset(join("/", [path.root, local.config_path.folder]), "**") :
    trimsuffix(filename, local.config_path.suffix) => merge(
      local.defaults,
      yamldecode(file(join("/", [path.root, local.config_path.folder, filename])))
    )
    if endswith(filename, local.config_path.suffix)
  }

  config_values = values(local.stack_configs)
  config        = length(local.config_values) == 1 ? local.config_values[0] : local.defaults
}

data "validation_error" "single_stack_config" {
  count     = length(local.stack_configs) == 1 ? 0 : 1
  condition = false
  summary   = "terraform-state stack requires exactly one YAML configuration file"
  details   = "Expected exactly one *.yml file under ${path.root}/config; found ${length(local.stack_configs)}."
}
