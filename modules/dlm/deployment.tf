locals {
  module_name = basename(path.module)
  stack_name  = basename(abspath(path.root))

  deployment    = reverse(slice(reverse(split("/", abspath(path.root))), 1, 4))
  business_unit = local.deployment[0]
  environment   = local.deployment[1]
  location      = local.deployment[2]
  region        = yamldecode(file("${dirname(abspath(path.root))}/location.yml")).region
  prefix        = join("-", local.deployment)
  path_prefix   = join("/", local.deployment)

  common_tags = merge(try(local.configs["database"].tags, {}), {
    BusinessUnit = local.business_unit
    Environment  = local.environment
    Location     = local.location
    Region       = local.region
    Stack        = local.stack_name
    Module       = local.module_name
    ManagedBy    = "Terraform"
  })
}
