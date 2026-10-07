locals {
  defaults = yamldecode(file("${path.module}/default.yml")).defaults
}
