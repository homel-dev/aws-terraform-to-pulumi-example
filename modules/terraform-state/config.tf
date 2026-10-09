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

  bucket_names = {
    for id, config in local.configs : id =>
    "${config.bucket_prefix}${id == "state" ? "" : "-${id}"}-${data.aws_caller_identity.current.account_id}"
  }
}

data "validation_error" "config_present" {
  count     = length(local.configs) > 0 ? 0 : 1
  condition = false
  summary   = "No terraform-state YAML configuration found"
  details   = "Add one YAML per logical resource under ${path.root}/config."
}
