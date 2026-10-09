locals {
  config      = yamldecode(file("${path.root}/config/database.yml"))
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

data "terraform_remote_state" "vpc" {
  backend = "s3"
  config = {
    bucket = "${local.config.state_bucket_prefix}-${data.aws_caller_identity.current.account_id}"
    key    = "${local.path_prefix}/vpc/terraform.tfstate"
    region = local.region
  }
}

data "terraform_remote_state" "ec2" {
  backend = "s3"
  config = {
    bucket = "${local.config.state_bucket_prefix}-${data.aws_caller_identity.current.account_id}"
    key    = "${local.path_prefix}/ec2/terraform.tfstate"
    region = local.region
  }
}

locals {
  vpc     = data.terraform_remote_state.vpc.outputs.vpcs[local.config.vpc_key]
  compute = data.terraform_remote_state.ec2.outputs.computes[local.config.compute_key]
}

module "rds" {
  source = "../../../../../modules/rds"

  name_prefix                   = local.prefix
  vpc_id                        = local.vpc.vpc_id
  subnet_ids                    = [local.vpc.subnet_ids[local.config.subnet], local.vpc.subnet_ids[local.config.standby_subnet]]
  application_security_group_id = local.compute.application_security_group_id
  migration_security_group_id   = local.compute.database_security_group_id
  db_name                       = local.config.database_name
  port                          = local.config.port
  engine_version                = local.config.engine_version
  instance_class                = local.config.instance_class
  allocated_storage_gib         = local.config.allocated_storage_gib
  master_username               = local.config.master_username
  backup_retention_days         = local.config.backup_retention_days
  tags                          = local.tags
}
