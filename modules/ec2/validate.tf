locals {
  invalid_ingress_allowlist = {
    for id, config in local.configs : id => config
    if length(config.approved_ingress_cidrs) == 0 || contains(config.approved_ingress_cidrs, "0.0.0.0/0")
  }
  invalid_ingress_cidrs = {
    for id, config in local.configs : id => [
      for cidr in config.approved_ingress_cidrs : cidr if !can(cidrhost(cidr, 0))
    ]
    if length([for cidr in config.approved_ingress_cidrs : cidr if !can(cidrhost(cidr, 0))]) > 0
  }
  invalid_single_instance_poc = {
    for id, config in local.configs : id => config
    if !alltrue([
      config.application.min_size == 1,
      config.application.max_size == 1,
      config.application.desired_capacity == 1,
    ])
  }
  invalid_boot_artifact_protocol = {
    for id, config in local.configs : id => config
    if !startswith(config.application.bootstrap.artifact_url, "https://")
  }
  invalid_runtime_https_protocol = {
    for id, config in local.configs : id => config
    if !startswith(config.application.runtime_https_url, "https://")
  }
  required_firewall_domains = {
    for id, config in local.configs : id => [
      try(regex("^https://([^/:?#]+)", config.application.bootstrap.artifact_url)[0], ""),
      try(regex("^https://([^/:?#]+)", config.application.runtime_https_url)[0], ""),
    ]
  }
  missing_firewall_domains = {
    for id, domains in local.required_firewall_domains : id => [
      for domain in domains : domain if domain == "" || !contains(var.allowed_tls_domains, domain)
    ]
    if length([for domain in domains : domain if domain == "" || !contains(var.allowed_tls_domains, domain)]) > 0
  }
}

data "validation_error" "finite_ingress_allowlist" {
  for_each  = local.invalid_ingress_allowlist
  condition = false
  summary   = "${each.key}: ingress allowlist is not finite"
  details   = "approved_ingress_cidrs must be non-empty and must not contain 0.0.0.0/0."
}

data "validation_error" "valid_ingress_cidrs" {
  for_each  = local.invalid_ingress_cidrs
  condition = false
  summary   = "${each.key}: ingress CIDR syntax is invalid"
  details   = "Invalid approved_ingress_cidrs: ${join(", ", each.value)}"
}

data "validation_error" "single_instance_poc" {
  for_each  = local.invalid_single_instance_poc
  condition = false
  summary   = "${each.key}: POC ASG size does not match the scenario"
  details   = "application min_size, max_size, and desired_capacity must all remain 1 on main."
}

data "validation_error" "https_boot_artifact" {
  for_each  = local.invalid_boot_artifact_protocol
  condition = false
  summary   = "${each.key}: boot artifact URL must use HTTPS"
  details   = "The baseline POC does not allow plaintext artifact retrieval."
}

data "validation_error" "https_runtime_dependency" {
  for_each  = local.invalid_runtime_https_protocol
  condition = false
  summary   = "${each.key}: runtime dependency must use HTTPS"
  details   = "application.runtime_https_url must begin with https://."
}

data "validation_error" "firewall_domains" {
  for_each  = local.missing_firewall_domains
  condition = false
  summary   = "${each.key}: Network Firewall does not allow every application dependency"
  details   = "TLS SNI allowlist is missing: ${join(", ", each.value)}"
}
