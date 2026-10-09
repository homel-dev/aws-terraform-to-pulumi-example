resource "aws_wafv2_web_acl" "application" {
  for_each = local.configs

  name  = "${local.name_prefixes[each.key]}-alb"
  scope = "REGIONAL"

  default_action {
    allow {}
  }

  rule {
    name     = "AWSManagedRulesAmazonIpReputationList"
    priority = 10

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesAmazonIpReputationList"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name_prefixes[each.key]}-ip-reputation"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 20

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name_prefixes[each.key]}-common"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${local.name_prefixes[each.key]}-alb"
    sampled_requests_enabled   = true
  }

  tags = merge(local.common_tags, try(each.value.tags, {}))
}

resource "aws_wafv2_web_acl_association" "application" {
  for_each = local.configs

  resource_arn = aws_lb.this[each.key].arn
  web_acl_arn  = aws_wafv2_web_acl.application[each.key].arn
}
