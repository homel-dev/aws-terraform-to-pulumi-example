data "aws_caller_identity" "current" {}

data "terraform_remote_state" "vpc" {
  backend = "s3"

  config = {
    bucket = "${local.state_bucket_prefix}-${data.aws_caller_identity.current.account_id}"
    key    = "${local.path_prefix}/vpc/terraform.tfstate"
    region = local.region
  }
}

locals {
  vpc_states = {
    for id, config in local.configs : id => data.terraform_remote_state.vpc.outputs.vpcs[config.vpc_key]
  }
}
