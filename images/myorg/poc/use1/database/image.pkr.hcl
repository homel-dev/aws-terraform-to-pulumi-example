packer {
  required_version = "= 1.16.1"

  required_plugins {
    amazon = {
      version = "= 1.8.2"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

variable "region" {
  type = string
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "source_ami_owner" {
  type    = string
  default = "099720109477"
}

variable "source_ami_name" {
  type    = string
  default = "ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"
}

variable "ami_name_prefix" {
  type    = string
  default = "myorg-poc-use1-database"
}

source "amazon-ebs" "this" {
  region                      = var.region
  instance_type               = var.instance_type
  ssh_username                = "ubuntu"
  associate_public_ip_address = true
  ami_name                    = "${var.ami_name_prefix}-${formatdate("YYYYMMDDhhmmss", timestamp())}"

  source_ami_filter {
    filters = {
      name                  = var.source_ami_name
      "root-device-type"    = "ebs"
      "virtualization-type" = "hvm"
    }
    most_recent = true
    owners      = [var.source_ami_owner]
  }

  subnet_filter {
    filters = {
      "tag:BusinessUnit" = "myorg"
      "tag:Environment"  = "poc"
      "tag:Location"     = "use1"
      "tag:SubnetRole"   = "public"
    }
    most_free = true
    random    = false
  }

  tags = {
    BusinessUnit = "myorg"
    Environment  = "poc"
    Location     = "use1"
    Image        = "database"
    ManagedBy    = "Packer"
  }
}

build {
  sources = ["source.amazon-ebs.this"]

  provisioner "shell" {
    script = "scripts/mysql.sh"
  }

  post-processor "manifest" {
    output     = "manifest.json"
    strip_path = true
  }
}
