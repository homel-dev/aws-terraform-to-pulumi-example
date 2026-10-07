locals {
  invalid_ingress_allowlist = (
    length(local.config.approved_ingress_cidrs) == 0 ||
    contains(local.config.approved_ingress_cidrs, "0.0.0.0/0")
  )

  invalid_single_instance_poc = !alltrue([
    local.config.application.min_size == 1,
    local.config.application.max_size == 1,
    local.config.application.desired_capacity == 1,
  ])

  invalid_boot_artifact_protocol = !startswith(local.config.application.bootstrap.artifact_url, "https://")
}

data "validation_error" "finite_ingress_allowlist" {
  count     = local.invalid_ingress_allowlist ? 1 : 0
  condition = false
  summary   = "Ingress allowlist is not finite"
  details   = "approved_ingress_cidrs must be non-empty and must not contain 0.0.0.0/0."
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
