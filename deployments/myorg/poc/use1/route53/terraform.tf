terraform {
  required_version = "= 1.16.5"

  backend "s3" {
    key          = "myorg/poc/use1/route53/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
