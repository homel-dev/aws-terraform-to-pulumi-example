output "zone_ids" {
  value = module.route53.zone_ids
}

output "zone_nameservers" {
  value = module.route53.zone_nameservers
}

output "record_fqdns" {
  value = module.route53.record_fqdns
}
