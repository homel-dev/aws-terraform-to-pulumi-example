# GuardDuty has one detector per AWS account and Region. If one already exists,
# import it into this address before running the audit-hardening apply.
resource "aws_guardduty_detector" "regional" {
  enable = true

  tags = local.common_tags
}
