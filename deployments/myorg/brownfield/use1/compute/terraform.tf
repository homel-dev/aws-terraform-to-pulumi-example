terraform {
  required_version = "= 1.16.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 6.67.0"
    }
  }

  backend "s3" {
    key          = "myorg/brownfield/use1/compute/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = "us-east-1"
}

variable "seed_manifest_path" {
  description = "Absolute path to the JSON manifest emitted by aws-brownfield-seed.sh deploy"
  type        = string
}

locals {
  seed         = jsondecode(file(var.seed_manifest_path))
  seed_ids     = local.seed.resources
  name_prefix  = local.seed.name_prefix
  instance_ami = local.seed_ids.ami_id
  seed_tags = {
    MyOrgSeedId = local.seed.seed_id
    ManagedBy    = "myorg-aws-seed"
  }
}
