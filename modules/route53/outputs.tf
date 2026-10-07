output "zone_ids" {
  description = "Map of managed Route53 zone names to hosted-zone IDs."
  value = {
    for zone_name, zone_resource in aws_route53_zone.this :
    zone_name => zone_resource.zone_id
  }
}

output "zone_nameservers" {
  description = "Map of public zones to delegated nameservers."
  value = {
    for zone_name, zone_resource in aws_route53_zone.this :
    zone_name => zone_resource.name_servers
    if zone_resource.name_servers != null
  }
}

output "record_fqdns" {
  description = "Map of record keys to FQDNs."
  value = merge(
    { for key, record in aws_route53_record.standard : key => record.fqdn },
    { for key, record in aws_route53_record.alias : key => record.fqdn }
  )
}
