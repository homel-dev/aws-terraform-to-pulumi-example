provider "aws" {
  region = local.config.region

  default_tags {
    tags = local.common_tags
  }
}
