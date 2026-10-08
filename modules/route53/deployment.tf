locals {
  deployment  = reverse(slice(reverse(split("/", abspath(path.root))), 1, 4))
  prefix      = join("-", local.deployment)
  system      = local.deployment[0]
  environment = local.deployment[1]
  region_code = local.deployment[2]
  name        = basename(path.module)
  path_prefix = join("/", local.deployment)

  common_tags = merge(local.defaults.tags, {
    BusinessUnit = local.system
    Environment  = local.environment
    Location     = local.region_code
    Stack        = basename(path.root)
    Module       = local.name
    ManagedBy    = "Terraform"
  })
}
