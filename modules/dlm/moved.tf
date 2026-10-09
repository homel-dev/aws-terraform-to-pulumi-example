moved {
  from = aws_iam_role.this[0]
  to   = aws_iam_role.this["database"]
}

moved {
  from = aws_iam_role_policy_attachment.this[0]
  to   = aws_iam_role_policy_attachment.this["database"]
}

moved {
  from = aws_dlm_lifecycle_policy.database[0]
  to   = aws_dlm_lifecycle_policy.database["database"]
}
