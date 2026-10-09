provider "aws" {
  region = local.region

  default_tags {
    tags = {
      BusinessUnit = local.system
      Environment  = local.environment
      Location     = local.region_code
      Stack        = basename(abspath(path.root))
      Module       = local.name
      ManagedBy    = "Terraform"
    }
  }
}
