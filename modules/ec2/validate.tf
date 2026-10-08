locals {
  invalid_ingress_allowlist = (
    length(local.config.approved_ingress_cidrs) == 0 ||
    contains(local.config.approved_ingress_cidrs, "0.0.0.0/0")
  )

  invalid_ingress_cidrs = [
    for cidr in local.config.approved_ingress_cidrs : cidr
    if !can(cidrhost(cidr, 0))
  ]

  invalid_single_instance_poc = !alltrue([
    local.config.application.min_size == 1,
    local.config.application.max_size == 1,
    local.config.application.desired_capacity == 1,
  ])

  invalid_boot_artifact_protocol = !startswith(local.config.application.bootstrap.artifact_url, "https://")
  invalid_runtime_https_protocol = !startswith(local.config.application.runtime_https_url, "https://")

  bootstrap_domain = try(regex("^https://([^/:?#]+)", local.config.application.bootstrap.artifact_url)[0], "")
  runtime_domain   = try(regex("^https://([^/:?#]+)", local.config.application.runtime_https_url)[0], "")
  missing_firewall_domains = [
    for domain in [local.bootstrap_domain, local.runtime_domain] : domain
    if domain == "" || !contains(var.allowed_tls_domains, domain)
  ]
}

data "validation_error" "finite_ingress_allowlist" {
  count     = local.invalid_ingress_allowlist ? 1 : 0
  condition = false
  summary   = "Ingress allowlist is not finite"
  details   = "approved_ingress_cidrs must be non-empty and must not contain 0.0.0.0/0."
}

data "validation_error" "valid_ingress_cidrs" {
  count     = length(local.invalid_ingress_cidrs) > 0 ? 1 : 0
  condition = false
  summary   = "Ingress CIDR syntax is invalid"
  details   = "Invalid approved_ingress_cidrs: ${join(", ", local.invalid_ingress_cidrs)}"
}

data "validation_error" "single_instance_poc" {
  count     = local.invalid_single_instance_poc ? 1 : 0
  condition = false
  summary   = "POC ASG size does not match the scenario"
  details   = "application min_size, max_size, and desired_capacity must all remain 1 on main."
}

data "validation_error" "https_boot_artifact" {
  count     = local.invalid_boot_artifact_protocol ? 1 : 0
  condition = false
  summary   = "Boot artifact URL must use HTTPS"
  details   = "The baseline POC does not allow plaintext artifact retrieval."
}

data "validation_error" "https_runtime_dependency" {
  count     = local.invalid_runtime_https_protocol ? 1 : 0
  condition = false
  summary   = "Runtime dependency must use HTTPS"
  details   = "application.runtime_https_url must begin with https://."
}

data "validation_error" "firewall_domains" {
  count     = length(local.missing_firewall_domains) > 0 ? 1 : 0
  condition = false
  summary   = "Network Firewall does not allow every application dependency"
  details   = "TLS SNI allowlist is missing: ${join(", ", local.missing_firewall_domains)}"
}
