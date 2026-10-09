locals {
  config      = yamldecode(file("${path.root}/config/waf.yml"))
  deployment  = reverse(slice(reverse(split("/", abspath(path.root))), 1, 4))
  region      = yamldecode(file("${path.root}/../location.yml")).region
  prefix      = join("-", local.deployment)
  path_prefix = join("/", local.deployment)
  tags = merge(try(local.config.tags, {}), {
    BusinessUnit = local.deployment[0]
    Environment  = local.deployment[1]
    Location     = local.deployment[2]
    Region       = local.region
    Stack        = "ec2"
    Module       = "ec2"
    ManagedBy    = "Terraform"
  })
}

provider "aws" {
  region = local.region
}

data "aws_caller_identity" "current" {}

data "terraform_remote_state" "ec2" {
  backend = "s3"
  config = {
    bucket = "${local.config.state_bucket_prefix}-${data.aws_caller_identity.current.account_id}"
    key    = "${local.path_prefix}/ec2/terraform.tfstate"
    region = local.region
  }
}

module "waf" {
  source       = "../../../../../modules/waf"
  name_prefix  = local.prefix
  resource_arn = data.terraform_remote_state.ec2.outputs.computes[local.config.compute_key].alb_arn
  tags         = local.tags
}
