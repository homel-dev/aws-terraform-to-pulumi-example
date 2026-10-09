moved {
  from = aws_iam_role.application
  to   = aws_iam_role.application["instances"]
}

moved {
  from = aws_iam_role.database
  to   = aws_iam_role.database["instances"]
}

moved {
  from = aws_iam_role_policy_attachment.application_ssm[0]
  to   = aws_iam_role_policy_attachment.application_ssm["instances"]
}

moved {
  from = aws_iam_role_policy_attachment.database_ssm[0]
  to   = aws_iam_role_policy_attachment.database_ssm["instances"]
}

moved {
  from = aws_iam_role_policy.application_secret
  to   = aws_iam_role_policy.application_secret["instances"]
}

moved {
  from = aws_iam_role_policy.database_secret
  to   = aws_iam_role_policy.database_secret["instances"]
}

moved {
  from = aws_iam_instance_profile.application
  to   = aws_iam_instance_profile.application["instances"]
}

moved {
  from = aws_iam_instance_profile.database
  to   = aws_iam_instance_profile.database["instances"]
}
