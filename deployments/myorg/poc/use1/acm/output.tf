output "certificate_arn" {
  value = module.acm.certificate_arn
}

output "certificate_arns" {
  description = "Certificate ARNs keyed by config filename, for downstream stacks."
  value       = module.acm.certificate_arns
}
