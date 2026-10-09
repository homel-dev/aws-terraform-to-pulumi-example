data "aws_caller_identity" "current" {}

locals {
  state_bucket = "${local.state_bucket_prefix}-${data.aws_caller_identity.current.account_id}"
}

data "terraform_remote_state" "vpc" {
  backend = "s3"
  config = {
    bucket = local.state_bucket
    key    = "${local.path_prefix}/vpc/terraform.tfstate"
    region = local.region
  }
}

data "terraform_remote_state" "iam" {
  backend = "s3"
  config = {
    bucket = local.state_bucket
    key    = "${local.path_prefix}/iam/terraform.tfstate"
    region = local.region
  }
}

data "terraform_remote_state" "logging" {
  backend = "s3"
  config = {
    bucket = local.state_bucket
    key    = "${local.path_prefix}/logging/terraform.tfstate"
    region = local.region
  }
}


data "terraform_remote_state" "acm" {
  backend = "s3"
  config = {
    bucket = local.state_bucket
    key    = "${local.path_prefix}/acm/terraform.tfstate"
    region = local.region
  }
}

locals {
  vpc_states = {
    for id, config in local.configs : id => data.terraform_remote_state.vpc.outputs.vpcs[config.vpc_key]
  }
  iam_groups = {
    for id, config in local.configs : id => data.terraform_remote_state.iam.outputs.groups[config.iam_key]
  }
  logging_bundles = {
    for id, config in local.configs : id => data.terraform_remote_state.logging.outputs.loggings[config.logging_key]
  }
  acm_certificates = {
    # Preexisting ACM state can expose only the legacy singular output.
    # Keep that state readable until the ACM root has published its map.
    for id, config in local.configs : id => try(
      data.terraform_remote_state.acm.outputs.certificate_arns[config.acm_key],
      data.terraform_remote_state.acm.outputs.certificate_arn
    )
  }
}
