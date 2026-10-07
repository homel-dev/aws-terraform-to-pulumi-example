terraform {
  required_version = "= 1.16.5"
  backend "s3" {
    key          = "myorg/poc/use1/iam/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
