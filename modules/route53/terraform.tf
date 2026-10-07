terraform {
  required_version = "= 1.16.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 6.67.0"
    }
    validation = {
      source  = "tlkamp/validation"
      version = "= 1.1.3"
    }
    random = {
      source  = "hashicorp/random"
      version = "= 3.7.1"
    }
  }
}
