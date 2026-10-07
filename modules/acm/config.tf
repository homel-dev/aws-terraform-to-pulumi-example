locals {
  config_path = {
    folder = "config"
    suffix = ".yml"
  }

  certificates = {
    for filename in fileset(join("/", [path.root, local.config_path.folder]), "**") :
    trimsuffix(filename, local.config_path.suffix) => merge(
      local.defaults,
      yamldecode(file(join("/", [path.root, local.config_path.folder, filename])))
    )
    if endswith(filename, local.config_path.suffix)
  }

  regions               = distinct([for _, config in local.certificates : config.region])
  state_bucket_prefixes = distinct([for _, config in local.certificates : config.state_bucket_prefix])
  region                = length(local.regions) == 1 ? local.regions[0] : local.defaults.region
  state_bucket_prefix   = length(local.state_bucket_prefixes) == 1 ? local.state_bucket_prefixes[0] : local.defaults.state_bucket_prefix

  managed_certificates = {
    for id, config in local.certificates : id => config
    if config.mode == "managed_dns"
  }

  imported_certificates = {
    for id, config in local.certificates : id => config
    if config.mode == "imported"
  }
}

data "validation_error" "certificate_config_present" {
  count     = length(local.certificates) > 0 ? 0 : 1
  condition = false
  summary   = "No ACM certificate configuration found"
  details   = "Add at least one *.yml file under ${path.root}/config."
}

data "validation_error" "single_region" {
  count     = length(local.regions) == 1 ? 0 : 1
  condition = false
  summary   = "ACM stack contains multiple regions"
  details   = "All certificate YAML files in one stack must use the same AWS region."
}

data "validation_error" "single_state_bucket_prefix" {
  count     = length(local.state_bucket_prefixes) == 1 ? 0 : 1
  condition = false
  summary   = "ACM stack contains multiple Terraform state bucket prefixes"
  details   = "All certificate YAML files in one stack must use the same state_bucket_prefix."
}
