output "certificate_arns" {
  description = "Map of certificate IDs to ACM ARNs."
  value       = local.certificate_arns
}

output "certificate_arn" {
  description = "Single certificate ARN for the POC stack."
  value       = length(local.certificate_arns) == 1 ? values(local.certificate_arns)[0] : null
}
