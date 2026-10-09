module "guardduty" {
  source = "../guardduty"
  tags   = local.common_tags
}
