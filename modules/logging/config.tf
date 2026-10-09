locals {
  config_path = {
    folder = "config"
    suffix = ".yml"
  }

  configs = {
    for filename in fileset(join("/", [path.root, local.config_path.folder]), "**") :
    trimsuffix(filename, local.config_path.suffix) => merge(
      local.defaults,
      yamldecode(file(join("/", [path.root, local.config_path.folder, filename])))
    )
    if endswith(filename, local.config_path.suffix)
  }
  state_bucket_prefixes = distinct([for _, config in local.configs : config.state_bucket_prefix])
  state_bucket_prefix   = length(local.state_bucket_prefixes) == 1 ? local.state_bucket_prefixes[0] : local.defaults.state_bucket_prefix

  flow_log_configs = {
    for id, config in local.configs : id => config if config.vpc_flow_logs_enabled
  }
  cloudtrail_configs = {
    for id, config in local.configs : id => config if config.cloudtrail_enabled
  }
}

data "validation_error" "config_present" {
  count     = length(local.configs) > 0 ? 0 : 1
  condition = false
  summary   = "No logging YAML configuration found"
  details   = "Add one YAML per logical resource under ${path.root}/config."
}

data "validation_error" "single_state_bucket_prefix" {
  count     = length(local.state_bucket_prefixes) == 1 ? 0 : 1
  condition = false
  summary   = "logging YAML files must share one state bucket prefix"
  details   = "All configs in a location stack read the same remote-state bucket."
}
