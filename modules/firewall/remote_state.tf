data "aws_caller_identity" "current" {}

data "terraform_remote_state" "vpc" {
  backend = "s3"

  config = {
    bucket = "${local.config.state_bucket_prefix}-${data.aws_caller_identity.current.account_id}"
    key    = "${local.path_prefix}/vpc/terraform.tfstate"
    region = local.config.region
  }
}

locals {
  vpc_state = data.terraform_remote_state.vpc.outputs
}
