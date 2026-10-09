# An AWS account can have only one GuardDuty detector per Region.
# Import an existing detector before the first apply.
resource "aws_guardduty_detector" "regional" {
  enable = true
  tags   = var.tags
}
