resource "aws_acm_certificate" "managed" {
  for_each = local.managed_certificates

  domain_name       = each.value.domain_name
  validation_method = "DNS"
  tags              = merge(local.defaults.tags, try(each.value.tags, {}))

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "validation" {
  for_each = {
    for item in flatten([
      for id, certificate in aws_acm_certificate.managed : [
        for option in certificate.domain_validation_options : {
          key     = "${id}/${option.domain_name}"
          cert_id = id
          zone    = local.managed_certificates[id].zone_name
          name    = option.resource_record_name
          record  = option.resource_record_value
          type    = option.resource_record_type
        }
      ]
    ]) : item.key => item
  }

  allow_overwrite = true
  zone_id         = data.terraform_remote_state.route53[0].outputs.zone_ids[each.value.zone]
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
}

resource "aws_acm_certificate_validation" "managed" {
  for_each = aws_acm_certificate.managed

  certificate_arn = each.value.arn
  validation_record_fqdns = [
    for key, record in aws_route53_record.validation : record.fqdn
    if startswith(key, "${each.key}/")
  ]
}

locals {
  certificate_arns = merge(
    { for id, certificate in aws_acm_certificate_validation.managed : id => certificate.certificate_arn },
    { for id, config in local.imported_certificates : id => config.certificate_arn }
  )
}
