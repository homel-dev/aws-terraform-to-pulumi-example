data "validation_error" "domain_allowlist" {
  count     = length(local.config.allowed_tls_domains) >= 2 ? 0 : 1
  condition = false
  summary   = "Firewall TLS allowlist is incomplete"
  details   = "The POC requires at least the boot-artifact host and the runtime HTTPS host."
}
