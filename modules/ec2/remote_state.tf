data "aws_caller_identity" "current" {}

locals {
  state_bucket = "${local.config.state_bucket_prefix}-${data.aws_caller_identity.current.account_id}"
}

data "terraform_remote_state" "vpc" {
  backend = "s3"
  config = {
    bucket = local.state_bucket
    key    = "${local.path_prefix}/vpc/terraform.tfstate"
    region = local.config.region
  }
}

data "terraform_remote_state" "iam" {
  backend = "s3"
  config = {
    bucket = local.state_bucket
    key    = "${local.path_prefix}/iam/terraform.tfstate"
    region = local.config.region
  }
}

data "terraform_remote_state" "logging" {
  backend = "s3"
  config = {
    bucket = local.state_bucket
    key    = "${local.path_prefix}/logging/terraform.tfstate"
    region = local.config.region
  }
}


data "terraform_remote_state" "acm" {
  backend = "s3"
  config = {
    bucket = local.state_bucket
    key    = "${local.path_prefix}/acm/terraform.tfstate"
    region = local.config.region
  }
}

locals {
  vpc_state     = data.terraform_remote_state.vpc.outputs
  iam_state     = data.terraform_remote_state.iam.outputs
  logging_state = data.terraform_remote_state.logging.outputs
  acm_state     = data.terraform_remote_state.acm.outputs
}
