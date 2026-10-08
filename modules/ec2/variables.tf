variable "allowed_tls_domains" {
  description = "TLS SNI domains declared by this location's firewall stack."
  type        = list(string)
}
