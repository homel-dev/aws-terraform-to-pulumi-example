data "validation_error" "domain_allowlist" {
  for_each  = { for id, config in local.configs : id => config if length(config.allowed_tls_domains) < 2 }
  condition = false
  summary   = "Firewall TLS allowlist is incomplete"
  details   = "The POC requires at least the boot-artifact host and the runtime HTTPS host."
}
