locals {
  config     = yamldecode(file("${path.root}/config/guardduty.yml"))
  deployment = reverse(slice(reverse(split("/", abspath(path.root))), 1, 4))
  region     = yamldecode(file("${path.root}/../location.yml")).region
  tags = merge(try(local.config.tags, {}), {
    BusinessUnit = local.deployment[0]
    Environment  = local.deployment[1]
    Location     = local.deployment[2]
    Region       = local.region
    Stack        = "logging"
    Module       = "logging"
    ManagedBy    = "Terraform"
  })
}

provider "aws" {
  region = local.region
}

module "guardduty" {
  source = "../../../../../modules/guardduty"
  tags   = local.tags
}
